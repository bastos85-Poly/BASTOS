using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace Bastos.Native.Services;

public sealed record CleanerCategory(string Id, string Name, string Description, string Group, bool DefaultSelected);
public sealed record CleanerOption(string Id, string CategoryId, string Name, string Path);
public sealed record CleanerFile(string Id, string CategoryId, string FullPath, string Root, long Length, DateTime LastWriteUtc);
public sealed class CleanerScan
{
    public DateTime CreatedUtc { get; }
    public IReadOnlyList<CleanerFile> Files { get; }
    public IReadOnlyList<string> Warnings { get; }
    public bool Complete { get; }
    public long TotalBytes => Files.Sum(f => f.Length);
    internal CleanerScan(DateTime date, IEnumerable<CleanerFile> files, IEnumerable<string> warnings, bool complete)
    { CreatedUtc = date; Files = Array.AsReadOnly(files.ToArray()); Warnings = Array.AsReadOnly(warnings.ToArray()); Complete = complete; }
}
public sealed record CleanerResult(IReadOnlyList<string> RemovedFileIds, int DeletedCount, long BytesRemoved, int Skipped, IReadOnlyList<string> Errors, bool Cancelled);

/// <summary>Inventories explicit cache roots; never executes an application, shell cleanup or registry action.</summary>
public sealed class SystemCleanerService
{
    internal sealed record Rule(string CategoryId, string Root, string Pattern = "*", bool Recursive = true, int MinAgeDays = 0)
    {
        internal string Id => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(CategoryId + "|" + Root + "|" + Pattern + "|" + Recursive + "|" + MinAgeDays)))[..24];
    }
    private sealed record Identity(string Hash, uint Volume, ulong FileIndex, DateTime CreationUtc, int MinAgeDays);
    private readonly IReadOnlyList<Rule>? fixtureRules;
    private readonly IReadOnlyList<Rule> allRules;
    private readonly Func<DateTime> clock;
    private readonly int maximumFiles;
    private readonly SemaphoreSlim gate = new(1, 1);
    private CleanerScan? current;
    private Dictionary<string, Identity> identities = new(StringComparer.Ordinal);
    private string[] currentExclusions = Array.Empty<string>();
    public IReadOnlyList<CleanerCategory> Catalog { get; }
    public IReadOnlyList<CleanerOption> Options { get; }
    public SystemCleanerService() : this(null, null, 250000) { }
    internal SystemCleanerService(IReadOnlyList<Rule>? rules, Func<DateTime>? clock = null, int maximumFiles = 250000)
    {
        fixtureRules = rules; this.clock = clock ?? (() => DateTime.UtcNow); this.maximumFiles = maximumFiles;
        Catalog = Array.AsReadOnly(new[] {
            new CleanerCategory("temp", "Fichiers temporaires", "Fichiers temporaires du compte et de Windows ; les fichiers utilisés restent en place.", "Système", true),
            new CleanerCategory("windows-update", "Cache Windows Update", "Téléchargements de mises à jour. Un accès refusé est signalé ; aucun service n’est arrêté.", "Système", true),
            new CleanerCategory("windows-logs", "Journaux Windows", "Anciens journaux CBS et DISM, rapports d’erreurs et fichiers de diagnostic.", "Système", true),
            new CleanerCategory("crash-dumps", "Rapports de plantage", "Vidages mémoire et rapports de plantage ; utiles pour diagnostiquer une panne.", "Système", true),
            new CleanerCategory("thumbnails", "Miniatures et icônes", "Caches reconstruits automatiquement par l’Explorateur Windows.", "Système", true),
            new CleanerCategory("shader-cache", "Cache des shaders", "Caches DirectX, NVIDIA et AMD ; visibles mais décochés car leur reconstruction peut ralentir les premiers lancements.", "Système", true),
            new CleanerCategory("prefetch", "Cache de lancement Prefetch", "Données de lancement visibles mais décochées par défaut ; réinitialisation facultative.", "Système", true),
            new CleanerCategory("font-cache", "Cache des polices", "Données de rendu des polices ; les fichiers utilisés par Windows sont conservés.", "Système", true),
            new CleanerCategory("internet-cache", "Caches Internet et Bureau à distance", "Cache web des composants Windows et vignettes des sessions Bureau à distance.", "Système", true),
            new CleanerCategory("diagnostics", "Rapports de diagnostic", "Résultats WinSAT, diagnostics énergétiques et traces de dépannage. Les derniers rapports peuvent être utiles.", "Système", true),
            new CleanerCategory("event-archives", "Archives des événements", "Uniquement Archive-*.evtx. Les journaux d’événements actifs de Windows et de sécurité sont conservés.", "Système", true),
            new CleanerCategory("defender-logs", "Journaux de diagnostic Defender", "Journaux de support uniquement. Historique des détections, quarantaine, signatures et métadonnées conservés.", "Système", true),
            new CleanerCategory("certificate-cache", "Cache de validation des certificats", "Listes de révocation mises en cache par les comptes système ; Windows devra les télécharger de nouveau.", "Système", true),
            new CleanerCategory("browsers", "Caches des navigateurs", "Chrome, Edge, Firefox, Brave, Opera, Vivaldi, Chromium et Helium. Mots de passe, cookies et historique conservés.", "Applications", true),
            new CleanerCategory("apps", "Caches des applications", "Caches et anciens journaux des applications détectées. Certains contenus hors connexion devront être téléchargés de nouveau.", "Applications", true),
            new CleanerCategory("games", "Caches des jeux et lanceurs", "Caches web et journaux Steam, Epic, EA, Battle.net et autres lanceurs. Sauvegardes et jeux installés conservés.", "Applications", true),
            new CleanerCategory("developer-cache", "Caches de développement", "Paquets téléchargés et caches de compilation. Les prochaines compilations ou installations peuvent être plus lentes.", "Applications", true),
            new CleanerCategory("ai-tools", "Caches des outils d’IA", "Caches et journaux des assistants et applications d’IA détectés. Les modèles et conversations ne sont pas ciblés.", "Outils d’IA", true),
            new CleanerCategory("shortcuts", "Raccourcis cassés", "Raccourcis .lnk dont la cible locale est absente. Les lecteurs indisponibles et chemins réseau sont conservés.", "Raccourcis", true),
            new CleanerCategory("privacy-files", "Listes d’activité Windows", "Raccourcis récents et listes de raccourcis Windows. Suppression facultative de traces d’usage, sans toucher à l’historique du navigateur.", "Traces de confidentialité", true)
        });
        allRules = fixtureRules ?? Rules();
        Options = Array.AsReadOnly(allRules.GroupBy(r => r.Id).Select(g => g.First()).Select(r => new CleanerOption(r.Id, r.CategoryId, DescribeRule(r), r.Root)).ToArray());
    }

    private static string DescribeRule(Rule rule)
    {
        string path = rule.Root.Replace('/', '\\');
        string[] segments = path.Split('\\', StringSplitOptions.RemoveEmptyEntries);
        string leaf = segments.LastOrDefault() ?? path;
        string parent = segments.Length > 1 ? segments[^2] : "";
        string label = rule.CategoryId switch
        {
            "temp" when path.Contains(@"ServiceProfiles\LocalService\", StringComparison.OrdinalIgnoreCase) => "Temp du service local",
            "temp" when path.Contains(@"ServiceProfiles\NetworkService\", StringComparison.OrdinalIgnoreCase) => "Temp du service réseau",
            "temp" when path.Contains(@"ServiceProfiles\LocalSystem\", StringComparison.OrdinalIgnoreCase) => "Temp du compte système",
            "temp" when path.Contains(@"\SystemTemp", StringComparison.OrdinalIgnoreCase) => "Temp système Windows",
            "temp" when path.Contains(@"\Windows\Temp", StringComparison.OrdinalIgnoreCase) => "Temp Windows",
            "temp" => "Temp utilisateur",
            "windows-update" => "Téléchargements Windows Update",
            "crash-dumps" when leaf.Equals("CrashDumps", StringComparison.OrdinalIgnoreCase) => "Vidages des applications",
            "crash-dumps" when leaf.Equals("Minidump", StringComparison.OrdinalIgnoreCase) => "Minidumps Windows",
            "crash-dumps" when leaf.Equals("LiveKernelReports", StringComparison.OrdinalIgnoreCase) => "Vidages du noyau",
            "crash-dumps" => "Vidage mémoire système",
            "thumbnails" when rule.Pattern.StartsWith("thumbcache", StringComparison.OrdinalIgnoreCase) => "Miniatures de l’Explorateur",
            "thumbnails" => "Icônes de l’Explorateur",
            "internet-cache" when leaf.Equals("Cache", StringComparison.OrdinalIgnoreCase) => "Vignettes Bureau à distance",
            "internet-cache" => "Cache Internet Windows",
            "event-archives" => "Archives des événements Windows",
            "shortcuts" when path.Contains(@"\User Pinned\TaskBar", StringComparison.OrdinalIgnoreCase) => "Raccourcis de la barre des tâches",
            "shortcuts" when path.Contains(@"\Start Menu\", StringComparison.OrdinalIgnoreCase) => "Raccourcis du menu Démarrer",
            "shortcuts" => "Raccourcis du Bureau",
            "privacy-files" when leaf.EndsWith("history", StringComparison.OrdinalIgnoreCase) => "Historique du terminal · " + leaf,
            "privacy-files" when leaf.Equals("Recent", StringComparison.OrdinalIgnoreCase) => "Éléments récents · " + parent,
            "privacy-files" => "Traces récentes · " + leaf,
            _ => parent + " / " + leaf
        };
        return rule.Pattern == "*" ? label : label + " · " + rule.Pattern;
    }

    public async Task<CleanerScan> ScanAsync(IEnumerable<string> categoryIds, IEnumerable<string> exclusions, int ageDays,
        IProgress<string>? progress = null, CancellationToken token = default, IEnumerable<string>? optionIds = null)
    {
        if (ageDays is < 0 or > 3650) throw new ArgumentOutOfRangeException(nameof(ageDays));
        var ids = categoryIds.ToHashSet(StringComparer.Ordinal);
        if (ids.Any(id => !Catalog.Any(c => c.Id == id))) throw new ArgumentException("Catégorie inconnue.");
        var selectedOptions = optionIds?.ToHashSet(StringComparer.Ordinal);
        if (selectedOptions != null && selectedOptions.Any(id => !Options.Any(o => o.Id == id))) throw new ArgumentException("Sous-option inconnue.");
        var excluded = exclusions.Where(x => !string.IsNullOrWhiteSpace(x)).Select(Canonical).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        await gate.WaitAsync(token);
        try
        {
            current = null; identities.Clear();
            return await Task.Run(() => Scan(ids, excluded, ageDays, progress, token, selectedOptions), token);
        }
        finally { gate.Release(); }
    }

    private CleanerScan Scan(HashSet<string> selected, string[] excluded, int ageDays, IProgress<string>? progress, CancellationToken token, HashSet<string>? selectedOptions)
    {
        DateTime now = clock();
        var files = new List<CleanerFile>(); var warnings = new List<string>();
        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var known = new Dictionary<string, Identity>(StringComparer.Ordinal);
        bool complete = true; int visited = 0, visitedDirectories = 0;
        foreach (var rule in allRules.Where(r => selected.Contains(r.CategoryId) && (selectedOptions == null || selectedOptions.Contains(r.Id))))
        {
            token.ThrowIfCancellationRequested();
            DateTime ruleCutoff = Cutoff(now, Math.Max(ageDays, rule.MinAgeDays));
            string root = Canonical(rule.Root);
            if (Excluded(root, excluded) || !Directory.Exists(root)) continue;
            progress?.Report("Analyse : " + Catalog.First(c => c.Id == rule.CategoryId).Name);
            var directories = new Stack<string>(); directories.Push(root);
            while (directories.Count > 0)
            {
                token.ThrowIfCancellationRequested(); string dir = directories.Pop();
                if (Excluded(dir, excluded)) continue;
                if (++visitedDirectories > maximumFiles) { complete = false; Warn(warnings, "Limite de dossiers atteinte. Réduis les catégories puis relance l’analyse."); break; }
                try
                {
                    RefuseLinks(dir);
                    // Pin the directory chain while enumerating to prevent redirecting the traversal.
                    using var pinned = PinAncestors(Path.Combine(dir, "__entry__"));
                    foreach (string path in Directory.EnumerateFiles(dir, rule.Pattern, SearchOption.TopDirectoryOnly))
                    {
                        token.ThrowIfCancellationRequested();
                        if (++visited > maximumFiles) { complete = false; Warn(warnings, "Limite d’inventaire atteinte. Réduis les catégories puis relance l’analyse."); break; }
                        if (Excluded(path, excluded) || !unique.Add(path)) continue;
                        try
                        {
                            RefuseLinks(path);
                            var info = new FileInfo(path);
                            if ((info.Attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Offline | FileAttributes.System)) != 0 || info.LastWriteTimeUtc > ruleCutoff) continue;
                            if (rule.CategoryId == "shortcuts" && !IsBrokenShortcut(path)) continue;
                            using var stream = OpenFile(path, false);
                            var native = Info(stream.SafeFileHandle);
                            if (native.Links > 1) { Warn(warnings, "Lien physique conservé : " + path); continue; }
                            long length = stream.Length; DateTime modified = FileTime(native.WriteHigh, native.WriteLow);
                            if (modified > ruleCutoff) continue;
                            string hash = Hash(stream, token);
                            var after = Info(stream.SafeFileHandle);
                            if (after.WriteHigh != native.WriteHigh || after.WriteLow != native.WriteLow || stream.Length != length)
                            { Warn(warnings, "Fichier modifié pendant l’analyse, conservé : " + path); continue; }
                            string id = Guid.NewGuid().ToString("N");
                            files.Add(new(id, rule.CategoryId, Canonical(path), root, length, modified));
                            known.Add(id, new(hash, native.Volume, ((ulong)native.IndexHigh << 32) | native.IndexLow, FileTime(native.CreatedHigh, native.CreatedLow), Math.Max(ageDays, rule.MinAgeDays)));
                            if (files.Count % 100 == 0) progress?.Report($"{files.Count:N0} fichiers analysés…");
                        }
                        catch (Exception ex) when (Handled(ex)) { Warn(warnings, "Fichier conservé : " + path + " — " + ex.Message); }
                    }
                    if (!complete) break;
                    if (rule.Recursive)
                        foreach (string child in Directory.EnumerateDirectories(dir))
                        {
                            token.ThrowIfCancellationRequested();
                            if (!Excluded(child, excluded) && (File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0) directories.Push(child);
                        }
                }
                catch (Exception ex) when (Handled(ex)) { Warn(warnings, "Dossier non analysé : " + dir + " — " + ex.Message); }
            }
            if (!complete) break;
        }
        token.ThrowIfCancellationRequested();
        current = new CleanerScan(now, files, warnings, complete); identities = known; currentExclusions = excluded;
        return current;
    }

    public async Task<CleanerResult> CleanAsync(CleanerScan scan, IEnumerable<string> selectedFileIds,
        IProgress<string>? progress = null, CancellationToken token = default)
    {
        var ids = selectedFileIds.ToHashSet(StringComparer.Ordinal);
        await gate.WaitAsync(CancellationToken.None);
        try
        {
            if (!ReferenceEquals(current, scan) || !scan.Complete || clock() - scan.CreatedUtc > TimeSpan.FromMinutes(30) || clock() < scan.CreatedUtc)
                throw new InvalidOperationException("L’aperçu est absent, incomplet, périmé ou déjà utilisé. Relance l’analyse.");
            if (ids.Any(id => !identities.ContainsKey(id))) throw new ArgumentException("La sélection ne correspond pas à l’aperçu.");
            current = null; // A failed or cancelled cleanup is not replayable.
            return await Task.Run(() => Clean(scan, ids, progress, token));
        }
        finally { gate.Release(); }
    }

    private CleanerResult Clean(CleanerScan scan, HashSet<string> selected, IProgress<string>? progress, CancellationToken token)
    {
        var removed = new List<string>(); var errors = new List<string>(); long bytes = 0; int skipped = 0, count = 0;
        foreach (var file in scan.Files.Where(f => selected.Contains(f.Id)))
        {
            if (token.IsCancellationRequested) break;
            progress?.Report($"Vérification et nettoyage : {++count:N0} / {selected.Count:N0}");
            try
            {
                if (!Within(file.FullPath, file.Root) || Excluded(file.FullPath, currentExclusions)) throw new IOException("Chemin hors du périmètre.");
                if (file.Root.EndsWith("-updater", StringComparison.OrdinalIgnoreCase) &&
                    (Path.GetFileName(file.FullPath).Equals("installer.exe", StringComparison.OrdinalIgnoreCase) || Path.GetFileName(file.FullPath).Equals("current.blockmap", StringComparison.OrdinalIgnoreCase)) &&
                    Directory.Exists(Path.Combine(file.Root, "pending"))) throw new IOException("Mise à jour en attente : paquet conservé.");
                RefuseLinks(file.FullPath);
                using var pinned = PinAncestors(file.FullPath);
                if (file.CategoryId == "shortcuts" && !IsBrokenShortcut(file.FullPath)) throw new IOException("La cible du raccourci est disponible : conservé.");
                using (var stream = OpenFile(file.FullPath, true))
                {
                    var info = Info(stream.SafeFileHandle); var expected = identities[file.Id];
                    if (info.Links != 1 || info.Volume != expected.Volume || (((ulong)info.IndexHigh << 32) | info.IndexLow) != expected.FileIndex ||
                        FileTime(info.CreatedHigh, info.CreatedLow) != expected.CreationUtc || FileTime(info.WriteHigh, info.WriteLow) != file.LastWriteUtc ||
                        file.LastWriteUtc > Cutoff(clock(), expected.MinAgeDays) || stream.Length != file.Length || Hash(stream, token) != expected.Hash)
                        throw new IOException("Fichier modifié depuis l’aperçu : conservé.");
                    token.ThrowIfCancellationRequested();
                    var disposition = new Disposition { Delete = true };
                    if (!SetFileInformationByHandle(stream.SafeFileHandle, 4, ref disposition, 1))
                        throw new IOException("Suppression refusée par Windows (" + Marshal.GetLastWin32Error() + ").");
                }
                // Ancestors remain pinned through the independent post-delete check.
                if (File.Exists(file.FullPath) || Directory.Exists(file.FullPath)) throw new IOException("Disparition du fichier non confirmée.");
                removed.Add(file.Id); bytes += file.Length;
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) when (Handled(ex)) { skipped++; Warn(errors, file.FullPath + " — " + ex.Message); }
        }
        return new(Array.AsReadOnly(removed.ToArray()), removed.Count, bytes, skipped, Array.AsReadOnly(errors.ToArray()), token.IsCancellationRequested);
    }

    private static void Warn(List<string> list, string message) { if (list.Count < 200) list.Add(message); else if (list.Count == 200) list.Add("Autres éléments ignorés : liste de détails limitée à 200."); }
    private static bool Handled(Exception ex) => ex is IOException or UnauthorizedAccessException or ArgumentException or System.Security.SecurityException or NotSupportedException;
    // Match Kudu's default one-hour protection even when the user does not request an older age.
    private static DateTime Cutoff(DateTime now, int ageDays) => now.AddMinutes(-Math.Max(60, ageDays * 1440));
    private static bool Within(string path, string root) => path.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
    private static bool Excluded(string path, IEnumerable<string> exclusions) => exclusions.Any(e => path.Equals(e, StringComparison.OrdinalIgnoreCase) || Within(path, e));
    private static string Canonical(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path)) throw new ArgumentException("Un chemin local absolu est requis.");
        string full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
        if (full.StartsWith(@"\\", StringComparison.Ordinal) || full.IndexOf(':', 2) >= 0) throw new ArgumentException("Les chemins réseau et flux alternatifs sont exclus.");
        return full;
    }
    private static void RefuseLinks(string path)
    {
        for (string? item = path; item != null; item = Path.GetDirectoryName(item))
            if ((File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0) throw new IOException("Lien ou jonction refusé.");
    }
    private sealed class Pins(List<SafeFileHandle> handles) : IDisposable { public void Dispose() { foreach (var handle in handles) handle.Dispose(); } }
    private static Pins PinAncestors(string path)
    {
        var dirs = new Stack<string>();
        for (string? dir = Path.GetDirectoryName(path); dir != null; dir = Path.GetDirectoryName(dir)) dirs.Push(dir);
        var handles = new List<SafeFileHandle>();
        try
        {
            foreach (string dir in dirs)
            {
                var handle = CreateFile(Extended(dir), 0x80, 3, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
                if (handle.IsInvalid) { handle.Dispose(); throw new IOException("Dossier occupé ou inaccessible (" + Marshal.GetLastWin32Error() + ")."); }
                handles.Add(handle);
                if ((Info(handle).Attributes & (uint)FileAttributes.ReparsePoint) != 0) throw new IOException("Dossier redirigé : refusé.");
                ExactPath(handle, dir);
            }
            return new Pins(handles);
        }
        catch { foreach (var h in handles) h.Dispose(); throw; }
    }
    private static string Extended(string path) => @"\\?\" + path;
    private static FileStream OpenFile(string path, bool delete)
    {
        // An inventory may read caches held open by a browser. Deletion still needs exclusive access.
        var handle = CreateFile(Extended(path), 0x80000080u | (delete ? 0x10000u : 0u), delete ? 0u : 7u, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (handle.IsInvalid) { int error = Marshal.GetLastWin32Error(); handle.Dispose(); throw new IOException("Fichier utilisé ou inaccessible (" + error + ")."); }
        try
        {
            var info = Info(handle);
            if ((info.Attributes & (uint)(FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Offline | FileAttributes.System)) != 0) throw new IOException("Fichier spécial conservé.");
            ExactPath(handle, path);
            return new FileStream(handle, FileAccess.Read);
        }
        catch { handle.Dispose(); throw; }
    }
    private static string Hash(Stream stream, CancellationToken token)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256); byte[] buffer = new byte[65536]; int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) != 0) { token.ThrowIfCancellationRequested(); hash.AppendData(buffer, 0, read); }
        return Convert.ToHexString(hash.GetHashAndReset());
    }
    private static DateTime FileTime(uint high, uint low) => DateTime.FromFileTimeUtc(unchecked((long)(((ulong)high << 32) | low)));
    private static NativeInfo Info(SafeFileHandle handle)
    { if (!GetFileInformationByHandle(handle, out var info)) throw new IOException("Identité du fichier non vérifiable."); return info; }
    private static void ExactPath(SafeFileHandle handle, string path)
    {
        var text = new StringBuilder(32768); uint size = GetFinalPathNameByHandle(handle, text, (uint)text.Capacity, 0);
        if (size == 0 || size >= text.Capacity || !text.ToString().Replace(@"\\?\", "").TrimEnd('\\').Equals(path.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
            throw new IOException("Le chemin réel diffère du chemin attendu.");
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativeInfo
    { public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh, WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
    [StructLayout(LayoutKind.Sequential)] private struct Disposition { [MarshalAs(UnmanagedType.U1)] public bool Delete; }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out NativeInfo info);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int kind, ref Disposition info, uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint size, uint flags);

    private static IReadOnlyList<Rule> Rules()
    {
        var rules = new List<Rule>();
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows), programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        void Add(string id, string root, string pattern = "*", bool recursive = true) { if (!string.IsNullOrWhiteSpace(root)) rules.Add(new(id, root, pattern, recursive)); }
        Add("temp", Path.Combine(local, "Temp")); Add("temp", Path.Combine(windows, "Temp"));
        Add("temp", Path.Combine(windows, "SystemTemp"));
        foreach (string account in new[] { "LocalService", "NetworkService", "LocalSystem" }) Add("temp", Path.Combine(windows, "ServiceProfiles", account, "AppData", "Local", "Temp"));
        Add("windows-update", Path.Combine(windows, "SoftwareDistribution", "Download"));
        foreach (string pattern in new[] { "*.log", "*.etl" }) Add("windows-logs", Path.Combine(windows, "SoftwareDistribution", "DataStore", "Logs"), pattern);
        foreach (string folder in new[] { "Logs", "Panther", "debug", "tracing", "System32\\LogFiles\\Firewall", "System32\\LogFiles\\WMI", "System32\\LogFiles\\HTTPERR", "System32\\LogFiles\\setupcln" })
            foreach (string pattern in new[] { "*.log", "*.etl" }) Add("windows-logs", Path.Combine(windows, folder), pattern);
        foreach (string relative in new[] { "Microsoft\\Windows\\RUXIM", "USOShared\\Logs", "Microsoft\\Search\\Data\\Applications\\Windows\\GatherLogs", "Microsoft\\Diagnosis\\ETLLogs" })
            foreach (string pattern in new[] { "*.log", "*.etl" }) Add("windows-logs", Path.Combine(programData, relative), pattern);
        foreach (string framework in new[] { "CLR_v4.0", "CLR_v4.0_32" }) Add("windows-logs", Path.Combine(local, "Microsoft", framework, "UsageLogs"), "*.log");
        Add("windows-logs", Path.Combine(local, "Microsoft", "Windows", "WER"));
        Add("windows-logs", Path.Combine(programData, "Microsoft", "Windows", "WER"));
        Add("crash-dumps", Path.Combine(local, "CrashDumps")); Add("crash-dumps", Path.Combine(windows, "Minidump"), "*.dmp");
        Add("crash-dumps", Path.Combine(windows, "LiveKernelReports"), "*.dmp"); Add("crash-dumps", windows, "MEMORY.DMP", false);
        Add("thumbnails", Path.Combine(local, "Microsoft", "Windows", "Explorer"), "thumbcache_*.db", false);
        Add("thumbnails", Path.Combine(local, "Microsoft", "Windows", "Explorer"), "iconcache_*.db", false);
        Add("thumbnails", local, "IconCache.db", false);
        Add("thumbnails", Path.Combine(local, "Microsoft", "Windows", "Caches"));
        Add("prefetch", Path.Combine(windows, "Prefetch"), "*.pf", false);
        Add("font-cache", Path.Combine(windows, "ServiceProfiles", "LocalService", "AppData", "Local", "FontCache"));
        Add("internet-cache", Path.Combine(local, "Microsoft", "Windows", "INetCache"));
        Add("internet-cache", Path.Combine(local, "Microsoft", "Terminal Server Client", "Cache"));
        Add("diagnostics", Path.Combine(local, "ElevatedDiagnostics"));
        Add("diagnostics", Path.Combine(windows, "Performance", "WinSAT", "DataStore"), "*.xml");
        Add("diagnostics", Path.Combine(programData, "Microsoft", "Windows", "Power Efficiency Diagnostics"));
        Add("diagnostics", Path.Combine(windows, "System32"), "energy-report.html", false);
        Add("diagnostics", Path.Combine(programData, "Microsoft", "RAC", "PublishedData"));
        foreach (string pattern in new[] { "*.log", "*.etl" }) Add("diagnostics", Path.Combine(windows, "AppCompat", "Programs"), pattern);
        Add("event-archives", Path.Combine(windows, "System32", "winevt", "Logs"), "Archive-*.evtx", false);
        foreach (string relative in new[] { "Support", "Network Inspection System\\Support" })
            foreach (string pattern in new[] { "*.log", "*.etl" }) Add("defender-logs", Path.Combine(programData, "Microsoft", "Windows Defender", relative), pattern);
        foreach (string account in new[] { "LocalService", "NetworkService" })
            Add("certificate-cache", Path.Combine(windows, "ServiceProfiles", account, "AppData", "LocalLow", "Microsoft", "CryptnetUrlCache"));
        Add("certificate-cache", Path.Combine(windows, "System32", "config", "systemprofile", "AppData", "LocalLow", "Microsoft", "CryptnetUrlCache"));
        foreach (string relative in new[] { "D3DSCache", "NVIDIA\\DXCache", "NVIDIA\\GLCache", "NVIDIA Corporation\\NV_Cache", "AMD\\DxCache", "AMD\\DxcCache", "AMD\\GLCache", "AMD\\VkCache", "Intel\\ShaderCache", "Unity\\cache" }) Add("shader-cache", Path.Combine(local, relative));
        Add("shader-cache", Path.Combine(programData, "NVIDIA Corporation", "NV_Cache"));
        Add("shader-cache", Path.Combine(roaming, "NVIDIA", "ComputeCache"));
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        // Additional direct Windows targets from Kudu 3.10.0's MIT rule catalog.
        Add("apps", Path.Combine(roaming, "Telegram Desktop", "tdata", "user_data"));
        Add("apps", Path.Combine(roaming, "Telegram Desktop", "tdata", "emoji"));
        Add("developer-cache", Path.Combine(home, ".m2", "repository"));
        foreach (string relative in new[] { "anaconda3\\pkgs", "miniconda3\\pkgs", ".conda\\pkgs", ".cargo\\registry\\src", ".cargo\\git\\checkouts", ".aws\\cli\\cache" })
            Add("developer-cache", Path.Combine(home, relative));
        foreach (string relative in new[] { ".claude\\cache", ".claude\\plugins\\cache" }) rules.Add(new("ai-tools", Path.Combine(home, relative), MinAgeDays: 1));
        rules.Add(new("ai-tools", Path.Combine(home, ".codex", "tmp"), MinAgeDays: 1));
        string? systemDrive = Path.GetPathRoot(windows);
        if (!string.IsNullOrEmpty(systemDrive)) rules.Add(new("apps", Path.Combine(systemDrive, "AMD"), MinAgeDays: 14));
        try
        {
            foreach (string updater in Directory.EnumerateDirectories(local).Where(p => Path.GetFileName(p).EndsWith("-updater", StringComparison.OrdinalIgnoreCase)))
            {
                if ((File.GetAttributes(updater) & FileAttributes.ReparsePoint) != 0 || Directory.Exists(Path.Combine(updater, "pending"))) continue;
                foreach (string name in new[] { "installer.exe", "current.blockmap" }) rules.Add(new("apps", updater, name, false, 14));
            }
        }
        catch (Exception e) when (Handled(e)) { }
        Add("shortcuts", Path.Combine(home, "Desktop"), "*.lnk");
        Add("shortcuts", Path.Combine(roaming, "Microsoft", "Windows", "Start Menu", "Programs"), "*.lnk");
        Add("shortcuts", Path.Combine(roaming, "Microsoft", "Internet Explorer", "Quick Launch", "User Pinned", "TaskBar"), "*.lnk");
        Add("shortcuts", Path.Combine(programData, "Microsoft", "Windows", "Start Menu", "Programs"), "*.lnk");
        Add("shortcuts", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory), ""), "*.lnk");
        Add("privacy-files", Path.Combine(roaming, "Microsoft", "Windows", "Recent"), "*.lnk", false);
        Add("privacy-files", Path.Combine(roaming, "Microsoft", "Windows", "Recent", "AutomaticDestinations"), "*.automaticDestinations-ms", false);
        Add("privacy-files", Path.Combine(roaming, "Microsoft", "Windows", "Recent", "CustomDestinations"), "*.customDestinations-ms", false);
        Add("privacy-files", Path.Combine(roaming, "Microsoft", "Office", "Recent"), "*.lnk", false);
        Add("privacy-files", Path.Combine(roaming, "Microsoft", "Windows", "PowerShell", "PSReadLine"), "*_history.txt", false);
        foreach (string name in new[] { ".bash_history", ".python_history", ".node_repl_history" }) Add("privacy-files", home, name, false);
        foreach (string relative in new[] { "AppData\\LocalLow\\NVIDIA\\DXCache", "AppData\\LocalLow\\NVIDIA\\PerDriverVersion\\DXCache" }) Add("shader-cache", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), relative));
        string[] profileCaches = { "Cache\\Cache_Data", "Code Cache", "GPUCache", "Service Worker\\CacheStorage", "Shared Dictionary\\cache", "DawnWebGPUCache", "DawnGraphiteCache" };
        string[] sharedCaches = { "component_crx_cache", "extensions_crx_cache", "GrShaderCache", "ShaderCache", "GraphiteDawnCache", "GPUPersistentCache", "PnaclTranslationCache" };
        foreach (string relative in new[] { "Google\\Chrome\\User Data", "Microsoft\\Edge\\User Data", "BraveSoftware\\Brave-Browser\\User Data", "Vivaldi\\User Data", "Chromium\\User Data", "imput\\Helium\\User Data", "Helium\\User Data", "Arc\\User Data", "Thorium\\User Data", "Supermium\\User Data", "Cromite\\User Data", "ArcSoft\\CatsXP\\User Data" })
        {
            string userData = Path.Combine(local, relative);
            foreach (string profile in Profiles(userData, p => Path.GetFileName(p) == "Default" || Path.GetFileName(p).StartsWith("Profile ", StringComparison.Ordinal)))
                foreach (string cache in profileCaches) Add("browsers", Path.Combine(profile, cache));
            foreach (string cache in sharedCaches) Add("browsers", Path.Combine(userData, cache));
        }
        foreach (string browser in new[] { "Mozilla\\Firefox", "LibreWolf", "Waterfox", "Floorp", "Zen" })
            foreach (string profile in Profiles(Path.Combine(local, browser, "Profiles"), _ => true)) Add("browsers", Path.Combine(profile, "cache2"));
        foreach (string opera in new[] { "Opera Stable", "Opera GX Stable" })
        {
            string root = Path.Combine(roaming, "Opera Software", opera);
            foreach (string cache in profileCaches.Concat(sharedCaches)) Add("browsers", Path.Combine(root, cache));
            foreach (string profile in Profiles(root, p => Path.GetFileName(p) == "Default" || Path.GetFileName(p).StartsWith("Profile ", StringComparison.Ordinal)))
                foreach (string cache in profileCaches) Add("browsers", Path.Combine(profile, cache));
        }
        AddWebView2Rules(rules, local);
        AddCatalogRules(rules);
        return rules;
    }

    // Bounded EBWebView anchor/leaf discovery mirrors the declared Kudu 3.10.0 rule.
    // Profile stores such as IndexedDB, Local Storage and Service Worker are never traversed.
    internal static void AddWebView2Rules(List<Rule> rules, string local)
    {
        string[] patterns = {
            "*/EBWebView", "Microsoft/*/EBWebView", "Microsoft/*/*/EBWebView", "Microsoft/*/*/*/EBWebView",
            "Packages/*/*/EBWebView", "Packages/*/*/*/EBWebView", "Packages/*/*/*/*/EBWebView",
            "TeamViewer/EdgeBrowserControl/*/*/EBWebView", "TeamViewer/EdgeBrowserControl/*/*/*/EBWebView",
            "Zoom/data/WebviewCacheX64/*/EBWebView", "Google/DriveFS/webview2_user_data/*/EBWebView",
            "Microsoft/Office/*/Wef/webview2/*/*/EBWebView"
        };
        var targets = new HashSet<string>(new[] { "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache" }, StringComparer.OrdinalIgnoreCase);
        var excluded = new HashSet<string>(new[] { "File System", "IndexedDB", "Local Storage", "Network", "Service Worker", "Session Storage", "WebStorage", "blob_storage", "databases" }, StringComparer.OrdinalIgnoreCase);
        var anchors = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        int visited = 0;
        foreach (string pattern in patterns)
        {
            var candidates = new List<string> { local };
            foreach (string segment in pattern.Split('/'))
            {
                var next = new List<string>();
                foreach (string candidate in candidates)
                {
                    if (++visited > 100000) return;
                    try
                    {
                        RefuseLinks(candidate);
                        if (segment == "*") next.AddRange(Directory.EnumerateDirectories(candidate).Where(p => (File.GetAttributes(p) & FileAttributes.ReparsePoint) == 0));
                        else { string exact = Path.Combine(candidate, segment); if (Directory.Exists(exact) && (File.GetAttributes(exact) & FileAttributes.ReparsePoint) == 0) next.Add(exact); }
                    }
                    catch (Exception e) when (Handled(e)) { }
                }
                candidates = next;
                if (candidates.Count == 0) break;
            }
            foreach (string candidate in candidates) anchors.Add(candidate);
        }
        var added = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string anchor in anchors)
        {
            var queue = new Queue<(string Path, int Depth)>(); queue.Enqueue((anchor, 0));
            while (queue.Count > 0)
            {
                if (++visited > 100000) return;
                var current = queue.Dequeue();
                try
                {
                    RefuseLinks(current.Path);
                    foreach (string child in Directory.EnumerateDirectories(current.Path))
                    {
                        if ((File.GetAttributes(child) & FileAttributes.ReparsePoint) != 0) continue;
                        string name = Path.GetFileName(child);
                        if (excluded.Contains(name)) continue;
                        if (targets.Contains(name)) { if (added.Add(child)) rules.Add(new("apps", child)); }
                        else if (current.Depth + 1 < 12) queue.Enqueue((child, current.Depth + 1));
                    }
                }
                catch (Exception e) when (Handled(e)) { }
            }
        }
    }
    // Frozen path metadata observed in Kudu 3.10.0's Windows catalog. No Kudu executable code is used.
    // Native prune actions, generic discovery roots, rollback stores and offline asset vaults are not file targets.
    private static void AddCatalogRules(List<Rule> rules)
    {
        const string metadata = """
[{"category":"apps","path":"${APPDATA}/discord/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discord/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discord/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discord/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Microsoft/Teams/Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Slack/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Slack/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Slack/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Slack/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Zoom/data/Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Zoom/data/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Zoom/data/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Zoom/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/CachedData","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/CachedExtensions","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/CachedExtensionVSIXs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code/logs","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/JetBrains","age":0,"children":["caches"]},{"category":"apps","path":"${LOCALAPPDATA}/Spotify/Storage","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Spotify/Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/obs-studio/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/obs-studio/profiler_data","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Adobe/AcroCef/Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Adobe/Common/Media Cache Files","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Adobe/Common/Media Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/npm-cache","age":0,"children":[]},{"category":"developer-cache","path":"${APPDATA}/npm-cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/Yarn/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/.bun/install/cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/pip/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/pipenv/pipenv/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/NuGet/v3-cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/NuGet/plugins-cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/Mozilla/sccache/cache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/.cargo/registry/cache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/go/pkg/mod/cache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/.gradle/caches","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/.gradle/daemon","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Modern MTR/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Modern MTR/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Modern MTR/GPUCache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/Composer/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Docker Desktop/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Docker Desktop/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Docker Desktop/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Docker/log/host","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Docker/log/vm","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/CachedData","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/CachedExtensions","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Signal/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Signal/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Postman/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Postman/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Figma/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Figma/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/GitHub Desktop/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/GitHub Desktop/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/vlc/art_cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Thunderbird/Profiles","age":0,"children":["cache2"]},{"category":"apps","path":"${APPDATA}/GIMP","age":0,"children":["tmp"]},{"category":"apps","path":"${APPDATA}/Blender Foundation/Blender","age":0,"children":["cache"]},{"category":"apps","path":"${APPDATA}/LibreOffice","age":0,"children":["cache"]},{"category":"apps","path":"${APPDATA}/TeamViewer/Logs","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/GoogleEarth/Cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/inkscape/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/krita/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/FileZilla/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/fontconfig/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/.purple/icons","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Transmission/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google","age":0,"children":["caches"]},{"category":"shader-cache","path":"${LOCALAPPDATA}/Unity/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Microsoft/VisualStudio","age":0,"children":["ComponentModelCache"]},{"category":"apps","path":"${APPDATA}/Notion/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/DawnCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/DawnGraphiteCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/DawnWebGPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Notion/Partitions/notion/Shared Dictionary/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/obsidian/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/obsidian/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/obsidian/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/WhatsApp/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/WhatsApp/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/WhatsApp/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Bitwarden/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Bitwarden/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Bitwarden/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/1Password/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/1Password/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/1Password/GPUCache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/.gem","age":0,"children":["cache"]},{"category":"developer-cache","path":"${LOCALAPPDATA}/deno","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${APPDATA}/Claude/logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Claude/Logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Local/Claude/Logs","age":7,"children":[]},{"category":"apps","path":"${HOME}/.claude/debug","age":7,"children":[]},{"category":"apps","path":"${HOME}/.claude/logs","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Claude/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Local/ChatGPT/Logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0/LocalCache/Roaming/ChatGPT/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${HOME}/.codex/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/codex-browser-app/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/component_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/extensions_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/GrShaderCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/ShaderCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/GPUPersistentCache/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Default/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${APPDATA}/Codex/logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Codex/Logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/Codex/Logs","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Codex/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Roaming/Codex/web/Codex/Crashpad/reports","age":7,"children":[]},{"category":"apps","path":"${HOME}/.copilot/logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Sublime Text/Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Termius/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Termius/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Termius/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Ledger Live/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Ledger Live/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Ledger Live/GPUCache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/node-gyp/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/electron-builder/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/electron/Cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/ffmpeg-static-nodejs/Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/CurseForge/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/CurseForge/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/CurseForge/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/CurseForge/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/G HUB/Cache/Cache_Data","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/G HUB/Code Cache","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/G HUB/GPUCache","age":7,"children":[]},{"category":"apps","path":"${PROGRAMDATA}/LGHUB/cache","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Zen/Profiles","age":0,"children":["cache2"]},{"category":"apps","path":"${APPDATA}/Kodi/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Kodi/userdata/Thumbnails","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/qBittorrent/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/HandBrake/logs","age":0,"children":[]},{"category":"apps","path":"${HOME}/AppData/LocalLow/Sun/Java/Deployment/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Windsurf/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Windsurf/CachedData","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Windsurf/CachedExtensions","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Windsurf/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Hyper/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Hyper/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Hyper/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Linear/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Linear/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Linear/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Todoist/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Todoist/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Todoist/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Loom/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Loom/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Loom/GPUCache","age":0,"children":[]},{"category":"developer-cache","path":"${HOME}/scoop/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/gcloud/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/gcloud/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/DriveFS/Logs","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/DriveFS/cef_cache/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/DriveFS/cef_cache/Code Cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/DriveFS/cef_cache/component_crx_cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Google/DriveFS/cef_cache/Shared Dictionary/cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/kudu/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/kudu/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/kudu/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/kudu/logs","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Browser","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/DawnCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Default/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/component_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/extensions_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/GraphiteDawnCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/GrShaderCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/ShaderCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/DashboardWidget/logs","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/DashboardWidget/Crashpad/reports","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Launcher/Logs","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalCache/Spotify/Launcher/Crashpad/reports","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/Code Cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/GPUCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/component_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/extensions_crx_cache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/GraphiteDawnCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/GrShaderCache","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/NVIDIA Corporation/NVIDIA app/CefCache/ShaderCache","age":1,"children":[]},{"category":"apps","path":"${PROGRAMDATA}/NVIDIA Corporation/NVIDIA app/Logs","age":1,"children":[]},{"category":"apps","path":"${PROGRAMDATA}/NVIDIA Corporation/Downloader","age":14,"children":[]},{"category":"apps","path":"${APPDATA}/Cursor/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${LOCALAPPDATA}/JetBrains","age":7,"children":["log"]},{"category":"apps","path":"${PROGRAMDATA}/EA Desktop/Logs","age":1,"children":[]},{"category":"apps","path":"${PROGRAMDATA}/Microsoft/EdgeUpdate/Log","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Mozilla/Firefox/Crash Reports/submitted","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Mozilla/Firefox/Crash Reports/events","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Mozilla/Firefox/Crash Reports/glean","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Mozilla/Firefox/Crash Reports/pending","age":30,"children":[]},{"category":"apps","path":"${PROGRAMDATA}/chocolatey/logs","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Bramblewatch/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/hearthglen/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/t3code/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/t3code/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/t3code-v2/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/t3code-v2/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/t3code/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"apps","path":"${APPDATA}/t3code-v2/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"shader-cache","path":"${APPDATA}/t3code/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"shader-cache","path":"${APPDATA}/t3code-v2/Partitions","age":1,"children":["Cache/Cache_Data","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Shared Dictionary/cache"]},{"category":"shader-cache","path":"${APPDATA}/t3code/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code/DawnWebGPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code-v2/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code-v2/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code-v2/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/t3code-v2/DawnWebGPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${LOCALAPPDATA}/Spark Desktop/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${LOCALAPPDATA}/Spark Desktop/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${LOCALAPPDATA}/Spark Desktop/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${LOCALAPPDATA}/Spark Desktop/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Pinokio/Cache/Cache_Data","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Pinokio/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Pinokio/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Pinokio/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Pinokio/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Granola/Cache/Cache_Data","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Granola/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Granola/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Granola/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/Granola/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/wsl-cleaner/Cache/Cache_Data","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/wsl-cleaner/Code Cache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/wsl-cleaner/GPUCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/wsl-cleaner/DawnGraphiteCache","age":1,"children":[]},{"category":"shader-cache","path":"${APPDATA}/wsl-cleaner/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${HOME}/.t3/userdata/logs","age":7,"children":[]},{"category":"apps","path":"${APPDATA}/Buzz/node-tools/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Upscayl/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Upscayl/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Upscayl/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Upscayl/DawnCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Upscayl/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ToDesktop Builder/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/git-project-updater/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/DawnGraphiteCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/DawnWebGPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/Shared Dictionary/cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Polyscope/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ShurePlus MOTIV/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ShurePlus MOTIV/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ShurePlus MOTIV/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/ShurePlus MOTIV/logs","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Termius Beta/Cache/Cache_Data","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Termius Beta/Code Cache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Termius Beta/GPUCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Termius Beta/DawnCache","age":1,"children":[]},{"category":"apps","path":"${APPDATA}/Termius Beta/Crashpad/reports","age":1,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Zed/node/cache","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Zed/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/CachedData","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/CachedExtensionVSIXs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/Code - Insiders/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/CachedData","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/CachedExtensionVSIXs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/VSCodium/logs","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordptb/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordptb/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordptb/GPUCache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordcanary/Cache/Cache_Data","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordcanary/Code Cache","age":0,"children":[]},{"category":"apps","path":"${APPDATA}/discordcanary/GPUCache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/Microsoft/TypeScript","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/Microsoft/vscode-cpptools/ipch","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/go-build","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/pypoetry/Cache/cache","age":0,"children":[]},{"category":"developer-cache","path":"${LOCALAPPDATA}/pypoetry/Cache/artifacts","age":0,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Packages/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe/LocalState/DiagOutputDir","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Microsoft/OneDrive/logs","age":7,"children":[]},{"category":"apps","path":"${LOCALAPPDATA}/Microsoft/OneDrive/setup/logs","age":7,"children":[]},{"category":"shader-cache","path":"${LOCALAPPDATA}/UnrealEngine/Common/DerivedDataCache","age":0,"children":[]},{"category":"games","path":"${PROGRAMFILES_X86}/Steam/logs","age":0,"children":[]},{"category":"games","path":"${PROGRAMFILES_X86}/Steam/dumps","age":0,"children":[]},{"category":"games","path":"${PROGRAMFILES_X86}/Steam/appcache/httpcache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Steam/htmlcache/Default/Cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Steam/htmlcache/Default/Code Cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Steam/htmlcache/Default/GPUCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Steam/htmlcache/GrShaderCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Steam/htmlcache/ShaderCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EpicGamesLauncher/Saved/webcache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EpicGamesLauncher/Saved/webcache_4430","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EpicGamesLauncher/Saved/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EpicGamesLauncher/Intermediate","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EpicGamesLauncher/Saved/webcache_4147","age":7,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Electronic Arts/EA Desktop/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Electronic Arts/EA Desktop/IGOCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/EADesktop/cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Origin/cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Ubisoft Game Launcher/cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Ubisoft Game Launcher/logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/GOG.com/Galaxy/webcache","age":0,"children":[]},{"category":"games","path":"${PROGRAMDATA}/GOG.com/Galaxy/logs","age":0,"children":[]},{"category":"games","path":"${PROGRAMDATA}/GOG.com/Galaxy/webcache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Battle.net/Cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Blizzard Entertainment/Battle.net/Logs","age":0,"children":[]},{"category":"games","path":"${APPDATA}/Battle.net/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Riot Games/Riot Client/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Packages/Microsoft.GamingApp_8wekyb3d8bbwe/LocalCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Packages/Microsoft.XboxApp_8wekyb3d8bbwe/LocalCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Rockstar Games/Launcher/cache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Rockstar Games/Launcher/logs","age":0,"children":[]},{"category":"games","path":"${APPDATA}/itch/Cache/Cache_Data","age":0,"children":[]},{"category":"games","path":"${APPDATA}/itch/logs","age":0,"children":[]},{"category":"games","path":"${APPDATA}/.minecraft/logs","age":0,"children":[]},{"category":"games","path":"${APPDATA}/.minecraft/crash-reports","age":0,"children":[]},{"category":"games","path":"${APPDATA}/.minecraft/webcache2","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Roblox/logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/VALORANT/Saved/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/VALORANT/Saved/Crashes","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/FortniteGame/Saved/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/FortniteGame/Saved/Crashes","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Amazon Games/Data/Logs","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Amazon Games/App/CEFCache","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Overwolf/Log","age":0,"children":[]},{"category":"games","path":"${LOCALAPPDATA}/Overwolf/BrowserCache","age":0,"children":[]},{"category":"shader-cache","path":"${PROGRAMFILES_X86}/Steam/steamapps/shadercache","age":0,"children":[]}]
""";
        var tokens = new Dictionary<string, string>(StringComparer.Ordinal) {
            ["${LOCALAPPDATA}"] = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            ["${APPDATA}"] = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            ["${PROGRAMDATA}"] = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            ["${HOME}"] = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ["${PROGRAMFILES_X86}"] = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            ["${PROGRAMFILES}"] = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
        };
        using var data = JsonDocument.Parse(metadata);
        foreach (var entry in data.RootElement.EnumerateArray())
        {
            string template = entry.GetProperty("path").GetString()!;
            var token = tokens.FirstOrDefault(pair => template.StartsWith(pair.Key + "/", StringComparison.Ordinal));
            if (string.IsNullOrEmpty(token.Value)) continue;
            string root = Path.Combine(token.Value, template[(token.Key.Length + 1)..].Replace('/', Path.DirectorySeparatorChar));
            string category = entry.GetProperty("category").GetString()!; int age = entry.GetProperty("age").GetInt32();
            if (category == "apps" && IsAiApplication(template)) category = "ai-tools";
            var children = entry.GetProperty("children").EnumerateArray().Select(child => child.GetString()!.Replace('/', Path.DirectorySeparatorChar)).ToArray();
            if (children.Length == 0) rules.Add(new(category, root, MinAgeDays: age));
            else foreach (string profile in Profiles(root, _ => true))
                foreach (string child in children) rules.Add(new(category, Path.Combine(profile, child), MinAgeDays: age));
        }
    }
    private static bool IsAiApplication(string template) => new[] { "/Cursor/", "/Claude/", "/ChatGPT/", "/Codex/", "/OpenAI.Codex_", "/Pinokio/", "/Granola/", "/t3code/", "/t3code-v2/", "/LM Studio/", "/Jan/", "/Ollama/", "/ComfyUI/", "/Spark Desktop/" }.Any(token => template.Contains(token, StringComparison.OrdinalIgnoreCase));
    private static bool IsBrokenShortcut(string path)
    {
        object? shell = null, shortcut = null;
        try
        {
            var type = Type.GetTypeFromProgID("WScript.Shell"); if (type == null) return false;
            shell = Activator.CreateInstance(type); if (shell == null) return false;
            shortcut = type.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { path });
            if (shortcut == null) return false;
            string target = Convert.ToString(shortcut.GetType().InvokeMember("TargetPath", System.Reflection.BindingFlags.GetProperty, null, shortcut, null)) ?? "";
            target = Environment.ExpandEnvironmentVariables(target.Trim('"'));
            if (string.IsNullOrWhiteSpace(target) || !Path.IsPathFullyQualified(target) || target.StartsWith(@"\\", StringComparison.Ordinal)) return false;
            string? root = Path.GetPathRoot(target);
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return false;
            return !File.Exists(target) && !Directory.Exists(target);
        }
        catch { return false; }
        finally
        {
            if (shortcut != null && Marshal.IsComObject(shortcut)) Marshal.FinalReleaseComObject(shortcut);
            if (shell != null && Marshal.IsComObject(shell)) Marshal.FinalReleaseComObject(shell);
        }
    }
    private static IEnumerable<string> Profiles(string parent, Func<string, bool> include)
    {
        try { if (!Directory.Exists(parent)) return Array.Empty<string>(); RefuseLinks(parent); return Directory.GetDirectories(parent).Where(include).Where(p => (File.GetAttributes(p) & FileAttributes.ReparsePoint) == 0).ToArray(); }
        catch (Exception ex) when (Handled(ex)) { return Array.Empty<string>(); }
    }
}
