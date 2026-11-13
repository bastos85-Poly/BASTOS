using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Xml;
using System.Xml.Linq;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record RecoveryExpectation(string SourceIso, string Mode, string? Root = null,
    string Snapshot = "", string WindowsDiskIdentity = "", string RecoveryGuid = "",
    int ImageIndex = 0, string EditionId = "", string UserName = "", string ComputerName = "", string Keyboard = "", string UiLanguage = "", bool PreserveDrivers = false, string CleanupProfile = "");

public static class RecoveryOperationVerifiers
{
    public const string BootSequenceCheck = "Démarrage unique relu dans Windows";
    public const string BootAuthorizationCheck = "Autorisation de cette tentative";
    public static bool CanRestart(OperationResult result) => result.State == OperationState.Succeeded && result.ProcessStopped && !result.ActionCompletionUnconfirmed && result.Checks is { Count: > 0 } &&
        result.Checks.All(c => c.Passed) && result.Checks.Any(c => c.Name == BootSequenceCheck) && result.Checks.Any(c => c.Name == BootAuthorizationCheck);
    public static async Task<OperationVerification> VerifyAsync(RecoveryExpectation expected, JsonElement report, JsonElement probe, bool boot)
    {
        var checks = new List<OperationCheck>();
        bool Check(string name, bool passed, string detail) { checks.Add(new(name, passed, detail)); return passed; }
        OperationVerification Invalid(string message) => new(false, message, checks);
        try
        {
            string id = Text(report, "OperationId");
            bool envelope = Guid.TryParseExact(id, "N", out _) && Text(report, "Action") == (boot ? "BootOnce" : "Provision") &&
                Number(probe, "SchemaVersion") == 1 && Text(probe, "OperationId") == id && Text(probe, "Action") == "InspectResult" && Flag(probe, "Success");
            if (!Check("Relecture liée à l’opération", envelope, "Une seconde lecture du stockage, distincte du rapport d’exécution."))
                return Invalid("Recovery non confirmée : la relecture ne correspond pas à l’opération.");
            string root = Path.GetFullPath(Text(probe, "Root"));
            if (!Check("Volume attendu", expected.Root == null || SamePath(root, expected.Root), root))
                return Invalid("Recovery non confirmée : le volume relu est différent de la cible attendue.");
            using var selection = ReadJson(SafeFile(root, "BASTOS-RECOVERY-SELECTION.json"));
            using var media = ReadJson(SafeFile(root, "BASTOS-MEDIA-STATE.json"));
            var selected = selection.RootElement; var prepared = media.RootElement;
            string snapshotText = Text(probe, "StorageSnapshot");
            using var snapshot = JsonDocument.Parse(snapshotText);
            var disks = snapshot.RootElement.GetProperty("Disks");
            bool plan = Number(selected, "Schema") == 3 && Number(snapshot.RootElement, "Schema") == 1 &&
                Text(selected, "PostInstallMode") == expected.Mode && Text(prepared, "PostInstallMode") == expected.Mode &&
                SameGuid(Text(selected, "CurrentWindowsDiskIdentity"), Text(disks.GetProperty("WindowsDisk"), "Guid")) &&
                SameGuid(Text(selected, "WindowsTargetDiskIdentity"), Text(disks.GetProperty("InstallDisk"), "Guid")) &&
                SameGuid(Text(selected, "RecoveryDiskIdentity"), Text(disks.GetProperty("TargetDisk"), "Guid")) &&
                SameGuid(Text(selected, "RecoveryPartitionGuid"), Text(probe, "RecoveryPartitionGuid")) &&
                (expected.Snapshot.Length == 0 || JsonNode.DeepEquals(JsonNode.Parse(expected.Snapshot), JsonNode.Parse(snapshotText))) &&
                (expected.WindowsDiskIdentity.Length == 0 || SameGuid(expected.WindowsDiskIdentity, Text(selected, "WindowsTargetDiskIdentity"))) &&
                (expected.RecoveryGuid.Length == 0 || SameGuid(expected.RecoveryGuid, Text(selected, "RecoveryPartitionGuid"))) &&
                (boot || Text(selected, "OperationId") == id);
            if (!Check("Disques et plan relus", plan, "Identités GPT et plan enregistré comparés au stockage actuel."))
                return Invalid("Recovery non confirmée : le disque, les partitions ou le profil ont changé.");
            bool cacheSchema = Number(prepared, "Schema") == 8 || Number(prepared, "Schema") == 9 &&
                Number(prepared, "WindowsCacheRevision") == 1 && Number(prepared, "BootCacheRevision") == 1;
            bool image = cacheSchema && Flag(prepared, "InstallWimSanitized") &&
                Text(prepared, "CleanupProfile") == expected.CleanupProfile &&
                SamePath(Text(prepared, "IsoPath"), expected.SourceIso) &&
                (expected.ImageIndex <= 0 || Number(prepared, "ProImageIndex") == expected.ImageIndex) &&
                (expected.EditionId.Length == 0 || Text(prepared, "WindowsEditionId") == expected.EditionId);
            string sourceHash = await Hash(expected.SourceIso);
            image &= sourceHash.Equals(Text(prepared, "IsoSha256"), StringComparison.OrdinalIgnoreCase) &&
                sourceHash.Equals(ReadText(SafeFile(root, "BASTOS-ISO.sha256")).Trim(), StringComparison.OrdinalIgnoreCase) &&
                (boot || sourceHash.Equals(Text(report, "IsoSha256"), StringComparison.OrdinalIgnoreCase));
            if (!Check("ISO et édition attendues", image, "Empreinte SHA-256 de l’ISO source relue par C#."))
                return Invalid("Recovery non confirmée : l’ISO source ou l’édition préparée ne correspond plus au choix validé.");
            if(expected.CleanupProfile == "minimal-2")
            {
                using var cleanup = ReadJson(SafeFile(root,"BASTOS-Minimal-Offline.json"));
                var proof = cleanup.RootElement;
                bool clean = Number(proof,"Schema") == 1 && Text(proof,"Profile") == "minimal-2" &&
                    proof.GetProperty("RemainingTargets").ValueKind == JsonValueKind.Array && proof.GetProperty("RemainingTargets").GetArrayLength() == 0;
                if(!Check("Nettoyage hors ligne",clean,"Rapport de retrait des applications ciblées présent ; image vérifiée par empreinte."))
                    return Invalid("Nettoyage de l’image non confirmé. Prépare de nouveau Recovery.");
            }
            foreach (var pair in new[] { ("sources/boot.wim", "BootWimSha256"), ("sources/install.wim", "InstallWimSha256") })
            {
                string file = SafeFile(root, pair.Item1);
                using var input = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
                byte[] magic = new byte[5]; int read = await input.ReadAsync(magic);
                bool valid = input.Length > 8 && read == 5 && Encoding.ASCII.GetString(magic) == "MSWIM" &&
                    (await Hash(file)).Equals(Text(prepared, pair.Item2), StringComparison.OrdinalIgnoreCase);
                if (!Check("Intégrité " + pair.Item1, valid, "Contenu WIM et empreinte SHA-256 relus."))
                    return Invalid("Recovery non confirmée : une image Windows est absente, incomplète ou modifiée.");
            }
            if (!Check("Sauvegarde des pilotes", await VerifyDriverBackupAsync(root, expected.PreserveDrivers),
                expected.PreserveDrivers ? "Choix actif, inventaire et empreintes des paquets relus ; Windows sélectionnera les pilotes applicables." : "Transmission des anciens pilotes désactivée pour cette installation."))
                return Invalid("Recovery non confirmée : le choix des pilotes ou leur sauvegarde n’est pas vérifié.");
            string answerFile = SafeFile(root, "BASTOS-Recovery-Unattend.xml");
            using var reader = XmlReader.Create(answerFile, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 4 * 1024 * 1024 });
            var answer = XDocument.Load(reader);
            // The generator associates the selected physical layout with the
            // Windows UI language, avoiding a second preferred app language.
            // Apply the same association to live and persisted expectations.
            string inputLocale = ExpectedInputLocale(expected.Keyboard, expected.UiLanguage);
            bool Has(string name, string value) { var nodes = answer.Descendants().Where(e => e.Name.LocalName == name).ToArray(); return value.Length == 0 || nodes.Length > 0 && nodes.All(e => string.Equals(e.Value, value, StringComparison.OrdinalIgnoreCase)); }
            bool accountProfile = await VerifyPreparedAccountAsync(root, answer, expected, inputLocale);
            bool profile = answer.Root?.Name.LocalName == "unattend" && !answer.ToString().Contains("__BASTOS_") &&
                Has("ComputerName", expected.ComputerName) && Has("InputLocale", inputLocale) && Has("UILanguage", expected.UiLanguage) &&
                accountProfile;
            if (!Check("Profil d’installation", profile, "XML relu sans résolution externe ; provisionnement du compte " + (accountProfile ? "conforme" : "non conforme") + ", PC et clavier contrôlés. Clavier attendu : " + inputLocale + "; langue Windows : " + expected.UiLanguage + "."))
                return Invalid("Recovery non confirmée : le profil d’installation est différent des options enregistrées.");
            string bootId = ReadText(SafeFile(root, "BASTOS-BOOT-ID.txt")).Trim();
            if (!Check("Identifiant de démarrage", SameGuid(bootId, Text(report, "BootId")) && SameGuid(bootId, Text(probe, "BootId")), bootId))
                return Invalid("Recovery non confirmée : l’identifiant de démarrage a changé.");
            if (boot)
            {
                string attempt = ReadText(SafeFile(root, "BASTOS-ACTIVE-ATTEMPT.txt")).Trim();
                bool attemptValid = attempt.StartsWith("Attempt-", StringComparison.Ordinal) && Guid.TryParseExact(attempt[8..], "N", out _);
                if (!attemptValid) return Invalid("Démarrage non confirmé : tentative invalide.");
                using var state = ReadJson(SafeFile(root, $"BASTOS-Diagnostics/Attempts/{attempt}/State.json"));
                bool authorization = Text(state.RootElement, "OperationId") == id && Text(state.RootElement, "AttemptId") == attempt && Text(report, "AttemptId") == attempt &&
                    ReadText(SafeFile(root, "BASTOS-BOOT-MODE.txt")).Trim() == "BOOTONCE|" + attempt &&
                    !string.IsNullOrWhiteSpace(ReadText(SafeFile(root, "BASTOS-AUTO-REINSTALL.token"))) &&
                    !File.Exists(Path.Combine(root, "BASTOS-DIAGNOSTIC-ONLY.token"));
                if (!Check(BootAuthorizationCheck, authorization, attempt)) return Invalid("Démarrage non confirmé : autorisation absente ou appartenant à une autre opération.");
                var ids = probe.GetProperty("BootSequenceIds"); string entry = Text(probe, "BootEntry");
                bool bcd = ids.ValueKind == JsonValueKind.Array && ids.GetArrayLength() == 1 && SameGuid(ids[0].GetString() ?? "", bootId) &&
                    entry.Contains(bootId, StringComparison.OrdinalIgnoreCase) && entry.Contains("sources\\boot.wim", StringComparison.OrdinalIgnoreCase) && entry.Contains("windows\\system32\\boot\\winload.efi", StringComparison.OrdinalIgnoreCase);
                if (!Check(BootSequenceCheck, bcd, "Élément BootSequence du fournisseur BCD, sans dépendre de la langue de Windows."))
                    return Invalid("Démarrage non confirmé : Windows ne programme pas exactement l’entrée Recovery attendue.");
            }
            return new(true, boot ? "Démarrage Recovery programmé et vérifié. La réinstallation n’a pas encore été exécutée." : "BASTOS_RECOVERY préparée : ISO, images Windows, profil et disque vérifiés.", checks);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or XmlException or ArgumentException or InvalidOperationException or KeyNotFoundException)
        { checks.Add(new("Lecture des preuves", false, error.Message)); return Invalid("Résultat Recovery non confirmé : les preuves ne peuvent pas être relues. Consulte le Journal avant de continuer."); }
    }

    private static async Task<bool> VerifyPreparedAccountAsync(string root, XDocument answer, RecoveryExpectation expected, string inputLocale)
    {
        if (expected.UserName.Length == 0) return true;
        var accounts = answer.Descendants().Where(e => e.Name.LocalName == "LocalAccount").ToArray();
        const string payload = "sources/$OEM$/$1/ProgramData/BASTOS-ISO/";
        string relative = payload + "Installation-Expected.json";
        bool LegacyAccount() => accounts.Length == 1 && accounts[0].Elements().Any(n => n.Name.LocalName == "Name" && n.Value == expected.UserName);
        // Existing media used OOBE LocalAccounts. New media explicitly selects
        // the single specialize writer; never demand a second OOBE writer.
        if (!File.Exists(Path.Combine(root, relative))) return LegacyAccount();
        using var document = ReadJson(SafeFile(root, relative));
        var profile = document.RootElement;
        string flow = Text(profile, "AccountProvisioning");
        if (flow.Length == 0) return LegacyAccount();
        if (flow != "SpecializePasswordlessV1" || Number(profile, "Schema") != 2 || accounts.Length != 0 ||
            Text(profile, "PasswordMode") != "Empty" || Text(profile, "UserName") != expected.UserName ||
            Text(profile, "ComputerName") != expected.ComputerName || Text(profile, "UILanguage") != expected.UiLanguage ||
            Text(profile, "KeyboardLayout") != inputLocale || Text(profile, "EditionId") != expected.EditionId ||
            !profile.TryGetProperty("AutoLogonEnabled", out var autoEnabled) ||
            autoEnabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        string hash = Text(profile, "AccountWorkerSha256");
        if (hash.Length != 64 || !hash.All(Uri.IsHexDigit) ||
            !string.Equals(await Hash(SafeFile(root, payload + "Initialize-BASTOS-LocalAccount.ps1")), hash, StringComparison.OrdinalIgnoreCase)) return false;
        XNamespace ns = "urn:schemas-microsoft-com:unattend";
        const string command = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%ProgramData%\\BASTOS-ISO\\Initialize-BASTOS-LocalAccount.ps1\"";
        var commands = answer.Descendants(ns + "RunSynchronousCommand").Where(e =>
            ((string?)e.Element(ns + "Path") ?? "").Contains("Initialize-BASTOS-LocalAccount.ps1", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (commands.Length != 1 || !string.Equals((string?)commands[0].Element(ns + "Path"), command, StringComparison.OrdinalIgnoreCase) ||
            (string?)commands[0].Element(ns + "WillReboot") != "Never" ||
            !commands[0].Ancestors(ns + "settings").Any(e => (string?)e.Attribute("pass") == "specialize") ||
            !commands[0].Ancestors(ns + "component").Any(e => (string?)e.Attribute("name") == "Microsoft-Windows-Deployment" &&
                (string?)e.Attribute("processorArchitecture") == "amd64")) return false;
        var auto = answer.Descendants(ns + "AutoLogon").ToArray();
        if (!autoEnabled.GetBoolean()) return auto.Length == 0;
        return auto.Length == 1 && (string?)auto[0].Element(ns + "Username") == expected.UserName &&
            (string?)auto[0].Element(ns + "Domain") == expected.ComputerName &&
            string.Equals((string?)auto[0].Element(ns + "Enabled"), "true", StringComparison.OrdinalIgnoreCase) &&
            auto[0].Element(ns + "Password")?.Element(ns + "Value") is { Value.Length: 0 } &&
            string.Equals((string?)auto[0].Element(ns + "Password")?.Element(ns + "PlainText"), "true", StringComparison.OrdinalIgnoreCase);
    }

    private static string ExpectedInputLocale(string keyboard, string uiLanguage)
    {
        if (keyboard.Length == 0) return "";
        if (keyboard.Length != 13 || keyboard[4] != ':' ||
            !keyboard.Where((_, index) => index != 4).All(Uri.IsHexDigit))
            throw new ArgumentException("Disposition de clavier attendue invalide.");
        if (uiLanguage.Length == 0) return keyboard;
        int languageId = CultureInfo.GetCultureInfo(uiLanguage).KeyboardLayoutId;
        if (languageId <= 0 || languageId == 0x1000)
            throw new ArgumentException("Association langue/clavier non prise en charge.");
        return languageId.ToString("X4", CultureInfo.InvariantCulture) + ":" + keyboard.Substring(5);
    }

    public static async Task<bool> VerifyDriverBackupAsync(string root, bool selected)
    {
        string selection = Path.Combine(root, "BASTOS-DRIVERS.enabled");
        if (!File.Exists(selection)) return !selected;
        if (ReadText(SafeFile(root, "BASTOS-DRIVERS.enabled")).Trim() != (selected ? "1" : "0")) return false;
        if (!selected) return true;
        string directory = Path.Combine(root, "BASTOS-Drivers", "Active");
        using var document = ReadJson(SafeFile(root, "BASTOS-Drivers/Active/Manifest.json"), 16 * 1024 * 1024);
        var manifest = document.RootElement;
        if (Number(manifest, "Schema") != 1 || Text(manifest, "Architecture") != "AMD64" ||
            !string.Equals(Text(manifest, "SourceComputer"), Environment.MachineName, StringComparison.OrdinalIgnoreCase)) return false;
        string packages = Path.Combine(directory, "Packages");
        var actual = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Stack<string>(); pending.Push(packages);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0) return false;
            foreach (string item in Directory.EnumerateFileSystemEntries(folder))
            {
                var attributes = File.GetAttributes(item);
                if ((attributes & FileAttributes.ReparsePoint) != 0) return false;
                if ((attributes & FileAttributes.Directory) != 0) pending.Push(item);
                else actual.Add(Path.GetRelativePath(packages, item));
            }
        }
        long bytes = 0; int infCount = 0;
        foreach (var entry in manifest.GetProperty("Files").EnumerateArray())
        {
            string relative = Text(entry, "Path");
            if (!actual.Remove(relative)) return false;
            string file = SafeFile(packages, relative);
            long length = new FileInfo(file).Length;
            if (length != entry.GetProperty("Bytes").GetInt64() || !string.Equals(await Hash(file), Text(entry, "Sha256"), StringComparison.OrdinalIgnoreCase)) return false;
            bytes += length;
            if (Path.GetExtension(file).Equals(".inf", StringComparison.OrdinalIgnoreCase)) infCount++;
        }
        return actual.Count == 0 && bytes == manifest.GetProperty("TotalBytes").GetInt64() && infCount == Number(manifest, "InfCount");
    }
    private static string Text(JsonElement data, string key) => data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    private static int Number(JsonElement data, string key) => data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number) ? number : -1;
    private static bool Flag(JsonElement data, string key) => data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.True;
    private static bool SameGuid(string a, string b) => Guid.TryParse(a, out var x) && x != Guid.Empty && Guid.TryParse(b, out var y) && x == y;
    private static bool SamePath(string a, string b) => Path.GetFullPath(a).TrimEnd('\\', '/').Equals(Path.GetFullPath(b).TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase);
    private static JsonDocument ReadJson(string path, int maximumBytes = 4 * 1024 * 1024)
    {
        if (new FileInfo(path).Length > maximumBytes) throw new IOException("Rapport trop volumineux.");
        return JsonDocument.Parse(File.ReadAllText(path));
    }
    private static string ReadText(string path)
    {
        if (new FileInfo(path).Length > 1024 * 1024) throw new IOException("Preuve texte trop volumineuse.");
        return File.ReadAllText(path);
    }
    private static string SafeFile(string root, string relative)
    {
        string current = Path.GetFullPath(root);
        foreach (string component in relative.Replace('\\', '/').Split('/'))
        {
            if (component is ".." or "." || Path.IsPathRooted(component)) throw new IOException("Chemin de preuve invalide.");
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new IOException("Dossier de preuve redirigé.");
            current = Path.Combine(current, component);
        }
        if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new IOException("Preuve redirigée.");
        return current;
    }
    private static async Task<string> Hash(string path)
    {
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexString(await SHA256.HashDataAsync(input));
    }
}
