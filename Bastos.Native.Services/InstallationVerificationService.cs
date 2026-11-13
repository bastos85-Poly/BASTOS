using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed record InstallationCheck(string Id, string Name, string Expected, string Actual, string Status, string Detail)
{
    public string Label => Status switch { "Passed" => "Conforme", "NotRequested" => "Non demandé", "Mismatch" => "Écart constaté", _ => "Non vérifié" };
    public string Color => Status == "Passed" ? "#38D9A9" : Status == "NotRequested" ? "#AAB8CE" : "#FFB84D";
    public string Comparison => $"Demandé : {Display(Expected)}\nConstaté : {Display(Actual)}";
    private static string Display(string value) => value switch { "Configured" => "Configuration enregistrée et vérifiée", "Applied" => "Appliqué et vérifié", "NotApplied" => "Non conforme", "Unknown" => "Non confirmé", "NotRequested" => "Option décochée", "Professional" => "Windows Pro", "Core" => "Windows Famille", "EnterpriseS" => "Windows Entreprise LTSC", "IoTEnterpriseS" => "Windows IoT Entreprise LTSC", "Verified" => "Raccourci et cible vérifiés", "Completed" => "Terminée", "" => "Indisponible", _ => value };
}
public sealed record InstallationReview(DateTime CheckedUtc, IReadOnlyList<InstallationCheck> Checks, string ReportPath)
{
    public bool Passed => Checks.Count == 16 && Checks.All(c => c.Status is "Passed" or "NotRequested");
    public string Summary => Passed ? $"Installation vérifiée : les {Checks.Count(c => c.Status == "Passed")} contrôles demandés sont conformes." :
        $"Bilan à vérifier : {Count("Passed", "conforme")}, {Count("Mismatch", "écart")}, {Count("Unavailable", "non vérifié")}.";
    private string Count(string status, string label) { int count = Checks.Count(c => c.Status == status); return $"{count} {label}{(count > 1 ? "s" : "")}"; }
}

public sealed class InstallationVerificationService(AppPaths paths)
{
    public static string ProfilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BASTOS-ISO", "Installation-Expected.json");
    public bool HasProfile => File.Exists(ProfilePath);
    private static readonly string[] ids = { "edition", "language", "region", "keyboard", "computer", "account", "shortcut", "finalization" };
    private static readonly string[] names = { "Édition de Windows", "Langue de Windows", "Format régional", "Clavier principal", "Nom du PC", "Compte local actif", "Raccourci Bastos sur le Bureau", "Finalisation du premier démarrage" };
    private static readonly string[] extraIds = { "preferredlanguage", "privacy", "suggestions", "onedrive", "teams", "outlook", "copilot", "widgets" };
    private static readonly string[] extraNames = { "Langue des applications", "Collecte facultative et confidentialité", "Suggestions et QoL demandées", "Suppression de OneDrive", "Suppression de Teams", "Suppression du nouvel Outlook", "Suppression de Copilot", "Widgets et météo" };
    private static readonly string[] optionNames = { "DisableTelemetry", "DisableConsumerContent", "RemoveOneDrive", "RemoveTeams", "RemoveOutlook", "DisableCopilot", "DisableWidgets" };

