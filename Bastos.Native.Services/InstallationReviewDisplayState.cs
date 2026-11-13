using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace Bastos.Native.Services;

// This records presentation only; it is never evidence that Windows passed verification.
public sealed class InstallationReviewDisplayState(string stateRoot, string profilePath, Func<string>? installationIdentity = null)
{
    private string? MarkerPath()
    {
        if (!File.Exists(profilePath)) return null;
        var info = new FileInfo(profilePath);
        if (info.Length > 1024 * 1024) throw new InvalidDataException("Profil d’installation trop volumineux.");
        string identity = (installationIdentity ?? ReadInstallationIdentity)();
        if (string.IsNullOrWhiteSpace(identity)) throw new InvalidDataException("Identité de Windows indisponible.");
        string profileHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(profilePath)));
        string key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity + "\n" + profileHash)));
        return Path.Combine(stateRoot, "InstallationReviews", key + ".shown");
    }

    public bool ShouldShow() => MarkerPath() is { } path && (!File.Exists(path) || File.ReadAllText(path) != "Shown-v1");

    // Capture the key before showing the window, so a changed profile is not marked as viewed.
    public Action PrepareMarkShown()
    {
        string? path = MarkerPath();
        return () =>
        {
            if (path == null) return;
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    stream.Write(Encoding.UTF8.GetBytes("Shown-v1"));
                    stream.Flush(true);
                }
                File.Move(temporary, path, true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        };
    }

    private static string ReadInstallationIdentity()
    {
        using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
        return key?.GetValue("MachineGuid") as string ?? "";
    }
}
