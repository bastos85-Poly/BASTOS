using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace Bastos.Native.Services;

public sealed class SoftwareFavoritesService
{
    private readonly string path;
    private readonly string? recoveryPath;
    private readonly JsonSerializerOptions options = new() { WriteIndented = true };

    public string Path => path;

    public SoftwareFavoritesService(AppPaths paths)
    {
        path = System.IO.Path.Combine(paths.DataRoot, "Software-Favorites.json");
        recoveryPath = FindRecoveryPath();
    }

    public HashSet<string> Load()
    {
        HashSet<string>? local = TryLoad(path);
        if (local != null)
        {
            TrySaveRecovery(local);
            return local;
        }

        HashSet<string>? recovered = recoveryPath == null ? null : TryLoad(recoveryPath);
        if (recovered != null)
        {
            SaveDocument(path, recovered);
            return recovered;
        }

        return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    }

    public void Save(IEnumerable<string> ids)
    {
        string[] normalized = ids.Where(IsValidId).Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
        SaveDocument(path, normalized);
        TrySaveRecovery(normalized);
    }

    private HashSet<string>? TryLoad(string sourcePath)
    {
        try
        {
            if (!File.Exists(sourcePath)) return null;
            var saved = JsonSerializer.Deserialize<FavoriteDocument>(File.ReadAllText(sourcePath));
            if (saved is not { Version: 1 }) return null;
            return new HashSet<string>((saved.Ids ?? Array.Empty<string>()).Where(IsValidId), StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            // Un fichier de préférences endommagé ne doit pas bloquer le catalogue.
            return null;
        }
    }

    private void TrySaveRecovery(IEnumerable<string> ids)
    {
        if (recoveryPath == null) return;
        try { SaveDocument(recoveryPath, ids); } catch { }
    }

    private void SaveDocument(string destinationPath, IEnumerable<string> ids)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destinationPath)!);
        string[] normalized = ids.Where(IsValidId).Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
        string temporary = destinationPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(new FavoriteDocument(1, normalized), options), new UTF8Encoding(false));
            File.Move(temporary, destinationPath, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private static string? FindRecoveryPath()
    {
        try
        {
            DriveInfo? recovery = DriveInfo.GetDrives().FirstOrDefault(drive =>
                drive.IsReady && drive.VolumeLabel.Equals("BASTOS_RECOVERY", StringComparison.OrdinalIgnoreCase));
            return recovery == null ? null : System.IO.Path.Combine(recovery.RootDirectory.FullName, "BASTOS-USER-DATA", "Software-Favorites.json");
        }
        catch { return null; }
    }

    private static bool IsValidId(string? value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 160;

    private sealed record FavoriteDocument(int Version, string[]? Ids);
}