    public async Task<InstallationReview> CheckAsync()
    {
        byte[] profile = ReadBounded(ProfilePath);
        string hash = Convert.ToHexString(SHA256.HashData(profile));
        using var document = JsonDocument.Parse(profile);
        string profileId = document.RootElement.GetProperty("ProfileId").GetString() ?? "";
        int schema = document.RootElement.GetProperty("Schema").GetInt32();
        if (schema is not (1 or 2) || !Guid.TryParse(profileId, out _)) throw new InvalidDataException("Profil d’installation inconnu. Reprépare le média avec la version actuelle de Bastos.");
        string directory = Path.Combine(paths.LogRoot, "Operations");
        Directory.CreateDirectory(directory);
        string id = Guid.NewGuid().ToString("N");
        string reportPath = Path.Combine(directory, id + ".worker.json");
        string journalPath = Path.Combine(directory, id + ".operation.json");
        DateTime started = DateTime.UtcNow;
        InstallationReview? review = null;
        string error = "";
        string errorCode = "INSTALLATION_REVIEW_REQUIRED";
        try
        {
            string script = paths.Script("Test-BASTOS-InstalledWindows.ps1");
            using var integrity = await Task.Run(() => new WorkerIntegrityService(paths.Root).Acquire("Test-BASTOS-InstalledWindows.ps1"));
            var result = await new ProcessExecutionService().RunAsync(
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
                new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-ProfilePath", ProfilePath, "-ResultPath", reportPath, "-RequestId", id, "-ExpectedUserSid", System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value },
                elevate: schema == 2, timeoutOverride: TimeSpan.FromSeconds(180), terminateOnTimeout: false);
            if (!result.Success) throw new InvalidDataException("Le contrôle n’a pas abouti. " + result.Error);
            if (!SHA256.HashData(ReadBounded(ProfilePath)).SequenceEqual(SHA256.HashData(profile))) throw new InvalidDataException("Le profil a changé pendant le contrôle. Recommence la vérification.");
            review = Parse(ReadBounded(reportPath), profileId, hash, id, started) with { ReportPath = reportPath };
            using (var report = JsonDocument.Parse(ReadBounded(reportPath)))
            {
                string machine = Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography", "MachineGuid", null) as string ?? "";
                if (string.IsNullOrWhiteSpace(machine) || !string.Equals(report.RootElement.GetProperty("MachineGuid").GetString(), machine, StringComparison.OrdinalIgnoreCase) ||
                    report.RootElement.GetProperty("UserSid").GetString() != System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value)
                    throw new InvalidDataException("Le rapport ne correspond pas au Windows et au compte actifs.");
            }
            string[] fields = { "EditionId", "UILanguage", "Locale", "KeyboardLayout", "ComputerName", "UserName" };
            for (int index = 0; index < fields.Length; index++)
                if (review.Checks[index].Expected != document.RootElement.GetProperty(fields[index]).GetString())
                    throw new InvalidDataException("Les valeurs demandées ont changé dans le rapport.");
            if (review.Checks[6].Expected != "Verified" || review.Checks[7].Expected != "Completed")
                throw new InvalidDataException("Le rapport ne vérifie pas la finalisation et le raccourci attendus.");
            ValidateOptionExpectations(document.RootElement, review);
        }
        catch (Exception ex) when (ex is InvalidDataException or IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or System.Collections.Generic.KeyNotFoundException or FormatException)
        { review = null; error = ex.Message; if (ex is WorkerIntegrityException integrityError) errorCode = integrityError.Code; }
        var operation = new OperationResult
        {
            OperationId = id, Name = "Bilan après réinstallation de Windows", ExecutionKind = "Vérification", OperationKey = "InstalledWindowsVerification",
            StartedUtc = started, EndedUtc = DateTime.UtcNow, Phase = "Contrôle de Windows installé", JournalPath = journalPath, WorkerReportPath = reportPath,
            State = review == null ? OperationState.Unconfirmed : review.Passed ? OperationState.Succeeded : OperationState.Partial,
            ErrorCode = review?.Passed == true ? "" : errorCode,
            ExecutionStarted = errorCode.StartsWith("ENGINE_", StringComparison.Ordinal) ? false : null,
            Message = review?.Summary ?? "Bilan indisponible : " + error,
            TechnicalDetail = error,
            Checks = review?.Checks.Select(c => new OperationCheck(c.Name, c.Status is "Passed" or "NotRequested", c.Label + " — " + c.Comparison + "\n" + c.Detail)).ToArray() ?? Array.Empty<OperationCheck>()
        };
        string temp = journalPath + ".tmp";
        await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(operation, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, journalPath, true);
        return review ?? throw new InvalidDataException(error);
    }

