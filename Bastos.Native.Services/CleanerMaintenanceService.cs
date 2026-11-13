using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed record MaintenanceAction(string Id, string Name, string Description, bool RequiresAdmin);
public enum MaintenanceStatus { Verified, Partial, Failed, Unconfirmed, Cancelled }
public sealed class MaintenancePreview
{
    public MaintenanceAction Action { get; }
    public DateTime CreatedUtc { get; }
    public bool CanExecute { get; }
    public string Status { get; }
    public long? EstimatedBytes { get; }
    public long? ItemCount { get; }
    public IReadOnlyList<string> Details { get; }
    internal MaintenancePreview(MaintenanceAction action, DateTime created, bool canExecute, string status, long? bytes, long? count, IEnumerable<string> details)
    { Action = action; CreatedUtc = created; CanExecute = canExecute; Status = status; EstimatedBytes = bytes; ItemCount = count; Details = Array.AsReadOnly(details.ToArray()); }
}
public sealed record CleanerMaintenanceResult(string ActionId, MaintenanceStatus Status, string Message, long? BytesRemoved, long? ItemsRemoved, TimeSpan Elapsed, IReadOnlyList<string> Details);

/// <summary>Optional built-in maintenance only. Never deletes WinSxS/cache paths directly or elevates silently.</summary>
public sealed class CleanerMaintenanceService
{
    internal sealed record Snapshot(bool Available, long? Bytes, long? Count, bool? Recommended, string Detail)
    {
        internal string Fingerprint => $"{Available}|{Bytes}|{Count}|{Recommended}";
    }
    internal sealed record CommandSpec(string Executable, string[] Arguments, bool Mutating);
    internal sealed record CommandResult(int ExitCode, string Output);
    internal interface IBackend
    {
        bool IsAdministrator { get; }
        string Identity { get; }
        Task<Snapshot> ObserveAsync(string id, CancellationToken token);
        Task<CommandResult> ApplyAsync(string id);
    }
    private sealed record Permit(MaintenancePreview Preview, Snapshot Snapshot, string Identity);
    private static readonly SemaphoreSlim OperationGate = new(1, 1);
    private readonly IBackend backend;
    private readonly Func<DateTime> clock;
    private readonly Dictionary<MaintenancePreview, Permit> permits = new();
    public IReadOnlyList<MaintenanceAction> Catalog { get; } = Array.AsReadOnly(new[] {
        new MaintenanceAction("windows-components", "Composants Windows", "Maintenance Windows des composants remplacés. Les anciennes versions sont supprimées sans ResetBase. Espace récupérable inconnu ; une exclusion de fichiers interdit cette opération globale.", true),
        new MaintenanceAction("delivery-optimization", "Optimisation de la distribution", "Demande à Windows de nettoyer son cache de distribution. Les fichiers épinglés sont conservés. Espace récupérable inconnu ; exclusions incompatibles.", true),
        new MaintenanceAction("recycle-bin", "Corbeille", "Vide définitivement la corbeille du compte courant sur tous les lecteurs. Les exclusions et la protection des fichiers récents ne peuvent pas s’appliquer à cette action globale.", false)
    });
    public CleanerMaintenanceService() : this(new WindowsBackend(), () => DateTime.UtcNow) { }
    internal CleanerMaintenanceService(IBackend backend, Func<DateTime>? clock = null)
    { this.backend = backend; this.clock = clock ?? (() => DateTime.UtcNow); }

