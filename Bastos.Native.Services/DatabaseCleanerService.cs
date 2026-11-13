using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed record DatabaseCleanerEntry(string Id, string Application, string Path, long Size, long EstimatedWaste);
public sealed record DatabaseCleanerResult(int Optimized, int Skipped, long BytesRecovered, IReadOnlyList<string> Errors, IReadOnlyList<string> Backups);

/// <summary>Optimizes known SQLite databases only. Every database is revalidated, backed up through SQLite, then vacuumed.</summary>
public sealed class DatabaseCleanerService
{
    private sealed record Candidate(DatabaseCleanerEntry Entry, string Hash, DateTime ModifiedUtc);
    private readonly Dictionary<string, Candidate> current = new(StringComparer.Ordinal);
    private readonly string? fixtureRoot;
    public DatabaseCleanerService() { }
    internal DatabaseCleanerService(string fixtureRoot) { this.fixtureRoot = fixtureRoot; }
    private DateTime createdUtc;
    private static readonly string[] ChromiumFiles = { "History", "Cookies", "Network/Cookies", "Favicons", "Top Sites", "Web Data", "Shortcuts" };
    private static readonly string[] FirefoxFiles = { "places.sqlite", "cookies.sqlite", "favicons.sqlite", "formhistory.sqlite", "webappsstore.sqlite", "content-prefs.sqlite" };
    private sealed record Target(string Name, string Root, bool Profiles, string[] Files);

