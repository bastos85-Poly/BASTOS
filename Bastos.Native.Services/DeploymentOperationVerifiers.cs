using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record IsoBuildExpectation(string Source, string Output, string Locale, string Keyboard, string UserName,
    string SourceAppManifestSha256, string NativeAppSha256, string RemovalSelectionSha256, string RemovalOptionsSha256);

public static class DeploymentOperationVerifiers
{
    public static async Task<OperationVerification> AdkAsync(JsonElement report, Func<string?> readVersion,
        Func<string, string, int?> readPatchState, IReadOnlyList<string> candidates, string? patchArchivePath = null)
    {
        var checks = new List<OperationCheck>();
        string version = report.GetProperty("InstalledVersion").GetString() ?? "";
        string path = Path.GetFullPath(report.GetProperty("Oscdimg").GetString() ?? "");
        bool found = version == readVersion() && candidates.Any(candidate => Path.GetFullPath(candidate).Equals(path, StringComparison.OrdinalIgnoreCase)) && File.Exists(path);
        checks.Add(new("Outils réellement installés", found, "Version relue dans le registre et chemin Oscdimg attendu."));
        if (!found) return new(false, "ADK non confirmé : version ou outil installé différent du rapport.", checks);
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        string hash = Convert.ToHexString(await SHA256.HashDataAsync(file));
        bool signature = report.GetProperty("SignatureStatus").GetString() == "Valid" &&
            System.Text.RegularExpressions.Regex.IsMatch(report.GetProperty("SignerSubject").GetString() ?? "", @"(?:^|,\s*)O=Microsoft Corporation(?:,|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        bool integrity = file.Length > 2 && file.Length == report.GetProperty("OscdimgLength").GetInt64() && hash.Equals(report.GetProperty("OscdimgSha256").GetString(), StringComparison.OrdinalIgnoreCase);
        file.Position = 0; integrity &= file.ReadByte() == 'M' && file.ReadByte() == 'Z';
        checks.Add(new("Signature et intégrité Oscdimg", signature && integrity, hash));
        string profile = report.GetProperty("ReadinessProfile").GetString() ?? "";
        bool readiness = version == AdkInstallationService.CurrentRelease && profile == "CurrentRelease" &&
            report.GetProperty("PatchStatus").GetString() == "DifferentRelease" && report.GetProperty("PatchId").GetString() == "";
        if (version == AdkInstallationService.PatchedBase && profile == "PatchedBase" && report.GetProperty("PatchId").GetString() == "KB5101684" && report.GetProperty("PatchStatus").GetString() == "WindowsInstallerVerified")
        {
            var pairs = report.GetProperty("RequiredPatches");
            readiness = pairs.ValueKind == JsonValueKind.Array && pairs.GetArrayLength() > 0;
            foreach (var pair in pairs.EnumerateArray())
            {
                string patch = pair.GetProperty("PatchCode").GetString() ?? "", product = pair.GetProperty("ProductCode").GetString() ?? "";
                bool applied = Guid.TryParseExact(patch, "B", out _) && Guid.TryParseExact(product, "B", out _) && readPatchState(patch, product) is 1 or 2;
                checks.Add(new("Correctif relu dans Windows Installer", applied, patch + " / " + product));
                readiness &= applied;
            }
        }
        checks.Add(new("Révision et correctif applicables", readiness, "Une révision supérieure quelconque et un fichier .ok ne prouvent pas l’application d’un correctif."));
        bool restart = report.TryGetProperty("RestartRequired", out var pending) && pending.ValueKind == JsonValueKind.True;
        if (!signature || !integrity || !readiness || restart) return new(false, restart ? "Redémarre Windows pour terminer les outils ADK avant de créer l’ISO." : "ADK non confirmé : outil, révision ou correctif non vérifié. Consulte le journal.", checks);
        if (profile == "PatchedBase")
        {
            bool archiveVerified = false;
            if (patchArchivePath != null && File.Exists(patchArchivePath))
            {
                using var archive = new FileStream(patchArchivePath, FileMode.Open, FileAccess.Read, FileShare.Read);
                string archiveHash = Convert.ToHexString(await SHA256.HashDataAsync(archive));
                archiveVerified = archiveHash == AdkInstallationService.PatchArchiveSha256 && report.GetProperty("PatchArchiveSha256").GetString() == archiveHash;
            }
            checks.Add(new("Correctif de référence", archiveVerified, "Archive KB5101684 identifiée par son empreinte SHA-256, relue par C#."));
            if (!archiveVerified) return new(false, "Correctif ADK non confirmé : l’archive ne correspond pas à la référence validée. Retélécharge le correctif puis réessaie.", checks);
        }
        return new(true, version == AdkInstallationService.CurrentRelease ? "ADK 10.1.26100.9457 et Oscdimg vérifiés ; KB5101684 concerne la base 2024." : "ADK, Oscdimg et correctifs applicables confirmés par Windows Installer.", checks);
    }

    public static async Task<OperationVerification> IsoAsync(IsoBuildExpectation expected, JsonElement report)
    {
        var checks = new List<OperationCheck>();
        bool PathEquals(string name, string wanted) => Path.GetFullPath(report.GetProperty(name).GetString() ?? "").Equals(Path.GetFullPath(wanted), StringComparison.OrdinalIgnoreCase);
        bool paths = PathEquals("OutputIso", expected.Output) && PathEquals("SourceIso", expected.Source) && File.Exists(expected.Output) && !Path.GetFullPath(expected.Source).Equals(Path.GetFullPath(expected.Output), StringComparison.OrdinalIgnoreCase);
        checks.Add(new("ISO attendue", paths, expected.Output));
        if (!paths) return new(false, "ISO non confirmée : fichier absent ou différent du fichier attendu.", checks);
        using var file = new FileStream(expected.Output, FileMode.Open, FileAccess.Read, FileShare.Read);
        bool length = file.Length > 16 * 1024 * 1024 && file.Length == report.GetProperty("FileLength").GetInt64();
        bool udf = false;
        byte[] sector = new byte[2048];
        for (int index = 16; index < 32 && file.Length >= (index + 1) * 2048; index++)
        {
            file.Position = index * 2048;
            await file.ReadExactlyAsync(sector);
            string identifier = Encoding.ASCII.GetString(sector, 1, 5);
            udf |= identifier is "NSR02" or "NSR03";
        }
        file.Position = 0;
        string actual = Convert.ToHexString(await SHA256.HashDataAsync(file));
        checks.Add(new("Fichier et empreinte finale", length && actual.Equals(report.GetProperty("Sha256").GetString(), StringComparison.OrdinalIgnoreCase), actual));
        checks.Add(new("Structure du média UDF", udf, "Descripteur UDF relu dans le fichier final."));
        bool configuration = report.GetProperty("WindowsLocale").GetString() == expected.Locale && report.GetProperty("KeyboardLayout").GetString() == expected.Keyboard &&
            report.GetProperty("LocalUserName").GetString() == expected.UserName && report.GetProperty("SourceAppManifestSha256").GetString() == expected.SourceAppManifestSha256 &&
            report.GetProperty("NativeAppSha256").GetString() == expected.NativeAppSha256 &&
            System.Text.RegularExpressions.Regex.IsMatch(report.GetProperty("AppManifestSha256").GetString() ?? "", "^[A-Fa-f0-9]{64}$") &&
            report.GetProperty("RequestRemoveSelectionSha256").GetString() == expected.RemovalSelectionSha256 && report.GetProperty("RequestRemovalOptionsSha256").GetString() == expected.RemovalOptionsSha256;
        checks.Add(new("Profil demandé", configuration, "Langue, clavier, compte, application et sélections de nettoyage comparés à la demande."));
        bool contents = new[] { "MediaRemounted", "BootFilesVerified", "WindowsImageVerified", "EmbeddedFilesVerified" }.All(name => report.GetProperty(name).ValueKind == JsonValueKind.True) &&
            report.GetProperty("VerifiedAppFileCount").GetInt32() > 0 && report.GetProperty("WindowsImageCount").GetInt32() == 1 && report.GetProperty("WindowsImageArchitecture").GetInt32() == 9 &&
            System.Text.RegularExpressions.Regex.IsMatch(report.GetProperty("WindowsImageName").GetString() ?? "", @"\bWindows\s*11\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        checks.Add(new("Contrôles du contenu final", contents, "Média réouvert ; fichiers de démarrage, image Windows et manifeste embarqué contrôlés par le worker."));
        return checks.All(check => check.Passed) ? new(true, "ISO BASTOS créée : contenu relu, profil et empreinte finale vérifiés.", checks)
            : new(false, "ISO non confirmée : structure, contenu, profil ou intégrité incorrecte. Consulte le journal avant de l’utiliser.", checks);
    }
}