    public async Task<MaintenancePreview> PreviewAsync(string id, IEnumerable<string>? exclusions = null, CancellationToken token = default)
    {
        var action = Catalog.SingleOrDefault(a => a.Id == id) ?? throw new ArgumentException("Action inconnue.", nameof(id));
        if (exclusions?.Any(x => !string.IsNullOrWhiteSpace(x)) == true)
            return MakeBlocked(action, "Retirez les exclusions avant d’envisager cette opération globale. Elles ne peuvent pas être respectées par Windows.");
        if (action.RequiresAdmin && !backend.IsAdministrator)
            return MakeBlocked(action, "Droits administrateur requis. Relancez BASTOS en tant qu’administrateur, puis analysez de nouveau.");
        await OperationGate.WaitAsync(token);
        try
        {
            token.ThrowIfCancellationRequested();
            Snapshot observed = await backend.ObserveAsync(id, token);
            bool useful = observed.Available && (id == "windows-components" ? observed.Recommended == true && observed.Count > 0 : (observed.Count > 0 || observed.Bytes > 0));
            string status = !observed.Available ? "Analyse indisponible : aucune opération autorisée." : useful ? "Analyse prête. Confirmation explicite nécessaire." : "Aucun nettoyage nécessaire selon la dernière mesure.";
            var details = new List<string> { observed.Detail, "L’analyse expire après 10 minutes. Une mesure modifiée impose une nouvelle analyse." };
            if (id != "recycle-bin") details.Add("La taille du cache ou du magasin n’est pas une estimation de l’espace récupérable.");
            var preview = new MaintenancePreview(action, clock(), useful, status,
                id == "recycle-bin" ? observed.Bytes : null, id == "recycle-bin" ? observed.Count : null, details);
            if (useful) lock (permits)
            {
                foreach (var old in permits.Keys.Where(p => p.Action.Id == id || clock() - p.CreatedUtc > TimeSpan.FromMinutes(10)).ToArray()) permits.Remove(old);
                permits.Add(preview, new Permit(preview, observed, backend.Identity));
            }
            return preview;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception e) { return MakeBlocked(action, "Analyse impossible : " + e.Message); }
        finally { OperationGate.Release(); }
    }

    private MaintenancePreview MakeBlocked(MaintenanceAction action, string message) => new(action, clock(), false, message, null, null, new[] { message });

    public async Task<CleanerMaintenanceResult> ExecuteAsync(MaintenancePreview preview, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(preview);
        var timer = Stopwatch.StartNew();
        CleanerMaintenanceResult Result(MaintenanceStatus state, string message, params string[] details) => new(preview.Action.Id, state, message, null, null, timer.Elapsed, Array.AsReadOnly(details));
        Permit? permit;
        lock (permits) { permits.Remove(preview, out permit); }
        if (permit == null || !preview.CanExecute || clock() < preview.CreatedUtc || clock() - preview.CreatedUtc > TimeSpan.FromMinutes(10) || permit.Identity != backend.Identity)
            return Result(MaintenanceStatus.Failed, "Analyse expirée, déjà utilisée ou étrangère à cette session. Analysez de nouveau.");
        if (preview.Action.RequiresAdmin && !backend.IsAdministrator)
            return Result(MaintenanceStatus.Failed, "Droits administrateur perdus. Analysez de nouveau.");
        try { await OperationGate.WaitAsync(token); }
        catch (OperationCanceledException) { return Result(MaintenanceStatus.Cancelled, "Annulé avant toute modification."); }
        bool started = false;
        try
        {
            token.ThrowIfCancellationRequested();
            var before = await backend.ObserveAsync(preview.Action.Id, token);
            if (!before.Available || before.Fingerprint != permit.Snapshot.Fingerprint || backend.Identity != permit.Identity)
                return Result(MaintenanceStatus.Failed, "L’état a changé depuis l’analyse. Analysez de nouveau avant de confirmer.", before.Detail);
            token.ThrowIfCancellationRequested();
            // Native maintenance cannot be interrupted safely. Do not kill DISM or detach it on cancellation.
            started = true;
            var command = await backend.ApplyAsync(preview.Action.Id);
            Snapshot after;
            try { after = await backend.ObserveAsync(preview.Action.Id, CancellationToken.None); }
            catch (Exception e) { return Result(MaintenanceStatus.Unconfirmed, "Commande terminée, mais résultat non confirmé. Consultez les détails avant toute nouvelle tentative.", "Code retour : " + command.ExitCode, e.Message); }
            var details = new List<string> { "Avant : " + before.Detail, "Après : " + after.Detail, "Code retour : " + command.ExitCode, Limit(command.Output, 6000) };
            if (token.IsCancellationRequested) details.Add("Annulation demandée après le début : l’opération Windows a été suivie jusqu’à sa fin, sans interruption forcée.");
            if (command.ExitCode != 0 && command.ExitCode != 3010)
                return new(preview.Action.Id, MaintenanceStatus.Failed, "Windows a signalé une erreur. Des modifications partielles sont possibles.", null, null, timer.Elapsed, details.AsReadOnly());
            if (!after.Available)
                return new(preview.Action.Id, MaintenanceStatus.Unconfirmed, "La commande est terminée, mais la vérification indépendante est indisponible.", null, null, timer.Elapsed, details.AsReadOnly());
            bool verified = preview.Action.Id == "windows-components" ? after.Recommended == false && after.Count == 0
                : preview.Action.Id == "recycle-bin" ? after.Count == 0 && after.Bytes == 0 : after.Bytes == 0;
            bool decreased = (before.Bytes.HasValue && after.Bytes.HasValue && after.Bytes < before.Bytes) || (before.Count.HasValue && after.Count.HasValue && after.Count < before.Count);
            var state = verified ? MaintenanceStatus.Verified : decreased ? MaintenanceStatus.Partial : MaintenanceStatus.Unconfirmed;
            string message = verified ? (preview.Action.Id == "recycle-bin" ? "Corbeille vérifiée vide." : "Maintenance vérifiée par une nouvelle analyse Windows.")
                : decreased ? "Une diminution a été mesurée ; des éléments restent présents." : "Commande terminée ; aucun résultat complet ne peut être confirmé.";
            if (command.ExitCode == 3010) message += " Windows demande un redémarrage.";
            details.Add("Les mesures sont globales et peuvent évoluer avec Windows ou les autres applications. Aucun gain d’espace par fichier n’est affirmé.");
            return new(preview.Action.Id, state, message, null, null, timer.Elapsed, details.AsReadOnly());
        }
        catch (OperationCanceledException) when (!started) { return Result(MaintenanceStatus.Cancelled, "Annulé avant toute modification."); }
        catch (Exception e) { return Result(started ? MaintenanceStatus.Unconfirmed : MaintenanceStatus.Failed, started ? "Résultat non confirmé après le lancement de la maintenance." : "Opération refusée avant modification.", e.Message); }
        finally { OperationGate.Release(); }
    }

