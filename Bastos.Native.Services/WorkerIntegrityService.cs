using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class WorkerIntegrityException(string code, string message) : IOException(message)
{
    public string Code { get; } = code;
}
public sealed class WorkerIntegrityLease : IDisposable
{
    private readonly List<FileStream> files;
    internal WorkerIntegrityLease(List<FileStream> files) { this.files = files; }
    public int CheckedFiles => files.Count;
    public void Dispose() { foreach (var file in files) file.Dispose(); files.Clear(); }
}
public sealed class WorkerIntegrityService
{
    private readonly string root;
    private readonly (string Path, string Sha256)[] catalog;
    private static readonly Lazy<byte[]> embedded = new(() => {
        using var stream = typeof(WorkerIntegrityService).Assembly.GetManifestResourceStream("Bastos.EngineIntegrity.json") ??
            throw Failure("ENGINE_CATALOG_INVALID", "Le catalogue de contrôle embarqué est absent.");
        using var copy = new MemoryStream(); stream.CopyTo(copy); return copy.ToArray();
    });
    public WorkerIntegrityService(string root) : this(root, embedded.Value) { }
    // Explicit catalogue injection is internal and used only by isolated fixtures.
    internal WorkerIntegrityService(string root, byte[] trustedCatalog)
    {
        this.root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        try
        {
            if (trustedCatalog.Length > 256 * 1024) throw new InvalidDataException();
            using var document = JsonDocument.Parse(trustedCatalog);
            if (document.RootElement.GetProperty("Schema").GetInt32() != 1) throw new InvalidDataException();
            catalog = document.RootElement.GetProperty("Files").EnumerateArray().Select(entry =>
                (Path: entry.GetProperty("Path").GetString() ?? "", Sha256: entry.GetProperty("Sha256").GetString() ?? "")).ToArray();
            if (catalog.Length is < 1 or > 512 || catalog.Select(e => e.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count() != catalog.Length ||
                catalog.Any(e => !ValidRelative(e.Path) || e.Sha256.Length != 64 || !e.Sha256.All(Uri.IsHexDigit))) throw new InvalidDataException();
        }
        catch (Exception ex) when (ex is JsonException or InvalidDataException or KeyNotFoundException or InvalidOperationException or ArgumentException)
        { throw Failure("ENGINE_CATALOG_INVALID", "Le catalogue de contrôle embarqué est illisible."); }
    }
    private static bool ValidRelative(string value) => !string.IsNullOrWhiteSpace(value) && !Path.IsPathRooted(value) &&
        !value.Contains(':') && !value.Contains('/') && !value.Split('\\').Any(p => p is "" or "." or "..") &&
        new[] { ".ps1", ".psm1", ".psd1", ".cmd", ".bat" }.Contains(Path.GetExtension(value), StringComparer.OrdinalIgnoreCase);
    private static WorkerIntegrityException Failure(string code, string detail) => new(code, detail +
        " Remets les fichiers de la même version de Bastos ou réinstalle l’application, puis réessaie. Aucun script n’a été lancé.");
    public WorkerIntegrityLease Acquire(string scriptName)
    {
        if (Path.GetFileName(scriptName) != scriptName || !scriptName.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) ||
            !catalog.Any(e => e.Path.Equals(scriptName, StringComparison.OrdinalIgnoreCase)))
            throw Failure("ENGINE_FILE_UNLISTED", "Script non répertorié : " + Path.GetFileName(scriptName) + ".");
        var opened = new List<FileStream>();
        var checkedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string current = "";
        try
        {
            // The small complete engine set also covers dynamically selected imports,
            // child scripts and generated Recovery payloads, without a guessed graph.
            foreach (var entry in catalog)
            {
                current = entry.Path;
                string full = Path.GetFullPath(Path.Combine(root, entry.Path));
                if (!full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    throw Failure("ENGINE_FILE_UNLISTED", "Chemin de script non autorisé.");
                for (string? cursor = full; cursor != null && checkedPaths.Add(cursor); cursor = Path.GetDirectoryName(cursor))
                    if ((File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                        throw Failure("ENGINE_LINK_REFUSED", "Fichier ou dossier redirigé : " + current + ".");
                // FileShare.Read blocks replacement/deletion/writing while the worker
                // is followed; the files themselves are never copied or modified.
                var input = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.Read);
                opened.Add(input);
                if (input.Length > 16 * 1024 * 1024 || !Convert.ToHexString(SHA256.HashData(input)).Equals(entry.Sha256, StringComparison.OrdinalIgnoreCase))
                    throw Failure("ENGINE_FILE_CHANGED", "Fichier différent de la version attendue : " + current + ".");
            }
            return new(opened);
        }
        catch (Exception ex)
        {
            foreach (var input in opened) input.Dispose();
            if (ex is WorkerIntegrityException) throw;
            if (ex is FileNotFoundException or DirectoryNotFoundException)
                throw Failure("ENGINE_FILE_MISSING", "Fichier du moteur absent : " + current + ".");
            if (ex is IOException or UnauthorizedAccessException)
                throw Failure("ENGINE_FILE_UNREADABLE", "Lecture du fichier impossible ou fichier en cours de modification : " + current + ".");
            throw;
        }
    }
    public static async Task HoldUntilExitAsync(Process process, WorkerIntegrityLease lease)
    {
        try { await process.WaitForExitAsync(); }
        catch (Exception) { }
        finally { lease.Dispose(); process.Dispose(); }
    }
}
