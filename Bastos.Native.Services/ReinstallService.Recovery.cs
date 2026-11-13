using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed partial class ReinstallService
{
    private readonly VerifiedOperationService recovery = new(paths.LogRoot,
        (script, arguments) => workers.RunAsync(script, arguments, elevate: true,
            timeoutMinutes: arguments.Contains("Provision") ? 180 : 10, terminateOnTimeout: false),
        (area, message, error) => log.Write(area, message, error));
    private bool recoveryRestartScheduled;
    private readonly ProcessExecutionService recoveryRunner = new();

    public async Task<(bool Success, string Message)> ProvisionRecoveryAsync(IsoChoice iso, LanguageChoice language, KeyboardChoice keyboard,
        string userName, IProgress<RecoveryBuildProgress>? recoveryProgress = null, bool forceBastosAutonomous = false, RufusInstallOptions? approvedOptions = null, OperationCancellation? cancellation = null, int editionIndex = 0)
    {
        if (recoveryRestartScheduled) return (false, "Un redémarrage Recovery est déjà programmé. Aucune nouvelle préparation autorisée.");
        ValidateUserName(userName);
        bool useOptions = !forceBastosAutonomous && (approvedOptions != null || HasRufusOptions);
        string? frozen = useOptions ? FreezeRecoveryOptions(approvedOptions ?? ReadRufusOptions()) : null;
        var options = frozen == null ? null : JsonSerializer.Deserialize<RufusInstallOptions>(File.ReadAllText(frozen));
        string mode = useOptions ? "WindowsOnly" : forceBastosAutonomous || iso.IsBastosCustom ? "BastosAutonomous" : "WindowsOnly";
        string answer = Path.Combine(paths.DataRoot, "Official-Windows", "autounattend-" + Guid.NewGuid().ToString("N") + ".xml");
        var arguments = new List<string> { "-Action", "Provision", "-IsoPath", iso.Path, "-AnswerFilePath", answer,
            "-GenerateAnswerFile", "-WindowsLocale", language.Locale, "-KeyboardLayout", keyboard.InputLocale, "-LocalUserName", useOptions ? "BastOS" : userName.Trim(),
            "-RecoverySizeGB", "40", "-RecoveryMode", "Novice", "-PostInstallMode", mode };
        if (frozen != null) arguments.AddRange(new[] { "-OptionsPath", frozen });
        if (editionIndex > 0) arguments.AddRange(new[] { "-EditionIndex", editionIndex.ToString(System.Globalization.CultureInfo.InvariantCulture) });
        if (iso.IsBastosCustom && !useOptions) arguments.Add("-UseEmbeddedProfile");
        if (cancellation != null) arguments.AddRange(new[] { "-CancellationPath", cancellation.BindWorker(paths.LogRoot) });
        var expected = RecoveryExpected(iso, mode, options, editionIndex);
        OperationResumeIntent? resumeIntent = null;
        if(frozen != null && mode == "WindowsOnly")
        {
            await using var input = File.OpenRead(frozen);
            resumeIntent = new("RecoveryPreparation",iso.Path,JsonSerializer.Serialize(expected),frozen,
                Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(input)));
        }
        var reporter = new RecoveryProgressAdapter(recoveryProgress);
        var running = recovery.RunAsync("Préparation de BASTOS_RECOVERY", "Initialize-BASTOS-Recovery.ps1", arguments,
            payload => VerifyRecoveryAsync(expected, payload, frozen, false),
            reporter, concurrencyKey: "recovery-storage", resumeIntent: resumeIntent);
        var operation = cancellation == null ? await running : await cancellation.TrackAsync(running);
        recoveryProgress?.Report(new(operation.Success ? 100 : Math.Min(99, reporter.Last.Percent), operation.Success ? "BASTOS_RECOVERY prête" :
            operation.State == OperationState.Cancelled ? "Annulée" : operation.State == OperationState.Unconfirmed ? "Résultat à vérifier" : "Échec", operation.UserMessage, reporter.Last.Step, reporter.Last.TotalSteps));
        return (operation.Success, operation.UserMessage + (operation.Success && cancellation?.Requested == true ? " La phase d’écriture avait déjà commencé ; l’annulation de cette préparation n’a pas été effectuée." : ""));
    }

    public async Task<(bool Success, string Message)> BootRecoveryAsync(IsoChoice iso, RufusInstallOptions? approvedOptions = null, bool forceBastosAutonomous = false, IProgress<RecoveryBuildProgress>? recoveryProgress = null)
    {
        if (recoveryRestartScheduled) return (false, "Un redémarrage Recovery est déjà programmé.");
        bool useOptions = !forceBastosAutonomous && (approvedOptions != null || HasRufusOptions);
        string? frozen = useOptions ? FreezeRecoveryOptions(approvedOptions ?? ReadRufusOptions()) : null;
        var options = frozen == null ? null : JsonSerializer.Deserialize<RufusInstallOptions>(File.ReadAllText(frozen));
        string mode = useOptions ? "WindowsOnly" : forceBastosAutonomous || iso.IsBastosCustom ? "BastosAutonomous" : "WindowsOnly";
        var arguments = new List<string> { "-Action", "BootOnce", "-RecoveryMode", "Novice", "-PostInstallMode", mode };
        if (frozen != null) arguments.AddRange(new[] { "-OptionsPath", frozen });
        recoveryProgress?.Report(new(0, "Programmation du démarrage", "Validation du média et du démarrage unique Recovery.", 0, 10, true));
        var operation = await recovery.RunAsync("Programmation du démarrage Recovery", "Initialize-BASTOS-Recovery.ps1", arguments,
            payload => VerifyRecoveryAsync(RecoveryExpected(iso, mode, options), payload, frozen, true), new RecoveryProgressAdapter(recoveryProgress), concurrencyKey: "recovery-storage");
        if (!RecoveryOperationVerifiers.CanRestart(operation))
        {
            if (operation.ErrorCode == "OPERATION_BUSY" || operation.ErrorCode == "JOURNAL_UNWRITABLE" || operation.State == OperationState.Cancelled)
                return (false, operation.UserMessage);
            if (!operation.ProcessStopped) return (false, operation.UserMessage + " Aucun redémarrage demandé. L’outil peut encore travailler ; vérifie son état avant de relancer.");
            var disabled = await DisableRecoveryBootAsync(operation.OperationId, frozen, mode);
            return (false, operation.UserMessage + (disabled.Success ? " Le démarrage de cette tentative a été neutralisé." :
                " La neutralisation du démarrage n’est pas confirmée. Consulte le Journal avant tout redémarrage manuel."));
        }
        recoveryRestartScheduled = true;
        var restart = await recovery.RunNativeAsync("Demande de redémarrage vers Recovery", "recovery-restart", async _ =>
        {
            var command = await recoveryRunner.RunAsync(Path.Combine(Environment.SystemDirectory, "shutdown.exe"),
                new[] { "/r", "/t", "15", "/d", "p:4:1", "/c", "Redémarrage vers BASTOS_RECOVERY" }, timeoutMinutes: 1, terminateOnTimeout: false);
            return new NativeOperationReport(command.Success && command.ProcessStopped, command.Success ? "Windows a accepté la demande de redémarrage dans 15 secondes." :
                "Windows n’a pas confirmé la demande de redémarrage. Consulte le Journal.",
                new Dictionary<string, object?> { ["RestartRequired"] = command.Success, ["BootOperationId"] = operation.OperationId,
                    ["SchedulerExitCode"] = command.ExitCode, ["ActionCompletionUnconfirmed"] = !command.ProcessStopped },
                command.Success ? "" : "RECOVERY_RESTART_FAILED", command.Error);
        }, payload => Task.FromResult(new OperationVerification(payload.GetProperty("SchedulerExitCode").GetInt32() == 0,
            "Demande de redémarrage acceptée par Windows ; la réinstallation reste à effectuer.",
            new[] { new OperationCheck("Commande Windows", payload.GetProperty("SchedulerExitCode").GetInt32() == 0, "Code de sortie du planificateur de redémarrage.") })));
        if (!restart.Success)
        {
            // An unknown scheduler may still restart Windows: do not claim cancellation.
            var disabled = await DisableRecoveryBootAsync(operation.OperationId, frozen, mode);
            return (false, restart.UserMessage + (disabled.Success ? " Le démarrage Recovery a été neutralisé ; une demande Windows déjà acceptée peut encore redémarrer le PC normalement." :
                " Le démarrage Recovery n’est pas confirmé comme neutralisé. Vérifie le Journal avant de poursuivre."));
        }
        return (true, operation.Message + " Windows redémarrera dans 15 secondes.");
    }

    private static RecoveryExpectation RecoveryExpected(IsoChoice iso, string mode, RufusInstallOptions? options, int editionIndex = 0) => new(iso.Path, mode,
        options == null ? null : "D:\\", options?.DiskSafetySnapshot ?? "", options?.WindowsDiskIdentity ?? "", options?.RecoveryPartitionGuid ?? "",
        options?.WindowsImageIndex ?? editionIndex, options?.WindowsEditionId ?? "", options?.UserName ?? "", options?.ComputerName ?? "", options?.KeyboardLayout ?? "", options?.WindowsUILanguage ?? "", options?.PreserveDrivers ?? false, options?.UseCleanBastosInstallation == true ? "minimal-2" : "");

    private async Task<OperationVerification> VerifyRecoveryAsync(RecoveryExpectation expected, JsonElement payload, string? frozen, bool boot, bool resuming = false)
    {
        string id = payload.GetProperty("OperationId").GetString()!;
        string file = Path.Combine(paths.LogRoot, "Operations", id + (resuming ? ".resume-verification-" + Guid.NewGuid().ToString("N") : ".verification") + ".json");
        var arguments = new List<string> { "-Action", "InspectResult", "-OperationId", id, "-ResultPath", file,
            "-RecoveryMode", "Novice", "-PostInstallMode", expected.Mode };
        if (frozen != null) arguments.AddRange(new[] { "-OptionsPath", frozen });
        if (boot) arguments.Add("-VerifyBoot");
        var command = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1", arguments, elevate: boot, timeoutMinutes: 5, terminateOnTimeout: false);
        if (!command.Success || !command.ProcessStopped || !File.Exists(file) || new FileInfo(file).Length > 4 * 1024 * 1024)
            return new(false, "Résultat Recovery non confirmé : la relecture indépendante a échoué. Aucun redémarrage demandé.",
                new[] { new OperationCheck("Relecture indépendante", false, command.Error) });
        using var probe = JsonDocument.Parse(await File.ReadAllTextAsync(file));
        return await RecoveryOperationVerifiers.VerifyAsync(expected, payload, probe.RootElement, boot);
    }

    private Task<OperationResult> DisableRecoveryBootAsync(string id, string? frozen, string mode) => recovery.RunNativeAsync(
        "Neutralisation du démarrage Recovery", "recovery-disarm", async _ =>
        {
            string file = Path.Combine(paths.LogRoot, "Operations", id + ".disarm.json");
            var arguments = new List<string> { "-Action", "DisarmBoot", "-OperationId", id, "-ResultPath", file, "-RecoveryMode", "Novice", "-PostInstallMode", mode };
            if (frozen != null) arguments.AddRange(new[] { "-OptionsPath", frozen });
            var command = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1", arguments, elevate: true, timeoutMinutes: 5, terminateOnTimeout: false);
            bool confirmed = false;
            if (command.Success && command.ProcessStopped && File.Exists(file) && new FileInfo(file).Length < 1024 * 1024)
            {
                using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(file)); var data = doc.RootElement;
                confirmed = data.GetProperty("SchemaVersion").GetInt32() == 1 && data.GetProperty("OperationId").GetString() == id &&
                    data.GetProperty("Action").GetString() == "DisarmBoot" && data.GetProperty("Success").GetBoolean();
            }
            return new NativeOperationReport(confirmed, confirmed ? "Tentative Recovery neutralisée." : "Neutralisation Recovery non confirmée ; consulte le Journal avant de redémarrer.",
                new Dictionary<string, object?> { ["BootOperationId"] = id, ["Disarmed"] = confirmed, ["ActionCompletionUnconfirmed"] = !command.ProcessStopped }, confirmed ? "" : "RECOVERY_DISARM_UNCONFIRMED", command.Error);
        }, data => Task.FromResult(new OperationVerification(data.GetProperty("Disarmed").GetBoolean(), "Démarrage de cette tentative neutralisé.",
            new[] { new OperationCheck("Neutralisation liée à l’opération", data.GetProperty("Disarmed").GetBoolean(), id) })));

    private sealed class RecoveryProgressAdapter(IProgress<RecoveryBuildProgress>? progress) : IProgress<WorkerProgress>
    {
        public WorkerProgress Last { get; private set; } = new(0, "Préparation", "Initialisation du suivi.");
        public void Report(WorkerProgress value) { Last = value; progress?.Report(new(value.Percent, value.Phase, value.Message, value.Step, value.TotalSteps)); }
    }
}