    private static string Limit(string value, int maximum) => value.Length <= maximum ? value : value[..maximum] + "\n[sortie tronquée]";
    internal static CommandSpec BuildCommand(string id, bool mutate, string systemDirectory)
    {
        if (!Path.IsPathFullyQualified(systemDirectory)) throw new ArgumentException("Chemin système absolu requis.");
        if (id == "windows-components")
            return new(Path.Combine(systemDirectory, "dism.exe"), mutate
                ? new[] { "/English", "/Online", "/Cleanup-Image", "/StartComponentCleanup", "/NoRestart" }
                : new[] { "/English", "/Online", "/Cleanup-Image", "/AnalyzeComponentStore" }, mutate);
        if (id != "delivery-optimization") throw new ArgumentException("Action sans commande intégrée.");
        string script = mutate ? "$ErrorActionPreference='Stop'; Delete-DeliveryOptimizationCache -Force -ErrorAction Stop"
            : "$ErrorActionPreference='Stop'; Get-Command Delete-DeliveryOptimizationCache -ErrorAction Stop | Out-Null; $s=Get-DeliveryOptimizationPerfSnap -ErrorAction Stop; if($null -eq $s.CacheSizeBytes){throw 'CacheSizeBytes unavailable'}; [pscustomobject]@{CacheSizeBytes=[long]$s.CacheSizeBytes;Files=[long]$s.Files} | ConvertTo-Json -Compress";
        return new(Path.Combine(systemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script }, mutate);
    }