    public Task<IReadOnlyList<DatabaseCleanerEntry>> ScanAsync(CancellationToken token = default) => Task.Run<IReadOnlyList<DatabaseCleanerEntry>>(() =>
    {
        var found = new List<Candidate>();
        foreach (var target in fixtureRoot == null ? Targets() : new[] { new Target("Fixture", fixtureRoot, false, new[] { "sample.db" }) })
        {
            token.ThrowIfCancellationRequested();
            if (!Directory.Exists(target.Root) || HasRedirectedAncestor(target.Root)) continue;
            IEnumerable<string> profiles;
            try { profiles = target.Profiles ? Directory.GetDirectories(target.Root).Where(p => (Path.GetFileName(p).Equals("Default", StringComparison.OrdinalIgnoreCase) || Path.GetFileName(p).StartsWith("Profile ", StringComparison.OrdinalIgnoreCase) || target.Name is "Firefox" or "Thunderbird") && !HasRedirectedAncestor(p)).ToArray() : new[] { target.Root }; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }
            foreach (string profile in profiles)
                foreach (string relative in target.Files)
                {
                    token.ThrowIfCancellationRequested();
                    string path = Path.GetFullPath(Path.Combine(profile, relative.Replace('/', Path.DirectorySeparatorChar)));
                    if (!path.StartsWith(Path.GetFullPath(profile).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;
                    try
                    {
                        if (!File.Exists(path) || File.Exists(path + "-wal") || File.Exists(path + "-shm") || HasRedirectedAncestor(path)) continue;
                        var info = new FileInfo(path);
                        if (info.Length < 40960) continue;
                        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                        var header = new byte[16]; if (stream.Read(header, 0, 16) != 16 || Encoding.ASCII.GetString(header) != "SQLite format 3\0") continue;
                        stream.Position = 0; string hash = Convert.ToHexString(SHA256.HashData(stream));
                        info.Refresh(); if (info.Length != stream.Length || info.LastWriteTimeUtc > DateTime.UtcNow.AddMinutes(-60)) continue;
                        long estimate = Math.Max(4096, info.Length / 10);
                        var entry = new DatabaseCleanerEntry(Guid.NewGuid().ToString("N"), target.Name, path, info.Length, estimate);
                        found.Add(new(entry, hash, info.LastWriteTimeUtc));
                    }
                    catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
                }
        }
        lock (current)
        {
            current.Clear(); foreach (var item in found) current.Add(item.Entry.Id, item);
            createdUtc = DateTime.UtcNow;
        }
        return found.Select(c => c.Entry).ToArray();
    }, token);

    public Task<DatabaseCleanerResult> CleanAsync(IEnumerable<string> ids, string backupRoot, CancellationToken token = default) => Task.Run<DatabaseCleanerResult>(() =>
    {
        var selected = ids.Distinct(StringComparer.Ordinal).ToArray(); Candidate[] items;
        lock (current)
        {
            if (createdUtc == default || DateTime.UtcNow - createdUtc > TimeSpan.FromMinutes(30) || selected.Any(id => !current.ContainsKey(id))) throw new InvalidOperationException("Analyse absente ou expirée. Relance l’analyse.");
            items = selected.Select(id => current[id]).ToArray(); current.Clear(); createdUtc = default;
        }
        var errors = new List<string>(); var backups = new List<string>(); int optimized = 0, skipped = 0; long recovered = 0;
        foreach (var item in items)
        {
            if (token.IsCancellationRequested) { skipped += items.Length - optimized - skipped; break; }
            try
            {
                string path = item.Entry.Path;
                if (HasRedirectedAncestor(path) || File.Exists(path + "-wal") || File.Exists(path + "-shm")) throw new IOException("Base active ou chemin redirigé : conservée.");
                var info = new FileInfo(path);
                if (!info.Exists || info.Length != item.Entry.Size || info.LastWriteTimeUtc != item.ModifiedUtc) throw new IOException("Base modifiée depuis l’analyse.");
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(item.Hash, StringComparison.Ordinal)) throw new IOException("Contenu modifié depuis l’analyse.");
                token.ThrowIfCancellationRequested();
                Directory.CreateDirectory(backupRoot);
                string backup = Path.Combine(backupRoot, "sqlite-" + Guid.NewGuid().ToString("N") + ".db");
                Optimize(path, backup);
                backups.Add(backup); optimized++;
                recovered += Math.Max(0, item.Entry.Size - new FileInfo(path).Length);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or DllNotFoundException or EntryPointNotFoundException or InvalidOperationException)
            { skipped++; errors.Add(item.Entry.Path + " : " + e.Message); }
        }
        return new(optimized, skipped, recovered, errors.AsReadOnly(), backups.AsReadOnly());
    }, token);

    private static void Optimize(string path, string backup)
    {
        IntPtr source = IntPtr.Zero, copy = IntPtr.Zero, operation = IntPtr.Zero;
        try
        {
            int open = sqlite3_open_v2(Utf8(path), out source, 0x00000002 | 0x00010000, IntPtr.Zero);
            if (open != 0 || source == IntPtr.Zero) throw new IOException("Ouverture SQLite refusée.");
            sqlite3_busy_timeout(source, 2000);
            if (!QuickCheck(source)) throw new IOException("Contrôle d’intégrité SQLite échoué ; base conservée.");
            open = sqlite3_open_v2(Utf8(backup), out copy, 0x00000002 | 0x00000004 | 0x00010000, IntPtr.Zero);
            if (open != 0 || copy == IntPtr.Zero) throw new IOException("Sauvegarde SQLite impossible.");
            operation = sqlite3_backup_init(copy, Utf8("main"), source, Utf8("main"));
            if (operation == IntPtr.Zero) throw new IOException("Sauvegarde SQLite initiale impossible.");
            int step = sqlite3_backup_step(operation, -1); int finish = sqlite3_backup_finish(operation); operation = IntPtr.Zero;
            if (step != 101 || finish != 0) throw new IOException("Sauvegarde SQLite incomplète.");
            sqlite3_close(copy); copy = IntPtr.Zero;
            if (!File.Exists(backup) || new FileInfo(backup).Length == 0) throw new IOException("Sauvegarde SQLite vide.");
            if (sqlite3_exec(source, Utf8("VACUUM;"), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) throw new IOException("VACUUM refusé ; sauvegarde conservée : " + backup);
            if (!QuickCheck(source)) throw new IOException("Contrôle d’intégrité après optimisation échoué ; sauvegarde conservée : " + backup);
        }
        finally
        {
            if (operation != IntPtr.Zero) sqlite3_backup_finish(operation);
            if (copy != IntPtr.Zero) sqlite3_close(copy);
            if (source != IntPtr.Zero) sqlite3_close(source);
        }
    }
    private static bool QuickCheck(IntPtr db)
    {
        IntPtr statement = IntPtr.Zero;
        try
        {
            if (sqlite3_prepare_v2(db, Utf8("PRAGMA quick_check;"), -1, out statement, IntPtr.Zero) != 0 || statement == IntPtr.Zero) return false;
            if (sqlite3_step(statement) != 100) return false;
            return Marshal.PtrToStringUTF8(sqlite3_column_text(statement, 0)) == "ok";
        }
        finally { if (statement != IntPtr.Zero) sqlite3_finalize(statement); }
    }
    private static byte[] Utf8(string value) => Encoding.UTF8.GetBytes(value + "\0");
    private static bool HasRedirectedAncestor(string path)
    {
        try
        {
            for (string? p = path; p != null; p = Path.GetDirectoryName(p))
                if ((File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0) return true;
        }
        catch { return true; }
        return false;
    }
    private static IEnumerable<Target> Targets()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        foreach (var (name, root) in new[] { ("Chrome", "Google/Chrome/User Data"), ("Edge", "Microsoft/Edge/User Data"), ("Brave", "BraveSoftware/Brave-Browser/User Data"), ("Vivaldi", "Vivaldi/User Data"), ("Chromium", "Chromium/User Data"), ("Arc", "Arc/User Data") })
            yield return new(name, Path.Combine(local, root.Replace('/', Path.DirectorySeparatorChar)), true, ChromiumFiles);
        foreach (var (name, root) in new[] { ("Opera", "Opera Software/Opera Stable"), ("Opera GX", "Opera Software/Opera GX Stable") })
            yield return new(name, Path.Combine(roaming, root.Replace('/', Path.DirectorySeparatorChar)), false, ChromiumFiles);
        yield return new("Firefox", Path.Combine(roaming, "Mozilla", "Firefox", "Profiles"), true, FirefoxFiles);
        yield return new("Thunderbird", Path.Combine(roaming, "Thunderbird", "Profiles"), true, new[] { "global-messages-db.sqlite", "places.sqlite", "cookies.sqlite" });
        foreach (var (name, root) in new[] { ("Discord", "discord"), ("Slack", "Slack"), ("Teams", "Microsoft/Teams"), ("VS Code", "Code"), ("Cursor", "Cursor"), ("Figma", "Figma"), ("Postman", "Postman") })
            yield return new(name, Path.Combine(roaming, root.Replace('/', Path.DirectorySeparatorChar)), false, new[] { "Network/Cookies", "User/globalStorage/state.vscdb" });
    }
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_busy_timeout(IntPtr db, int milliseconds);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr sqlite3_backup_init(IntPtr destination, byte[] destinationName, IntPtr source, byte[] sourceName);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_backup_step(IntPtr operation, int pages);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_backup_finish(IntPtr operation);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr callback, IntPtr userData, IntPtr error);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int length, out IntPtr statement, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_step(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr sqlite3_column_text(IntPtr statement, int index);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int sqlite3_finalize(IntPtr statement);
}

