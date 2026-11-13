using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public static class OperationVerifiers
{
    public static async Task<OperationVerification> WebView2BootstrapperAsync(string cacheRoot, JsonElement report)
    {
        string expectedPath = Path.Combine(cacheRoot, report.GetProperty("OperationId").GetString() ?? "", "MicrosoftEdgeWebview2Setup.exe");
        var checks = new List<OperationCheck>();
        bool path = report.TryGetProperty("Path", out var reported) && reported.ValueKind == JsonValueKind.String &&
            string.Equals(Path.GetFullPath(reported.GetString() ?? ""), Path.GetFullPath(expectedPath), StringComparison.OrdinalIgnoreCase) && File.Exists(expectedPath);
        checks.Add(new("Bootstrapper attendu", path, expectedPath));
        if (!path) return Invalid("Bootstrapper WebView2 impossible à confirmer : fichier absent ou chemin incorrect.", checks);
        using var file = new FileStream(expectedPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        bool size = report.TryGetProperty("FileLength", out var length) && length.TryGetInt64(out long bytes) &&
            report.TryGetProperty("ExpectedLength", out var expected) && expected.TryGetInt64(out long wanted) &&
            file.Length >= 1024 * 1024 && file.Length <= 20 * 1024 * 1024 && file.Length == bytes && bytes == wanted;
        bool signature = report.TryGetProperty("SignatureStatus", out var status) && status.GetString() == "Valid" &&
            report.TryGetProperty("SignerSubject", out var subject) && System.Text.RegularExpressions.Regex.IsMatch(subject.GetString() ?? "", @"(?:^|,\s*)O=Microsoft Corporation(?:,|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        string actual = Convert.ToHexString(await SHA256.HashDataAsync(file));
        bool hash = report.TryGetProperty("Sha256", out var sha) && string.Equals(actual, sha.GetString(), StringComparison.OrdinalIgnoreCase);
        file.Position = 0;
        bool executable = file.ReadByte() == 'M' && file.ReadByte() == 'Z';
        bool url = report.TryGetProperty("FinalUrl", out var final) && Uri.TryCreate(final.GetString(), UriKind.Absolute, out var uri) &&
            OfficialDriverService.IsAllowed(uri.AbsoluteUri, new[] { "microsoft.com", "msedge.net" });
        checks.Add(new("Taille du téléchargement", size, "Taille reçue comparée à la taille annoncée."));
        checks.Add(new("Signature Microsoft contrôlée par Windows", signature, "Éditeur Microsoft Corporation requis."));
        checks.Add(new("Intégrité du fichier signé", hash && executable, actual));
        checks.Add(new("Provenance Microsoft", url, "Redirection HTTPS vers un domaine Microsoft autorisé."));
        return checks.All(check => check.Passed) ? new(true, "Bootstrapper WebView2 téléchargé et vérifié ; aucune installation confirmée par ce seul contrôle.", checks)
            : Invalid("Bootstrapper WebView2 impossible à confirmer : taille, signature, provenance ou intégrité incorrecte.", checks);
    }

    public static async Task<OperationVerification> WebView2Async(string cacheRoot, Func<string?> readVersion, JsonElement report)
    {
        var checks = new List<OperationCheck>();
        string? reported = report.GetProperty("Version").GetString();
        string? actual = readVersion();
        bool version = WebView2RuntimeService.IsInstalledVersion(reported) && WebView2RuntimeService.IsInstalledVersion(actual) && new Version(actual!) >= new Version(reported!);
        checks.Add(new("Version relue dans Windows", version, $"Rapport : {reported ?? "absente"} ; lecture indépendante : {actual ?? "absente"}."));
        if (!version) return Invalid("WebView2 n’est pas confirmé : aucune version valide correspondante n’est détectée dans Windows. Vérifie son installation avant de poursuivre.", checks);
        string? status = report.GetProperty("Status").GetString();
        bool started = report.GetProperty("InstallerStarted").GetBoolean();
        bool mode = status == "AlreadyInstalled" && !started || status == "Installed" && started;
        checks.Add(new("Étape réellement terminée", mode, "Déjà présent ou version détectée après installation."));
        if (!mode) return Invalid("WebView2 n’est pas confirmé : le rapport indique uniquement un téléchargement ou un état incohérent.", checks);
        if (started)
        {
            var bootstrapper = await WebView2BootstrapperAsync(cacheRoot, report);
            checks.AddRange(bootstrapper.Checks);
            if (!bootstrapper.Valid) return Invalid(bootstrapper.Message, checks);
        }
        bool warning = started && report.TryGetProperty("InstallerExitCode", out var exit) && exit.ValueKind != JsonValueKind.Null &&
            (!exit.TryGetInt32(out int code) || code is not (0 or 3010));
        string message = $"WebView2 {actual} est détecté dans Windows ; version vérifiée.";
        if (warning) message += " L’installateur a signalé une erreur malgré cette présence ; consulte le journal si le téléchargement Windows ne s’ouvre pas.";
        return new(true, message, checks, warning);
    }

    public static Task<OperationVerification> CleanupAsync(bool analyzeOnly, JsonElement report)
    {
        var checks = new List<OperationCheck>();
        string[] names = { "Count", "Bytes", "EligibleCount", "EligibleBytes", "Removed", "RemovedBytes", "Failed", "ScanErrors", "SkippedLinks" };
        var numbers = new Dictionary<string, long>();
        foreach (string name in names)
        {
            if (!report.TryGetProperty(name, out var value) || !value.TryGetInt64(out long number) || number < 0)
                return Task.FromResult(Invalid("Nettoyage impossible à confirmer : compteurs absents ou invalides.", checks));
            numbers[name] = number;
        }
        bool mode = report.GetProperty("AnalyzeOnly").GetBoolean() == analyzeOnly;
        bool coherent = numbers["EligibleCount"] <= numbers["Count"] && numbers["EligibleBytes"] <= numbers["Bytes"] &&
            numbers["RemovedBytes"] <= numbers["EligibleBytes"] && numbers["Removed"] <= numbers["EligibleCount"] &&
            (analyzeOnly ? numbers["Removed"] == 0 && numbers["RemovedBytes"] == 0 && numbers["Failed"] == 0
                : numbers["Removed"] + numbers["Failed"] == numbers["EligibleCount"]);
        bool targets = report.GetProperty("Targets").ValueKind == JsonValueKind.Array && report.GetProperty("Targets").GetArrayLength() > 0 &&
            report.GetProperty("Targets").EnumerateArray().All(value => Path.IsPathFullyQualified(value.GetString() ?? "") &&
                string.Equals(Path.GetFileName(value.GetString()!.TrimEnd('\\')), "Temp", StringComparison.OrdinalIgnoreCase));
        checks.Add(new("Mode et dossiers temporaires", mode && targets, "Mode demandé et racines TEMP contrôlés."));
        checks.Add(new("Compteurs cohérents", coherent, "Seuls les fichiers de plus de 24 heures sont éligibles."));
        checks.Add(new("Suppressions contrôlées par le worker", report.GetProperty("DeletionVerified").GetBoolean(), "Absence contrôlée immédiatement après chaque suppression."));
        if (checks.Any(check => !check.Passed)) return Task.FromResult(Invalid("Résultat du nettoyage incohérent : consulte le journal.", checks));
        bool partial = numbers["Failed"] > 0 || numbers["ScanErrors"] > 0;
        string message = analyzeOnly ? $"Analyse : {numbers["EligibleCount"]} fichier(s) de plus de 24 h, {numbers["EligibleBytes"] / 1048576d:N1} Mo potentiellement récupérables."
            : $"Nettoyage : {numbers["Removed"]} fichier(s) supprimé(s), {numbers["RemovedBytes"] / 1048576d:N1} Mo de fichiers supprimés.";
        if (partial) message += $" Résultat partiel : {numbers["Failed"]} fichier(s) conservé(s), {numbers["ScanErrors"]} dossier(s) inaccessible(s). Ferme les applications concernées puis relance une analyse.";
        if (numbers["SkippedLinks"] > 0) message += " Les liens et dossiers redirigés ont été ignorés.";
        return Task.FromResult(new OperationVerification(true, message, checks, partial));
    }

    public static Task<OperationVerification> OfficialDriverAsync(string requestedUrl, string strategy, IReadOnlyList<string> domains, JsonElement report)
    {
        string final = report.GetProperty("Url").GetString() ?? "";
        string expected = OfficialDriverService.Resolve(requestedUrl, strategy);
        var checks = new[] {
            new OperationCheck("Domaines officiels", OfficialDriverService.IsAllowed(requestedUrl, domains) && OfficialDriverService.IsAllowed(final, domains), "HTTPS et domaines autorisés requis."),
            new OperationCheck("Lien demandé", report.GetProperty("RequestedUrl").GetString() == requestedUrl && final == expected, final),
            new OperationCheck("Transmission au navigateur", report.GetProperty("LaunchRequested").GetBoolean(), "Chargement de la page non contrôlé.") };
        return Task.FromResult(checks.All(check => check.Passed) ? new OperationVerification(true,
            "Lien officiel vérifié ; demande d’ouverture transmise au navigateur. Le chargement de la page reste à vérifier dans le navigateur.", checks)
            : Invalid("Ouverture impossible à confirmer : lien ou rapport incorrect. Consulte le journal.", checks));
    }

    public static Task<OperationVerification> NetworkAsync(JsonElement report)
    {
        var checks = new List<OperationCheck>();
        bool configuration = report.TryGetProperty("Target", out var target) && target.ValueKind == JsonValueKind.String && target.GetString() == NetworkDiagnosticsService.Target &&
            report.TryGetProperty("Attempts", out var attempts) && attempts.TryGetInt32(out int count) && count == NetworkDiagnosticsService.Attempts &&
            report.TryGetProperty("TimeoutMs", out var timeout) && timeout.TryGetInt32(out int milliseconds) && milliseconds == NetworkDiagnosticsService.TimeoutMs;
        checks.Add(new("Cible et paramètres du test", configuration, "8 essais ICMP vers 1.1.1.1, délai de 1 seconde par essai."));
        if (!configuration || !report.TryGetProperty("Replies", out var replies) || replies.ValueKind != JsonValueKind.Array || replies.GetArrayLength() != NetworkDiagnosticsService.Attempts)
            return Task.FromResult(Invalid("Mesure réseau impossible à confirmer : paramètres ou réponses incomplets.", checks));
        var latencies = new List<long>();
        int index = 0;
        foreach (var reply in replies.EnumerateArray())
        {
            index++;
            bool valid = reply.ValueKind == JsonValueKind.Object && reply.TryGetProperty("Sequence", out var sequence) && sequence.TryGetInt32(out int number) && number == index &&
                reply.TryGetProperty("Status", out var status) && status.ValueKind == JsonValueKind.String &&
                reply.TryGetProperty("RoundtripMs", out _);
            if (!valid) return Task.FromResult(Invalid("Mesure réseau impossible à confirmer : essai manquant ou invalide.", checks));
            string state = reply.GetProperty("Status").GetString() ?? "";
            var latency = reply.GetProperty("RoundtripMs");
            if (state == "Success")
            {
                if (!latency.TryGetInt64(out long value) || value < 0)
                    return Task.FromResult(Invalid("Mesure réseau impossible à confirmer : latence incohérente.", checks));
                latencies.Add(value);
            }
            else if (latency.ValueKind != JsonValueKind.Null || (state != "Error" && (!Enum.TryParse<IPStatus>(state, out var parsed) || !Enum.IsDefined(parsed))))
                return Task.FromResult(Invalid("Mesure réseau impossible à confirmer : état de réponse invalide.", checks));
        }
        int lost = NetworkDiagnosticsService.Attempts - latencies.Count;
        checks.Add(new("Réponses et latences", true, $"{latencies.Count} réponses ; {lost} essais sans réponse."));
        string message = $"ICMP vers 1.1.1.1 : {latencies.Count}/8 réponses, {lost * 100d / 8:N1} % de perte.";
        if (latencies.Count > 0) message += $" Latence : min. {latencies.Min()} ms, moyenne {latencies.Average():N1} ms, max. {latencies.Max()} ms.";
        if (lost > 0) message += " Résultat partiel : des réponses ICMP peuvent être filtrées ou perdues ; cela ne suffit pas à conclure à une panne Internet.";
        return Task.FromResult(new OperationVerification(true, message, checks, lost > 0));
    }

    public static async Task<OperationVerification> RufusAsync(string expectedPath, JsonElement report)
    {
        var checks = new List<OperationCheck>();
        bool pathMatches = report.TryGetProperty("Path", out var path) && path.ValueKind == JsonValueKind.String &&
            string.Equals(Path.GetFullPath(path.GetString() ?? ""), Path.GetFullPath(expectedPath), StringComparison.OrdinalIgnoreCase);
        checks.Add(new("Fichier attendu", pathMatches && File.Exists(expectedPath), expectedPath));
        if (!checks.Last().Passed) return Invalid("Rufus n’est pas prêt : le fichier attendu est absent ou le chemin du rapport est incorrect.", checks);
        using var file = new FileStream(expectedPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        bool sizeMatches = report.TryGetProperty("FileLength", out var length) && length.ValueKind == JsonValueKind.Number && length.TryGetInt64(out long reportedLength) &&
            report.TryGetProperty("ExpectedLength", out var expected) && expected.ValueKind == JsonValueKind.Number && expected.TryGetInt64(out long expectedLength) &&
            file.Length > 0 && file.Length == reportedLength && file.Length == expectedLength;
        checks.Add(new("Taille du téléchargement", sizeMatches, $"{file.Length} octets ; comparaison aux métadonnées GitHub."));
        bool signature = report.TryGetProperty("SignatureStatus", out var status) && status.ValueKind == JsonValueKind.String && status.GetString() == "Valid" &&
            report.TryGetProperty("SignerSubject", out var signer) && signer.ValueKind == JsonValueKind.String && (signer.GetString() ?? "").Contains("Akeo Consulting", StringComparison.OrdinalIgnoreCase);
        checks.Add(new("Signature contrôlée par le worker Windows", signature, "Signature valide et éditeur Akeo Consulting requis."));
        string actual = Convert.ToHexString(await SHA256.HashDataAsync(file));
        bool hashMatches = report.TryGetProperty("Sha256", out var hash) && hash.ValueKind == JsonValueKind.String && actual.Equals(hash.GetString(), StringComparison.OrdinalIgnoreCase);
        checks.Add(new("Empreinte du fichier signé", hashMatches, actual));
        file.Position = 0;
        bool executable = file.ReadByte() == 'M' && file.ReadByte() == 'Z';
        checks.Add(new("Exécutable Windows", executable, "En-tête MZ requis."));
        return checks.All(check => check.Passed) ? new(true, "Rufus est prêt : fichier téléchargé, signature et intégrité vérifiées.", checks)
            : Invalid("Rufus n’a pas été ouvert : sa taille, sa signature ou son intégrité n’a pas pu être confirmée. Consulte le journal puis réessaie le téléchargement.", checks);
    }

    public static Task<OperationVerification> HardwareAsync(JsonElement payload)
    {
        var checks = new List<OperationCheck>();
        if (!payload.TryGetProperty("Report", out var report) || report.ValueKind != JsonValueKind.Object)
            return Task.FromResult(Invalid("Analyse impossible à confirmer : le rapport matériel est absent.", checks));
        bool objects = new[] { "System", "Motherboard", "Summary" }.All(name => report.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Object);
        checks.Add(new("Structure de l’inventaire", objects, "Système, carte mère et résumé présents."));
        bool arrays = new[] { "Processors", "Graphics", "Storage", "Network", "Audio", "ProblemDevices", "CollectionErrors" }
            .All(name => report.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Array && (name == "CollectionErrors" || value.EnumerateArray().All(item => item.ValueKind == JsonValueKind.Object)));
        bool recommendations = payload.TryGetProperty("Recommendations", out var rec) && rec.ValueKind == JsonValueKind.Array && rec.EnumerateArray().All(item => item.ValueKind == JsonValueKind.Object);
        checks.Add(new("Listes de périphériques et recommandations", arrays && recommendations, "Types des listes et de leurs éléments contrôlés."));
        if (!objects || !arrays || !recommendations) return Task.FromResult(Invalid("Analyse impossible à confirmer : le rapport est incomplet ou mal formé.", checks));
        var summary = report.GetProperty("Summary");
        bool counts = new[] { "DetectedDevices", "ProblemCount" }.All(name => summary.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number) && number >= 0);
        checks.Add(new("Compteurs du résumé", counts, "Compteurs entiers et positifs ou nuls."));
        bool partial = report.GetProperty("CollectionErrors").GetArrayLength() > 0 || (payload.TryGetProperty("RecommendationError", out var error) && !string.IsNullOrWhiteSpace(error.ToString()));
        bool hasData = new[] { "Processors", "Graphics", "Storage", "Network", "Audio" }.Any(name => report.GetProperty(name).GetArrayLength() > 0);
        checks.Add(new("Collecte exploitable", !partial || hasData, partial ? "La collecte comporte des informations indisponibles ; voir le rapport." : "Aucune erreur de collecte signalée."));
        if (!counts || (partial && !hasData)) return Task.FromResult(Invalid("Analyse impossible à confirmer : aucune collecte exploitable ou résumé invalide. Vérifie les services de gestion Windows puis réessaie.", checks));
        return Task.FromResult(new OperationVerification(true, partial ? "Analyse partielle : les données disponibles ont été vérifiées ; certains composants ou recommandations n’ont pas pu être lus. Consulte le rapport."
            : "Analyse matérielle terminée : rapport et inventaire vérifiés.", checks, partial));
    }
    private static OperationVerification Invalid(string message, IReadOnlyList<OperationCheck> checks) => new(false, message, checks);
}