    internal static Snapshot ParseComponents(CommandResult result)
    {
        var count = Regex.Match(result.Output, @"Number of Reclaimable Packages\s*:\s*(\d+)", RegexOptions.IgnoreCase);
        var recommendation = Regex.Match(result.Output, @"Component Store Cleanup Recommended\s*:\s*(Yes|No)", RegexOptions.IgnoreCase);
        if (result.ExitCode != 0 || !count.Success || !recommendation.Success || !long.TryParse(count.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out long packages))
            return new(false, null, null, null, "Analyse DISM non interprétable. " + Limit(result.Output, 2000));
        bool recommended = recommendation.Groups[1].Value.Equals("Yes", StringComparison.OrdinalIgnoreCase);
        return new(true, null, packages, recommended, $"Paquets récupérables : {packages} ; nettoyage recommandé : {(recommended ? "oui" : "non")}. Taille récupérable inconnue.");
    }
    internal static Snapshot ParseDelivery(CommandResult result)
    {
        if (result.ExitCode != 0) return new(false, null, null, null, "Mesure Delivery Optimization indisponible. " + Limit(result.Output, 2000));
        try
        {
            using var doc = JsonDocument.Parse(result.Output.Trim());
            long bytes = doc.RootElement.GetProperty("CacheSizeBytes").GetInt64();
            long count = doc.RootElement.GetProperty("Files").GetInt64();
            if (bytes < 0 || count < 0) throw new FormatException();
            return new(true, bytes, count, null, $"Cache Windows observé : {bytes} octets, {count} fichiers. Les fichiers épinglés restent protégés.");
        }
        catch { return new(false, null, null, null, "Mesure Delivery Optimization non interprétable."); }
    }
    private sealed class WindowsBackend : IBackend
    {
        public bool IsAdministrator { get { using var identity = WindowsIdentity.GetCurrent(); return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator); } }
        public string Identity { get { using var identity = WindowsIdentity.GetCurrent(); return Environment.MachineName + "|" + identity.User?.Value + "|" + Environment.SystemDirectory; } }
        public async Task<Snapshot> ObserveAsync(string id, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (id == "recycle-bin") return await Task.Run(QueryRecycleBin, token);
            var result = await RunAsync(BuildCommand(id, false, Environment.SystemDirectory), token);
            return id == "windows-components" ? ParseComponents(result) : ParseDelivery(result);
        }
        public async Task<CommandResult> ApplyAsync(string id)
        {
            if (id == "recycle-bin") return await Task.Run(() => {
                int hr = SHEmptyRecycleBinW(IntPtr.Zero, null, 1 | 2 | 4);
                return new CommandResult(hr, hr == 0 ? "Demande Windows de vidage terminée." : "HRESULT : 0x" + hr.ToString("X8"));
            });
            return await RunAsync(BuildCommand(id, true, Environment.SystemDirectory), CancellationToken.None);
        }
        private static Snapshot QueryRecycleBin()
        {
            var info = new RecycleInfo { Size = (uint)Marshal.SizeOf<RecycleInfo>() };
            int hr = SHQueryRecycleBinW(null, ref info);
            if (hr != 0 || info.Bytes < 0 || info.Items < 0) return new(false, null, null, null, "Corbeille inaccessible (HRESULT 0x" + hr.ToString("X8") + ").");
            return new(true, info.Bytes, info.Items, null, $"Corbeille du compte sur tous les lecteurs : {info.Items} éléments, {info.Bytes} octets à cet instant.");
        }
        private static async Task<CommandResult> RunAsync(CommandSpec command, CancellationToken token)
        {
            var psi = new ProcessStartInfo(command.Executable) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (string arg in command.Arguments) psi.ArgumentList.Add(arg);
            using var process = new Process { StartInfo = psi };
            token.ThrowIfCancellationRequested();
            process.Start();
            var stdout = CaptureAsync(process.StandardOutput);
            var stderr = CaptureAsync(process.StandardError);
            try { await process.WaitForExitAsync(token); }
            catch (OperationCanceledException) when (!command.Mutating)
            {
                try { if (!process.HasExited) process.Kill(true); } catch { }
                await process.WaitForExitAsync(CancellationToken.None);
                await Task.WhenAll(stdout, stderr);
                throw;
            }
            return new(process.ExitCode, (await stdout) + "\n" + (await stderr));
        }
        private static async Task<string> CaptureAsync(StreamReader reader)
        {
            var output = new StringBuilder(); var buffer = new char[4096]; int read;
            while ((read = await reader.ReadAsync(buffer.AsMemory())) > 0)
                if (output.Length < 65536) output.Append(buffer, 0, Math.Min(read, 65536 - output.Length));
            return output.ToString();
        }
        [StructLayout(LayoutKind.Sequential)] private struct RecycleInfo { public uint Size; public long Bytes; public long Items; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern int SHQueryRecycleBinW(string? rootPath, ref RecycleInfo info);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern int SHEmptyRecycleBinW(IntPtr owner, string? rootPath, uint flags);
    }
}

