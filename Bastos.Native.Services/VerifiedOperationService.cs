using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Threading;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

// Workers opt into this protocol. The caller chooses the timeout/termination policy;
// destructive workers must not be forcibly terminated.
public sealed class VerifiedOperationService(string logRoot,
    Func<string, IReadOnlyList<string>, Task<CommandResult>> runWorker,
    Action<string, string, bool> writeLog)
{
    private readonly ConcurrentDictionary<string, SemaphoreSlim> gates = new();
    public Task<OperationResult> RunAsync(string name, string script, IReadOnlyList<string> arguments,
        Func<JsonElement, Task<OperationVerification>> verify, IProgress<WorkerProgress>? progress = null, string? concurrencyKey = null, OperationResumeIntent? resumeIntent = null)
        => RunCoreAsync(name, "worker|" + (concurrencyKey ?? script + "|" + JsonSerializer.Serialize(arguments)),
            (result, progressPath, _) => runWorker(script, arguments.Concat(new[] { "-OperationId", result.OperationId,
                "-ResultPath", result.WorkerReportPath, "-ProgressPath", progressPath }).ToArray()), verify, progress, false, resumeIntent);

    public Task<OperationResult> RunNativeAsync(string name, string actionKey,
        Func<IProgress<WorkerProgress>, Task<NativeOperationReport>> execute,
        Func<JsonElement, Task<OperationVerification>> verify, IProgress<WorkerProgress>? progress = null, OperationResumeIntent? resumeIntent = null)
        => RunCoreAsync(name, "native|" + actionKey, async (result, _, reporter) =>
        {
            var report = await execute(reporter);
            var payload = new Dictionary<string, object?>(report.Data) {
                ["SchemaVersion"] = 1, ["OperationId"] = result.OperationId, ["Success"] = report.Success,
                ["Message"] = report.Message, ["ErrorCode"] = report.ErrorCode, ["TechnicalDetail"] = report.TechnicalDetail
            };
            string temporary = result.WorkerReportPath + ".tmp";
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(payload));
            File.Move(temporary, result.WorkerReportPath, true);
            return new CommandResult(report.Success, report.Success ? 0 : 1, "", report.TechnicalDetail);
        }, verify, progress, true, resumeIntent);

    private async Task<OperationResult> RunCoreAsync(string name, string key,
        Func<OperationResult, string, IProgress<WorkerProgress>, Task<CommandResult>> execute,
        Func<JsonElement, Task<OperationVerification>> verify, IProgress<WorkerProgress>? progress, bool native, OperationResumeIntent? resumeIntent)
    {
        string id = Guid.NewGuid().ToString("N");
        string directory = Path.Combine(logRoot, "Operations");
        var result = new OperationResult { OperationId = id, Name = name, ExecutionKind = native ? "Native" : "PowerShell", StartedUtc = DateTime.UtcNow,
            OwnerProcessId = Environment.ProcessId, OwnerProcessStartedUtc = OperationTrackingService.ProcessStartedUtc(),
            BootStamp = await OperationTrackingService.ReadBootAsync() ?? "",
            OperationKey = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(key))),
            State = OperationState.Running, Message = "Opération en cours.", ExecutionStarted = false, ResumeIntent = resumeIntent,
            JournalPath = Path.Combine(directory, id + ".operation.json"), WorkerReportPath = Path.Combine(directory, id + ".worker.json") };
        string progressPath = Path.Combine(directory, id + ".progress.txt");
        var gate = gates.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
        if (!await gate.WaitAsync(0))
            return await Finish(result, OperationState.Failed, "OPERATION_BUSY", "Cette opération est déjà en cours ou son arrêt n’a pas été confirmé. Consulte son journal avant de la relancer.");
        bool releaseGate = true;
        FileStream? sessionLease = null;
        try
        {
            Directory.CreateDirectory(directory);
            await Save(result);
            sessionLease = AcquireSessionLease(directory,result);
            if(sessionLease==null)
            {
                gate.Release();
                return await Finish(result,OperationState.Failed,"OPERATION_BUSY","Une tentative précédente est encore active ou sa fin reste inconnue. Ouvre Journal pour vérifier ses éléments avant de poursuivre.");
            }
            writeLog("Opération", $"[{id}] {name} — démarrage", false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            sessionLease?.Dispose();
            gate.Release();
            result = result with { State = OperationState.Failed, ErrorCode = "JOURNAL_UNWRITABLE", EndedUtc = DateTime.UtcNow,
                Message = "Impossible de créer le journal. Vérifie l’accès au dossier des journaux ; aucune action n’a été lancée.", TechnicalDetail = error.Message };
            try { await Save(result); } catch (Exception retry) when (retry is IOException or UnauthorizedAccessException) { }
            return result;
        }
        try
        {
            var reporter = new CallbackProgress(value => {
                result = result with { Phase = value.Phase };
                progress?.Report(value with { Percent = Math.Clamp(value.Percent, 0, 99) });
            });
            string savedPhase = result.Phase;
            DateTime savedAt = DateTime.UtcNow;
            result = result with { ExecutionStarted = true };
            await Save(result);
            Task<CommandResult> running = execute(result, progressPath, reporter);
            string last = "";
            while (!running.IsCompleted)
            {
                try
                {
                    if (File.Exists(progressPath))
                    {
                        string snapshot = await File.ReadAllTextAsync(progressPath);
                        var parts = snapshot.TrimStart('\ufeff').Split('\t', 5);
                        if (snapshot != last && parts.Length >= 3 && int.TryParse(parts[0], out int percent))
                        {
                            last = snapshot;
                            result = result with { Phase = parts[1] };
                            int step = parts.Length >= 4 && int.TryParse(parts[3], out int number) ? number : 0;
                            int total = parts.Length >= 5 && int.TryParse(parts[4], out int steps) ? steps : 0;
                            progress?.Report(new WorkerProgress(Math.Clamp(percent, 0, 99), parts[1], parts[2], step, total));
                        }
                    }
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
                if (result.Phase != savedPhase && DateTime.UtcNow - savedAt >= TimeSpan.FromSeconds(1))
                {
                    try { await Save(result); savedPhase = result.Phase; savedAt = DateTime.UtcNow; }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
                }
                await Task.WhenAny(running, Task.Delay(150));
            }
            var process = await running;
            releaseGate = process.ProcessStopped;
            result = result with { WorkerExitCode = native ? null : process.ExitCode, ProcessStopped = process.ProcessStopped };
            if (process.ExecutionBlocked)
                return await Finish(result with { ExecutionStarted = false, Phase = "Contrôle des fichiers", Checks = new[] { new OperationCheck("Fichiers du moteur", false, process.Error) } },
                    OperationState.Failed, process.ErrorCode, process.Error, process.Error);
            if (process.ExitCode == 1223)
                return await Finish(result, OperationState.Cancelled, "ADMIN_CANCELLED", "Autorisation administrateur annulée. Relance l’action et accepte la demande Windows si tu souhaites continuer.", process.Error);
            if (process.ExitCode == -2)
                return await Finish(result, process.ProcessStopped ? OperationState.TimedOut : OperationState.Unconfirmed,
                    process.ProcessStopped ? "TIMEOUT_STOPPED" : "TIMEOUT_UNCONFIRMED",
                    process.ProcessStopped ? "Le délai maximal est dépassé et le processus a été arrêté. Tu peux réessayer."
                    : "Le délai maximal est dépassé. L’arrêt du processus n’est pas confirmé : vérifie son état avant de relancer.", process.Error);
            if (!File.Exists(result.WorkerReportPath))
                return await Finish(result, process.Success ? OperationState.Unconfirmed : OperationState.Failed, "REPORT_MISSING",
                    process.Success ? "Résultat impossible à confirmer : le rapport attendu est absent."
                    : "L’opération a échoué avant de fournir son rapport. Consulte le journal avant de réessayer.", process.Error);
            if (new FileInfo(result.WorkerReportPath).Length > 16 * 1024 * 1024)
                return await Finish(result, OperationState.Unconfirmed, "REPORT_TOO_LARGE", "Résultat impossible à confirmer : le rapport dépasse la taille autorisée.");
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(result.WorkerReportPath));
            var payload = document.RootElement;
            if (payload.ValueKind != JsonValueKind.Object || !payload.TryGetProperty("SchemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out int version) || version != 1 ||
                !payload.TryGetProperty("OperationId", out var operation) || operation.ValueKind != JsonValueKind.String || operation.GetString() != id ||
                !payload.TryGetProperty("Success", out var success) || success.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                return await Finish(result, OperationState.Unconfirmed, "REPORT_INVALID", "Résultat impossible à confirmer : le rapport est incomplet ou ne correspond pas à cette opération.");
            result = result with { Payload = payload.Clone(), Checks = new[] { new OperationCheck("Rapport de l’opération", true, "Identifiant, version du protocole et état contrôlés.") } };
            result = result with { RestartRequired =
                (payload.TryGetProperty("RestartRequired", out var restart) && restart.ValueKind == JsonValueKind.True) ||
                (payload.TryGetProperty("InstallerExitCode", out var installerExit) && installerExit.ValueKind == JsonValueKind.Number && installerExit.TryGetInt32(out int exit) && exit == 3010) ||
                (payload.TryGetProperty("ErrorCode", out var restartCode) && restartCode.ValueKind == JsonValueKind.String && restartCode.GetString() == "ADK_RESTART_REQUIRED") };
            if (payload.TryGetProperty("ActionCompletionUnconfirmed", out var pending) && pending.ValueKind == JsonValueKind.True)
            {
                releaseGate = false;
                result = result with { ActionCompletionUnconfirmed = true };
                return await Finish(result, OperationState.Unconfirmed, "ACTION_COMPLETION_UNCONFIRMED",
                    "La fin de l’opération « " + result.Name + " » n’est pas confirmée. Aucun arrêt forcé n’a été demandé. Attends puis vérifie son état dans Windows avant de relancer ; le journal conserve les détails.");
            }
            if (!process.Success || !success.GetBoolean())
            {
                if (process.ExitCode == 2 && payload.TryGetProperty("Cancelled", out var cancelled) && cancelled.ValueKind == JsonValueKind.True)
                {
                    string scope = payload.TryGetProperty("CancellationScope", out var scopeValue) && scopeValue.ValueKind == JsonValueKind.String ? scopeValue.GetString() ?? "" : "";
                    bool clean = process.ProcessStopped && payload.TryGetProperty("CancellationCleanupVerified", out var cleanup) && cleanup.ValueKind == JsonValueKind.True;
                    if (!clean || scope is not ("IsoBuildCheckpoint" or "RecoveryBeforeWrites"))
                        return await Finish(result, OperationState.Unconfirmed, "CANCELLATION_CLEANUP_UNCONFIRMED", "Annulation demandée ; l’arrêt au point sûr ou le nettoyage ne sont pas confirmés.");
                    return await Finish(result, OperationState.Cancelled, scope == "RecoveryBeforeWrites" ? "RECOVERY_CANCELLED" : "OPERATION_CANCELLED",
                        scope == "RecoveryBeforeWrites" ? "Préparation annulée avant les écritures Recovery. L’ISO est démontée ; des fichiers de profil temporaires peuvent subsister."
                        : "Création de l’ISO annulée ; montages libérés et sortie incomplète supprimée si elle avait été créée par cette tentative.");
                }
                if (payload.TryGetProperty("ErrorCode", out var cancellationCode) && cancellationCode.ValueKind == JsonValueKind.String && cancellationCode.GetString() == "CANCELLATION_CLEANUP_UNCONFIRMED")
                    return await Finish(result, OperationState.Unconfirmed, "CANCELLATION_CLEANUP_UNCONFIRMED", "Annulation demandée ; le nettoyage des montages ou des fichiers reste à vérifier dans Journal.");
                if (native)
                    return await Finish(result, OperationState.Failed, payload.GetProperty("ErrorCode").GetString() is { Length: > 0 } code ? code : "NATIVE_FAILED",
                        payload.GetProperty("Message").GetString() ?? "L’opération a échoué. Consulte le journal.", process.Error);
                string detail = (payload.TryGetProperty("Message", out var message) ? message.ToString() : payload.TryGetProperty("Error", out var error) ? error.ToString() : "") + "\n" + process.Error;
                string reportedCode = payload.TryGetProperty("ErrorCode", out var failure) && failure.ValueKind == JsonValueKind.String ? failure.GetString() ?? "" : "";
                string? specificHint = reportedCode switch {
                    "DISK_PLAN_MISSING" or "DISK_PLAN_CHANGED" => "Le plan des disques n’est plus validé. Ouvre Compte, nom du PC, nettoyage et partitions, vérifie les cibles puis enregistre les options. Aucune réinstallation ne sera lancée.",
                    "RECOVERY_PROFILE_FAILED" => "Le profil d’installation n’a pas pu être créé. Vérifie l’ISO et les options enregistrées, puis consulte le Journal.",
                    "RECOVERY_PREPARATION_FAILED" => "La préparation Recovery n’a pas abouti à l’étape « " + result.Phase + " ». Aucun redémarrage demandé. Consulte le Journal avant de réessayer.",
                    "RECOVERY_BOOT_FAILED" => "Le démarrage Recovery n’a pas été confirmé. Aucun redémarrage demandé par Bastos. Consulte le Journal pour le résultat de la neutralisation.",
                    "ADK_RESTART_REQUIRED" => "Les outils ADK demandent un redémarrage de Windows. Redémarre le PC avant de relancer la création d’ISO.",
                    "ADK_PATCH_UNCONFIRMED" => "Windows Installer ne confirme pas les composants applicables du correctif ADK. La création d’ISO reste bloquée ; consulte les journaux MSI puis répare le correctif depuis Microsoft.",
                    "ADK_VERSION_UNSUPPORTED" => "La révision ADK détectée n’est pas validée par cette version de Bastos. Utilise ADK 10.1.26100.9457 ou la base 10.1.26100.2454 avec son correctif vérifié.",
                    "WEBVIEW2_LINK_REFUSED" => "Le lien de l’installateur ne correspond pas au bootstrapper Microsoft autorisé. Répare les fichiers de Bastos ; aucun installateur n’a été exécuté.",
                    "WEBVIEW2_DOWNLOAD_FAILED" => "Le téléchargement de WebView2 n’a pas pu être validé. Vérifie la connexion Internet puis réessaie ; aucun installateur n’a été exécuté.",
                    "WEBVIEW2_SIGNATURE_INVALID" => "La signature Microsoft du bootstrapper n’a pas pu être validée. L’installateur n’a pas été exécuté.",
                    "WEBVIEW2_INSTALL_FAILED" => "Windows n’a pas pu terminer l’installation de WebView2. Vérifie la connexion et les droits d’installation. " +
                        (payload.TryGetProperty("InstallerExitCode", out var installerCode) && installerCode.ValueKind == JsonValueKind.Number ? "Code de l’installateur : " + installerCode + "." : "Consulte le journal pour le détail."),
                    "WEBVIEW2_DETECTION_FAILED" => "La détection de WebView2 n’a pas abouti. Vérifie les droits d’accès et les fichiers de Bastos puis réessaie.",
                    _ => null
                };
                if (specificHint != null) return await Finish(result, OperationState.Failed, reportedCode, specificHint, detail);
                string hint = detail.Contains("liste blanche", StringComparison.OrdinalIgnoreCase) ? "Le lien a été refusé car son domaine ne figure pas dans les sources officielles. Aucun navigateur n’a été ouvert."
                    : detail.Contains("dossier temporaire", StringComparison.OrdinalIgnoreCase) || detail.Contains("dossier TEMP", StringComparison.OrdinalIgnoreCase) ? "Le dossier temporaire est absent ou redirigé. Vérifie les dossiers TEMP dans Windows puis relance l’analyse."
                    : detail.Contains("signature", StringComparison.OrdinalIgnoreCase) ? "La signature du fichier n’a pas pu être validée. Le fichier ne sera pas ouvert."
                    : detail.Contains("taille", StringComparison.OrdinalIgnoreCase) ? "Le téléchargement est incomplet ou sa taille est incorrecte. Vérifie la connexion puis réessaie."
                    : new[] { "network", "connect", "resolve", "SSL", "TLS", "HTTP" }.Any(word => detail.Contains(word, StringComparison.OrdinalIgnoreCase)) ? "Le service de téléchargement est inaccessible. Vérifie la connexion Internet puis réessaie."
                    : new[] { "denied", "unauthorized", "refus", "permission" }.Any(word => detail.Contains(word, StringComparison.OrdinalIgnoreCase)) ? "Windows a refusé l’accès nécessaire. Vérifie les droits d’accès puis réessaie."
                    : "L’étape « " + result.Phase + " » n’a pas abouti. Consulte le journal avant de réessayer.";
                return await Finish(result, OperationState.Failed, "WORKER_FAILED", result.Name + " : échec. " + hint, detail);
            }
            result = result with { Phase = "Vérification du résultat" };
            await Save(result);
            progress?.Report(new WorkerProgress(99, "Vérification du résultat", "Contrôle des preuves avant validation finale.",
                payload.TryGetProperty("Step", out var verifyStep) && verifyStep.TryGetInt32(out int verifyingStep) ? verifyingStep : 0,
                payload.TryGetProperty("TotalSteps", out var verifyTotal) && verifyTotal.TryGetInt32(out int verifyingTotal) ? verifyingTotal : 0));
            var verification = await verify(payload);
            result = result with { Checks = result.Checks.Concat(verification.Checks).ToArray() };
            if (!verification.Valid)
                return await Finish(result, OperationState.Unconfirmed, "VERIFICATION_FAILED", verification.Message);
            var completed = await Finish(result, verification.Partial ? OperationState.Partial : OperationState.Succeeded, "", verification.Message);
            if (completed.Success) progress?.Report(new WorkerProgress(100, verification.Partial ? "Analyse partielle" : "Résultat vérifié", verification.Message,
                payload.TryGetProperty("Step", out var finalStep) && finalStep.TryGetInt32(out int completedStep) ? completedStep : 0,
                payload.TryGetProperty("TotalSteps", out var finalTotal) && finalTotal.TryGetInt32(out int completedTotal) ? completedTotal : 0));
            return completed;
        }
        catch (JsonException error) { return await Finish(result, OperationState.Unconfirmed, "REPORT_UNREADABLE", "Résultat impossible à confirmer : le rapport est illisible.", error.Message); }
        catch (Exception error) { return await Finish(result, OperationState.Unconfirmed, "VERIFICATION_ERROR", "Résultat impossible à confirmer : la vérification n’a pas pu être terminée.", error.ToString()); }
        finally { sessionLease?.Dispose(); if (releaseGate) gate.Release(); }
    }

    private static FileStream? AcquireSessionLease(string directory,OperationResult current)
    {
        string path=Path.Combine(directory,current.OperationKey+".lease.json");
        if(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("Verrou d’opération redirigé.");
        FileStream file;
        try{file=new FileStream(path,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
        catch(IOException error) when((error.HResult&0xffff) is 32 or 33){return null;}
        try
        {
            if(file.Length>0)
            {
                if(file.Length>8192){file.Dispose();return null;}
                using var lease=JsonDocument.Parse(file);
                string id=lease.RootElement.GetProperty("OperationId").GetString()??"";
                if(!Guid.TryParseExact(id,"N",out _)){file.Dispose();return null;}
                string journal=Path.Combine(directory,id+".operation.json");
                if(!File.Exists(journal)||new FileInfo(journal).Length>4*1024*1024||(File.GetAttributes(journal)&FileAttributes.ReparsePoint)!=0){file.Dispose();return null;}
                var previous=JsonSerializer.Deserialize<OperationResult>(File.ReadAllText(journal));
                if(previous==null||previous.SchemaVersion!=1||!Enum.IsDefined(previous.State)||previous.OperationId!=id||previous.OperationKey!=current.OperationKey){file.Dispose();return null;}
                bool completed=previous.State!=OperationState.Running&&previous.ProcessStopped&&!previous.ActionCompletionUnconfirmed;
                bool stopped=previous.ExecutionStarted==false||completed;
                string receipt=Path.Combine(directory,id+".process.json");
                if(!stopped&&File.Exists(receipt)&&new FileInfo(receipt).Length<8192&&(File.GetAttributes(receipt)&FileAttributes.ReparsePoint)==0)
                {
                    using var identity=JsonDocument.Parse(File.ReadAllText(receipt));var data=identity.RootElement;
                    stopped=data.GetProperty("SchemaVersion").GetInt32()==1&&data.GetProperty("OperationId").GetString()==id&&
                        ReceiptProcessStopped(data.GetProperty("ProcessId").GetInt32(),data.GetProperty("StartedUtc").GetDateTime());
                    if(previous.ActionCompletionUnconfirmed&&previous.ResumeIntent?.Kind is not ("Adk" or "WebView2"))stopped=false;
                }
                if(!stopped||(!completed&&PreviousToolsBusy(previous.ResumeIntent?.Kind))){file.Dispose();return null;}
            }
            file.Position=0;file.SetLength(0);JsonSerializer.Serialize(file,new{OperationId=current.OperationId});file.Flush(true);return file;
        }
        catch(JsonException){file.Dispose();return null;}
        catch(InvalidOperationException){file.Dispose();return null;}
        catch(System.Collections.Generic.KeyNotFoundException){file.Dispose();return null;}
        catch(FormatException){file.Dispose();return null;}
        catch{file.Dispose();throw;}
    }
    private static bool ReceiptProcessStopped(int pid,DateTime started)
    {
        if(pid<=0||started==default)return false;
        try{using var process=System.Diagnostics.Process.GetProcessById(pid);return process.HasExited||process.StartTime.ToUniversalTime()!=started.ToUniversalTime();}
        catch(ArgumentException){return true;}catch(InvalidOperationException){return true;}catch{return false;}
    }
    private static bool PreviousToolsBusy(string? kind)
    {
        string[] names=kind switch{
            "RecoveryPreparation"=>new[]{"dism","DismHost","robocopy","bcdboot","bcdedit"},
            "IsoBuild"=>new[]{"dism","DismHost","robocopy","oscdimg"},"Adk"=>new[]{"adksetup","msiexec"},
            "WebView2"=>new[]{"MicrosoftEdgeWebview2Setup","MicrosoftEdgeUpdate"},_=>Array.Empty<string>()};
        try{foreach(string name in names){var all=System.Diagnostics.Process.GetProcessesByName(name);bool found=all.Length>0;foreach(var process in all)process.Dispose();if(found)return true;}return false;}catch{return true;}
    }

    private sealed class CallbackProgress(Action<WorkerProgress> report) : IProgress<WorkerProgress>
    {
        public void Report(WorkerProgress value) => report(value);
    }

    private async Task<OperationResult> Finish(OperationResult result, OperationState state, string code, string message, string detail = "")
    {
        result = result with { State = state, ErrorCode = code, Message = message, TechnicalDetail = detail, EndedUtc = DateTime.UtcNow };
        try { await Save(result); writeLog("Opération", $"[{result.OperationId}] {result.Name} — {state} — {message} — {result.JournalPath}", !result.Success); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            result = result with { State = OperationState.Unconfirmed, ErrorCode = "JOURNAL_UNWRITABLE", Message = "Résultat impossible à confirmer : l’enregistrement du journal a échoué.", TechnicalDetail = error.Message };
            try { await Save(result); } catch (Exception retry) when (retry is IOException or UnauthorizedAccessException) { }
        }
        return result;
    }
    private static async Task Save(OperationResult result)
    {
        string temporary = result.JournalPath + ".tmp";
        await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, result.JournalPath, true);
    }
}