    public static InstallationReview Parse(byte[] json, string profileId, string profileHash, string requestId, DateTime startedUtc)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        DateTime date = root.GetProperty("CheckedUtc").GetDateTime().ToUniversalTime();
        int schema = root.GetProperty("Schema").GetInt32();
        if (schema is not (1 or 2) || root.GetProperty("ProfileId").GetString() != profileId ||
            !string.Equals(root.GetProperty("ProfileSha256").GetString(), profileHash, StringComparison.OrdinalIgnoreCase) ||
            root.GetProperty("RequestId").GetString() != requestId || date < startedUtc.AddSeconds(-2) || date > DateTime.UtcNow.AddMinutes(1) ||
            !Guid.TryParse(root.GetProperty("MachineGuid").GetString(), out _) ||
            !(root.GetProperty("UserSid").GetString() ?? "").StartsWith("S-1-5-21-", StringComparison.Ordinal))
            throw new InvalidDataException("Ce rapport ne correspond pas au profil et au contrôle en cours.");
        var checks = JsonSerializer.Deserialize<InstallationCheck[]>(root.GetProperty("Checks").GetRawText()) ?? Array.Empty<InstallationCheck>();
        var expectedIds = schema == 2 ? ids.Concat(extraIds).ToArray() : ids;
        if (checks.Length != expectedIds.Length || checks.Any(c => c == null) || !checks.Select(c => c.Id).OrderBy(i => i).SequenceEqual(expectedIds.OrderBy(i => i)) ||
            checks.Any(c => c.Status is not ("Passed" or "Mismatch" or "Unavailable" or "NotRequested") || c.Expected == null || c.Actual == null || c.Detail == null ||
                (c.Status == "NotRequested" && (schema != 2 || !extraIds.Skip(1).Contains(c.Id) || c.Expected != "NotRequested" || c.Actual != "NotRequested")) ||
                (c.Status == "Passed" && (string.IsNullOrWhiteSpace(c.Expected) || !string.Equals(c.Expected, c.Actual, StringComparison.OrdinalIgnoreCase)))))
            throw new InvalidDataException("Les contrôles du rapport sont incomplets ou incohérents.");
        var allNames = schema == 2 ? names.Concat(extraNames).ToArray() : names;
        var ordered = expectedIds.Select((id, index) => checks.Single(c => c.Id == id) with { Name = allNames[index] }).ToList();
        if (schema == 1) ordered.Add(new("cleanupcoverage", "Nettoyage et langue des applications", "Profil complet", "Non enregistré", "Unavailable", "Ancien profil : les choix de nettoyage et la langue prioritaire des applications ne sont pas enregistrés. Ces résultats ne sont pas confirmés. Reprépare le média avec la version actuelle pour le prochain essai."));
        return new InstallationReview(date, ordered, "");
    }
    internal static void ValidateOptionExpectations(JsonElement profile, InstallationReview review)
    {
        bool complete = profile.GetProperty("Schema").GetInt32() == 2;
        if (!complete) { if (review.Checks.Count != 9) throw new InvalidDataException("Rapport incompatible avec l’ancien profil."); return; }
        if (review.Checks.Count != 16 || review.Checks[8].Expected != profile.GetProperty("UILanguage").GetString()) throw new InvalidDataException("Langue des applications non vérifiée.");
        var options = profile.GetProperty("Options");
        for (int i = 0; i < optionNames.Length; i++)
        {
            bool selected = options.GetProperty(optionNames[i]).GetBoolean();
            var check = review.Checks[9 + i];
            bool oobeOnly = i == 0 && options.TryGetProperty("RufusExperienceVersion", out var rufusVersion) && rufusVersion.GetString() == "4.15";
            bool widgetsConfiguration = optionNames[i] == "DisableWidgets";
            bool cleanLayout = i == 1 && options.TryGetProperty("CleanBastosVersion", out var cleanVersion) && cleanVersion.GetString() == "1";
            if (check.Expected != (selected ? (oobeOnly || cleanLayout || widgetsConfiguration ? "Configured" : "Applied") : "NotRequested") || (selected && check.Status == "NotRequested") || (!selected && check.Status != "NotRequested"))
                throw new InvalidDataException("Une option de nettoyage ne correspond pas au profil confirmé.");
        }
    }
    private static byte[] ReadBounded(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length > 1024 * 1024 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Profil ou rapport absent, trop volumineux ou redirigé.");
        return File.ReadAllBytes(path);
    }
}
