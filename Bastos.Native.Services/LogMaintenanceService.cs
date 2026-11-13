using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record MaintenanceFile(string RelativePath, long Length, DateTime ModifiedUtc, string Sha256);
public sealed record MaintenanceItem(string Id, string Title, string Reason, bool Eligible, IReadOnlyList<MaintenanceFile> Files)
{
    public long Bytes => Files.Sum(f => f.Length);
    public string Size => LogMaintenanceService.FormatBytes(Bytes);
    public string State => Eligible ? "Nettoyable" : "Conservé";
    public string Inventory => string.Join("\n", Files.Select(f => f.RelativePath + " • " + LogMaintenanceService.FormatBytes(f.Length)));
}
public sealed record MaintenancePlan(DateTime CreatedUtc, int KeepDays, bool Complete, IReadOnlyList<MaintenanceItem> Items, string Notice)
{
    public long TotalBytes => Items.Sum(i => i.Bytes);
    public long CleanableBytes => Items.Where(i => i.Eligible).Sum(i => i.Bytes);
    public long ProtectedBytes => TotalBytes - CleanableBytes;
}
public sealed record MaintenanceResult(int DeletedFiles, long DeletedBytes, int SkippedItems, IReadOnlyList<string> Issues, string ReportPath)
{
    public string Summary => $"{DeletedFiles} fichier(s) supprimé(s), taille retirée : {LogMaintenanceService.FormatBytes(DeletedBytes)} ; {SkippedItems} élément(s) conservé(s).";
}

