using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record OperationHistoryEntry(OperationResult Result, string ReportPath)
{
    public OperationTracking Tracking { get; init; } = OperationTrackingService.Evaluate(Result, OperationTrackingService.CurrentBootStamp);
    public string FollowUp => Tracking.Guidance;
    public bool HasIssue => Result.State != OperationState.Succeeded || NeedsAttention;
    public string Effects => Result.Guidance.Effects;
    public string NextStep => string.IsNullOrEmpty(Tracking.Guidance) ? Result.Guidance.NextStep : Tracking.Guidance;
    public string Name => string.IsNullOrWhiteSpace(Result.Name) ? "Opération sans nom" : Result.Name;
    public string Date => Result.StartedUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss");
    public string Reference => Result.OperationId;
    public bool NeedsAttention => Result.State != OperationState.Succeeded || Tracking.RestartPending || Tracking.RestartObserved || Tracking.ExternalUnconfirmed;
    public string Status => Tracking.Status.Length > 0 ? Tracking.Status : RecordedStatus;
    public string Outcome => Tracking.Status.Length > 0 ? "Résultat enregistré : " + RecordedStatus : "";
    public string RecordedStatus => Result.State switch
    {
        OperationState.Succeeded => "Réussie",
        OperationState.Partial => "Partiellement réussie",
        OperationState.Failed => "Échec",
        OperationState.Cancelled => "Annulée",
        OperationState.TimedOut => "Délai dépassé",
        OperationState.Running => "Fin non enregistrée",
        _ => "Résultat non confirmé"
    };
    public string Color => Tracking.Status.Length > 0 ? "#FFB84D" : Result.State == OperationState.Succeeded ? "#38D9A9" : Result.State == OperationState.Failed ? "#FF8585" : "#FFB84D";
    public string Message => Result.State == OperationState.Running
        ? "Cette opération n’a pas de résultat final enregistré. Dernière phase enregistrée : " + Result.Phase + "."
        : HasIssue ? Result.Guidance.Problem : Result.Message;
    public string TechnicalDetail => $"Référence : {Reference}\nÉtat enregistré : {Result.State}\nPhase : {Result.Phase}\nCode : {Result.ErrorCode}\nCode de sortie : {Result.WorkerExitCode?.ToString() ?? "non renseigné"}\nExécution engagée : {Result.ExecutionStarted?.ToString() ?? "non renseigné"}\nMessage enregistré : {Result.Message}\nProcessus Bastos : {Result.OwnerProcessId}\nDébut du processus : {Result.OwnerProcessStartedUtc:O}\nDémarrage Windows : {Result.BootStamp}\n{Result.TechnicalDetail}";
    public IEnumerable<string> Checks => (Result.Checks ?? Array.Empty<OperationCheck>()).Where(c => c != null).Select(c => $"{(c.Passed ? "✓" : "!")} {c.Name} — {c.Detail}");
}

public sealed record OperationHistorySnapshot(IReadOnlyList<OperationHistoryEntry> Entries, int Skipped);

public sealed class OperationHistoryService(string logRoot)
{
    public string DirectoryPath { get; } = Path.Combine(Path.GetFullPath(logRoot), "Operations");

    public OperationHistorySnapshot Read(int maximum = 200)
    {
        if (!Directory.Exists(DirectoryPath)) return new(Array.Empty<OperationHistoryEntry>(), 0);
        var entries = new List<OperationHistoryEntry>();
        int skipped = 0;
        // Bound disk reads and JSON size; a damaged report must not hide the rest of the history.
        foreach (var file in new DirectoryInfo(DirectoryPath).EnumerateFiles("*.operation.json")
            .OrderByDescending(f => f.LastWriteTimeUtc).Take(Math.Clamp(maximum, 1, 1000)))
        {
            try
            {
                if (file.Length > 4 * 1024 * 1024 || (file.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException();
                using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var result = JsonSerializer.Deserialize<OperationResult>(stream);
                string id = file.Name[..^".operation.json".Length];
                if (result == null || result.SchemaVersion != 1 || !Guid.TryParseExact(id, "N", out _) ||
                    !id.Equals(result.OperationId, StringComparison.OrdinalIgnoreCase) || result.StartedUtc == default ||
                    !Enum.IsDefined(result.State)) throw new InvalidDataException();
                // Never use a path supplied by a report as an executable/open target.
                entries.Add(new(result, file.FullName));
            }
            catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or ArgumentException)
            { skipped++; }
        }
        var ordered = entries.OrderByDescending(e => e.Result.StartedUtc).ToArray();
        for (int i = 0; i < ordered.Length; i++)
        {
            var entry = ordered[i];
            // A later verified run of the exact same action can close the reminder,
            // while the original report and its result remain untouched.
            bool rechecked = !string.IsNullOrEmpty(entry.Result.OperationKey) &&
                ordered.Any(next => next.Result.State == OperationState.Succeeded && !next.Result.RestartRequired &&
                    next.Result.OperationKey == entry.Result.OperationKey && next.Result.StartedUtc > (entry.Result.EndedUtc ?? entry.Result.StartedUtc));
            if (rechecked && (entry.Tracking.Interrupted || entry.Tracking.RestartObserved || entry.Tracking.ExternalUnconfirmed))
                ordered[i] = entry with { Tracking = new("Recontrôlée depuis", "Une nouvelle exécution de cette même action a été vérifiée depuis. Le rapport original conserve son résultat initial.") };
        }
        return new(ordered, skipped);
    }

    public string ResolveReport(OperationHistoryEntry entry)
    {
        string expected = Path.Combine(DirectoryPath, entry.Reference + ".operation.json");
        if (!Guid.TryParseExact(entry.Reference, "N", out _) ||
            !string.Equals(expected, entry.ReportPath, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(expected) || (File.GetAttributes(expected) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Le rapport n’est plus disponible. Actualisez le journal.");
        return expected;
    }
}