// Only direct local Logs files and Logs/Operations are inspected. No recursive
// cleanup, supplied report paths, ISO caches, Recovery or user TEMP traversal.
public sealed class LogMaintenanceService
{
    private readonly string root;
    private readonly Func<int, DateTime, bool?> alive;
    private readonly Func<DateTime> now;
    private const int MaximumFiles = 10000;
    private const long MaximumRead = 64 * 1024 * 1024;
    private static readonly Regex operationName = new(@"^(?<id>[0-9a-f]{32})\.(?:operation\.json|worker\.json|process\.json|progress\.txt|resume\.json|operation\.json\.tmp|worker\.json\.tmp|(?:process|resume)\.json\.[0-9a-f]{32}\.tmp)$", RegexOptions.IgnoreCase);
    private static readonly Regex archiveName = new(@"^BASTOS-Native-Archive-(?<date>\d{8}T\d{9})-[0-9a-f]{32}\.log$", RegexOptions.IgnoreCase);
    public LogMaintenanceService(string logRoot) : this(logRoot, ProcessAlive, () => DateTime.UtcNow) { }
    internal LogMaintenanceService(string logRoot, Func<int, DateTime, bool?> alive, Func<DateTime> now)
    { root = Path.GetFullPath(logRoot).TrimEnd(Path.DirectorySeparatorChar); this.alive = alive; this.now = now; }
    public static string FormatBytes(long bytes) => bytes >= 1024 * 1024 * 1024 ? $"{bytes / (1024d * 1024 * 1024):N2} Go" : bytes >= 1024 * 1024 ? $"{bytes / (1024d * 1024):N2} Mo" : bytes >= 1024 ? $"{bytes / 1024d:N1} Ko" : $"{bytes} octets";
    private static bool? ProcessAlive(int pid, DateTime started)
    {
        if (pid <= 0 || started == default) return null;
        try { using var process = Process.GetProcessById(pid); return !process.HasExited && process.StartTime.ToUniversalTime() == started.ToUniversalTime(); }
        catch (ArgumentException) { return false; } catch (InvalidOperationException) { return false; } catch { return null; }
    }
    private string Resolve(string relative)
    {
        if (Path.IsPathRooted(relative)) throw new IOException("Chemin hors des journaux locaux refusé.");
        string path = Path.GetFullPath(Path.Combine(root, relative));
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException("Chemin hors des journaux locaux refusé.");
        RefuseLinks(path); return path;
    }
    internal static void RefuseLinks(string path)
    {
        if (!Regex.IsMatch(Path.GetFullPath(path), @"^[A-Za-z]:\\")) throw new IOException("Un dossier local est requis.");
        for (string? cursor = Path.GetFullPath(path); cursor != null; cursor = Path.GetDirectoryName(cursor))
            if ((File.Exists(cursor) || Directory.Exists(cursor)) && (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Fichier ou dossier redirigé : analyse et nettoyage refusés.");
    }
    public MaintenancePlan Scan(int keepDays = 30)
    {
        if (keepDays is < 30 or > 365) throw new ArgumentOutOfRangeException(nameof(keepDays));
        RefuseLinks(root);
        DateTime date = now(), cutoff = date.AddDays(-keepDays);
        if (!Directory.Exists(root)) return new(date, keepDays, true, Array.Empty<MaintenanceItem>(), "Aucun journal local à analyser.");
        var items = new List<MaintenanceItem>();
        var files = new List<FileInfo>();
        long read = 0;
        byte[] Read(string relative, int limit)
        {
            string path = Resolve(relative); var info = new FileInfo(path);
            if (info.Length > limit || (read += info.Length) > MaximumRead) throw new InvalidDataException("Limite de lecture atteinte.");
            return File.ReadAllBytes(path);
        }
        MaintenanceFile Metadata(FileInfo file, bool hash = false) => new(Path.GetRelativePath(root, file.FullName), file.Length, file.LastWriteTimeUtc,
            hash ? Convert.ToHexString(SHA256.HashData(Read(Path.GetRelativePath(root, file.FullName), 16 * 1024 * 1024))) : "");
        try
        {
            files.AddRange(new DirectoryInfo(root).EnumerateFiles().Take(MaximumFiles + 1));
            string operations = Resolve("Operations");
            if (Directory.Exists(operations)) files.AddRange(new DirectoryInfo(operations).EnumerateFiles().Take(MaximumFiles + 1));
            if (files.Count > MaximumFiles) throw new InvalidDataException("Trop de fichiers pour un aperçu complet.");
            // Leases are durable cross-session references. Their referenced journal
            // must remain even after a successful operation and an application exit.
            var leaseIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            bool leasesReadable = true;
            foreach (var lease in files.Where(f => f.Name.EndsWith(".lease.json", StringComparison.OrdinalIgnoreCase)))
                try
                {
                    using var json = JsonDocument.Parse(Read(Path.GetRelativePath(root, lease.FullName), 8192));
                    string id = json.RootElement.GetProperty("OperationId").GetString() ?? "";
                    if (!Guid.TryParseExact(id, "N", out _)) throw new InvalidDataException();
                    leaseIds.Add(id);
                }
                catch { leasesReadable = false; }
            var results = new Dictionary<string, OperationResult>(StringComparer.OrdinalIgnoreCase);
            foreach (var file in files.Where(f => Path.GetDirectoryName(f.FullName)!.Equals(operations, StringComparison.OrdinalIgnoreCase) && operationName.IsMatch(f.Name) && f.Name.EndsWith(".operation.json", StringComparison.OrdinalIgnoreCase)))
                try
                {
                    var result = JsonSerializer.Deserialize<OperationResult>(Read(Path.GetRelativePath(root, file.FullName), 4 * 1024 * 1024));
                    string id = operationName.Match(file.Name).Groups["id"].Value;
                    if (result == null || result.SchemaVersion != 1 || result.OperationId != id || result.StartedUtc == default || !Enum.IsDefined(result.State)) throw new InvalidDataException();
                    results[id] = result;
                }
                catch { }
            var recent = results.Values.OrderByDescending(r => r.StartedUtc).Take(200).Select(r => r.OperationId).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var grouped = files.Where(f => Path.GetDirectoryName(f.FullName)!.Equals(operations, StringComparison.OrdinalIgnoreCase) && operationName.IsMatch(f.Name))
                .GroupBy(f => operationName.Match(f.Name).Groups["id"].Value, StringComparer.OrdinalIgnoreCase).ToArray();
            var groupedPaths = grouped.SelectMany(g => g).Select(f => f.FullName).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var group in grouped)
            {
                string reason = "", id = group.Key;
                results.TryGetValue(id, out var result);
                if (!leasesReadable) reason = "Suivi d’opérations illisible ou occupé : éléments conservés.";
                else if (result == null) reason = "Rapport absent ou illisible : état inconnu.";
                else if (result.State != OperationState.Succeeded || !result.ProcessStopped || result.ActionCompletionUnconfirmed || result.RestartRequired)
                    reason = "Erreur, opération incomplète ou état à vérifier.";
                else if (result.Checks?.Any(c => c == null || !c.Passed) == true || result.EndedUtc < result.StartedUtc)
                    reason = "Rapport contradictoire : fichiers conservés.";
                else if (result.ResumeIntent != null) reason = "Informations de reprise conservées.";
                else if (leaseIds.Contains(id)) reason = "Référence de suivi conservée pour les prochaines opérations.";
                else if (recent.Contains(id)) reason = "Parmi les 200 opérations les plus récentes.";
                else if (result.EndedUtc == null || result.EndedUtc > cutoff || result.StartedUtc > cutoff || group.Any(f => f.LastWriteTimeUtc > cutoff)) reason = $"Conservation minimale de {keepDays} jours.";
                else if (result.OwnerProcessId > 0 && (result.OwnerProcessStartedUtc == null || alive(result.OwnerProcessId, result.OwnerProcessStartedUtc.Value) != false))
                    reason = "Processus d’origine encore actif ou état inaccessible.";
                else
                {
                    var receipt = group.FirstOrDefault(f => f.Name.Equals(id + ".process.json", StringComparison.OrdinalIgnoreCase));
                    if (receipt != null)
                        try
                        {
                            using var json = JsonDocument.Parse(Read(Path.GetRelativePath(root, receipt.FullName), 8192)); var data = json.RootElement;
                            int pid = data.GetProperty("ProcessId").GetInt32(); DateTime started = data.GetProperty("StartedUtc").GetDateTime();
                            if (data.GetProperty("SchemaVersion").GetInt32() != 1 || data.GetProperty("OperationId").GetString() != id || pid <= 0 || started == default || alive(pid, started) != false)
                                reason = "Processus de l’outil actif ou fin non confirmée.";
                        }
                        catch { reason = "Reçu du processus illisible : fichiers conservés."; }
                }
                var ordered = group.OrderBy(f => f.Name.EndsWith(".operation.json", StringComparison.OrdinalIgnoreCase) ? 1 : 0).ThenBy(f => f.Name, StringComparer.OrdinalIgnoreCase).ToArray();
                MaintenanceFile[] metadata;
                try { metadata = ordered.Select(f => { Resolve(Path.GetRelativePath(root, f.FullName)); return Metadata(f, reason == ""); }).ToArray(); }
                catch { reason = "Fichier illisible, volumineux ou redirigé : conservé."; metadata = ordered.Select(f => Metadata(f)).ToArray(); }
                string title = result == null ? "Rapport d’opération et fichiers associés" : (string.IsNullOrWhiteSpace(result.Name) ? "Opération" : result.Name[..Math.Min(result.Name.Length, 120)]) + $" — {result.StartedUtc.ToLocalTime():dd/MM/yyyy}";
                items.Add(new(id, title, reason == "" ? $"Ancien rapport de réussite, hors des 200 opérations récentes ({ordered.Length} fichier(s))." : reason, reason == "", metadata));
            }
            foreach (var file in files.Where(f => !groupedPaths.Contains(f.FullName)))
            {
                var stamp = archiveName.Match(file.Name);
                bool eligible = Path.GetDirectoryName(file.FullName)!.Equals(root, StringComparison.OrdinalIgnoreCase) && stamp.Success &&
                    DateTime.TryParseExact(stamp.Groups["date"].Value, "yyyyMMdd'T'HHmmssfff", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var archived) && archived <= cutoff && file.LastWriteTimeUtc <= cutoff;
                string reason = eligible ? $"Journal texte archivé depuis plus de {keepDays} jours." : "Journal courant, paramètres, référence de suivi ou fichier non reconnu : conservé.";
                MaintenanceFile metadata;
                try {
                    Resolve(Path.GetRelativePath(root, file.FullName));
                    if (eligible && Encoding.UTF8.GetString(Read(Path.GetRelativePath(root, file.FullName), 16 * 1024 * 1024)).Contains("\tERROR\t", StringComparison.OrdinalIgnoreCase))
                    { eligible = false; reason = "Archive contenant des erreurs : conservée pour le diagnostic."; }
                    metadata = Metadata(file, eligible);
                }
                catch { eligible = false; reason = "Fichier illisible ou redirigé : conservé."; metadata = Metadata(file); }
                items.Add(new("file:" + Path.GetRelativePath(root, file.FullName), archiveName.IsMatch(file.Name) ? "Journal texte archivé" : "Autre fichier local", reason, eligible, new[] { metadata }));
            }
            if (read > MaximumRead) throw new InvalidDataException("Limite de lecture atteinte.");
            return new(date, keepDays, true, Array.AsReadOnly(items.OrderByDescending(i => i.Eligible).ThenBy(i => i.Id).ToArray()),
                "Périmètre : journaux locaux et fichiers temporaires associés aux anciennes opérations réussies. ISO, Recovery, caches d’outils, réglages et dossiers personnels exclus.");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException)
        { return new(date, keepDays, false, Array.Empty<MaintenanceItem>(), "Analyse incomplète : " + ex.Message + " Aucun nettoyage autorisé."); }
    }
    public MaintenanceResult Clean(MaintenancePlan preview, IReadOnlyCollection<string> selectedIds)
    {
        if (!preview.Complete || preview.CreatedUtc > now().AddMinutes(1) || preview.CreatedUtc < now().AddMinutes(-15))
            throw new IOException("Cet aperçu est incomplet ou a expiré. Relance l’analyse.");
        var selected = preview.Items.Where(i => i.Eligible && selectedIds.Contains(i.Id)).ToArray();
        if (selected.Length == 0) throw new IOException("Aucun élément nettoyable sélectionné.");
        RefuseLinks(root);
        var fresh = Scan(preview.KeepDays);
        if (!fresh.Complete) throw new IOException("La nouvelle vérification n’est pas complète. Aucun fichier supprimé.");
        string auditDirectory = Resolve("Maintenance"); Directory.CreateDirectory(auditDirectory); RefuseLinks(auditDirectory);
        string auditPath = Path.Combine(auditDirectory, "Cleanup-" + Guid.NewGuid().ToString("N") + ".json");
        using var audit = new FileStream(auditPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        var deleted = new List<string>(); var issues = new List<string>(); long bytes = 0; int skipped = 0;
        bool auditHealthy = true;
        void Save(string state) {
            try { audit.Position = 0; audit.SetLength(0); JsonSerializer.Serialize(audit, new { Schema = 1, State = state, UpdatedUtc = now(), DeletedFiles = deleted, DeletedBytes = bytes, SkippedItems = skipped, Issues = issues }); audit.Flush(true); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { auditHealthy = false; throw; }
        }
        Save("Running");
        foreach (var item in selected)
        {
            var current = fresh.Items.FirstOrDefault(i => i.Id == item.Id && i.Eligible);
            if (current == null || !current.Files.SequenceEqual(item.Files)) {
                skipped++; issues.Add(item.Id + " : état ou contenu modifié depuis l’aperçu, conservé.");
                try { Save("Running"); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { issues.Add("Écriture du bilan interrompue : nettoyage arrêté."); break; }
                continue;
            }
            var handles = new List<(FileStream Stream, MaintenanceFile File)>();
            try
            {
                // Open every group member exclusively before any deletion. Delete by
                // verified handle so a replacement path can never target another file.
                foreach (var file in item.Files)
                {
                    string path = Resolve(file.RelativePath);
                    // Resolve has already enforced a canonical local path and refused
                    // links. Use the extended spelling for the native API as .NET's
                    // file APIs do, including when a profile path exceeds MAX_PATH.
                    var native = CreateFile(@"\\?\" + path, 0xC0010000, 0, IntPtr.Zero, 3, 0x80, IntPtr.Zero);
                    if (native.IsInvalid) { int error = Marshal.GetLastWin32Error(); native.Dispose(); throw new IOException($"Ouverture exclusive refusée par Windows (code {error}) : groupe conservé."); }
                    var input = new FileStream(native, FileAccess.ReadWrite);
                    handles.Add((input, file)); RefuseLinks(path); ExactPath(input.SafeFileHandle, path);
                    if (input.Length != file.Length || File.GetLastWriteTimeUtc(path) != file.ModifiedUtc || Convert.ToHexString(SHA256.HashData(input)) != file.Sha256)
                        throw new IOException("Le fichier a changé ou est utilisé : groupe conservé.");
                }
                foreach (var handle in handles)
                {
                    var info = new Disposition { Delete = true };
                    if (!SetFileInformationByHandle(handle.Stream.SafeFileHandle, 4, ref info, (uint)Marshal.SizeOf<Disposition>())) throw new IOException("Suppression refusée par Windows.");
                    handle.Stream.Dispose(); deleted.Add(handle.File.RelativePath); bytes += handle.File.Length; Save("Running");
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            { skipped++; issues.Add(item.Id + " : " + ex.Message); if (!auditHealthy) { issues.Add("Écriture du bilan interrompue : nettoyage arrêté, résultat partiel à vérifier."); break; } }
            finally { foreach (var handle in handles) handle.Stream.Dispose(); }
        }
        if (auditHealthy) try { Save(issues.Count == 0 ? "Completed" : "Partial"); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { issues.Add("Le bilan final n’a pas pu être enregistré. Les suppressions indiquées ont été vérifiées ; le rapport local reste incomplet."); }
        return new(deleted.Count, bytes, skipped, issues.AsReadOnly(), auditPath);
    }
    private static void ExactPath(SafeFileHandle handle, string expected)
    {
        var buffer = new StringBuilder(32768); uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0 || length >= buffer.Capacity || !buffer.ToString().Replace(@"\\?\", "").Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new IOException("Le chemin réel du fichier n’est pas celui de l’aperçu.");
    }
    [StructLayout(LayoutKind.Sequential)] private struct Disposition { [MarshalAs(UnmanagedType.U1)] public bool Delete; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref Disposition info, uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint length, uint flags);
}
