using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed class OfficialDriverService(string configPath, Action<string> openBrowser, Action<string>? copySearch = null)
{
    public const string NvidiaDriversUrl = "https://www.nvidia.com/fr-fr/drivers/";

    public static bool IsAllowed(string text, IReadOnlyList<string> domains) =>
        Uri.TryCreate(text, UriKind.Absolute, out var uri) && uri.Scheme == "https" &&
        string.IsNullOrEmpty(uri.UserInfo) && uri.IsDefaultPort && domains.Any(domain => !string.IsNullOrWhiteSpace(domain) &&
            (uri.DnsSafeHost.TrimEnd('.').Equals(domain.Trim().TrimStart('.'), StringComparison.OrdinalIgnoreCase) ||
             uri.DnsSafeHost.TrimEnd('.').EndsWith("." + domain.Trim().TrimStart('.'), StringComparison.OrdinalIgnoreCase)));

    public static string Resolve(string url, string strategy) =>
        string.Equals(strategy, "NVIDIA_LATEST_GEFORCE", StringComparison.OrdinalIgnoreCase) ? NvidiaDriversUrl : url;

    public async Task<string[]> ReadDomainsAsync()
    {
        if (new FileInfo(configPath).Length > 1024 * 1024) throw new InvalidDataException("Configuration des sources trop volumineuse.");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(configPath));
        var domains = document.RootElement.GetProperty("allowedDomains").EnumerateArray().Select(value => value.GetString() ?? "").ToArray();
        if (domains.Length == 0 || domains.Any(domain => string.IsNullOrWhiteSpace(domain) || domain.Contains('/') || domain.Contains(':')))
            throw new InvalidDataException("Liste de domaines officiels invalide.");
        return domains;
    }

    public async Task<NativeOperationReport> ExecuteAsync(string requestedUrl, string strategy, string searchTerm, IProgress<WorkerProgress> progress)
    {
        var data = new Dictionary<string, object?> { ["RequestedUrl"] = requestedUrl, ["ResolutionStrategy"] = strategy, ["LaunchRequested"] = false };
        NativeOperationReport Failure(string code, string message, Exception? error = null) => new(false, message, data, code, error?.ToString() ?? "");
        progress.Report(new(10, "Vérification du lien", "Lecture des sources officielles…"));
        string[] domains;
        try { domains = await ReadDomainsAsync(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or KeyNotFoundException)
        { return Failure("OFFICIAL_SOURCES_UNAVAILABLE", "Les sources officielles sont absentes ou illisibles. Répare les fichiers de Bastos puis réessaie.", error); }
        string finalUrl = Resolve(requestedUrl, strategy);
        if (!IsAllowed(requestedUrl, domains) || !IsAllowed(finalUrl, domains))
            return Failure("DRIVER_URL_REFUSED", "Le lien du pilote a été refusé : une adresse HTTPS figurant dans les sources officielles est requise. Aucun navigateur n’a été ouvert.");
        data["Url"] = finalUrl;
        data["AllowedDomains"] = domains;
        bool copied = false;
        if (!string.IsNullOrWhiteSpace(searchTerm) && copySearch != null)
        {
            try { copySearch(searchTerm); copied = true; } catch { /* Optional clipboard; the driver page can still open. */ }
        }
        data["SearchTermCopied"] = copied;
        progress.Report(new(70, "Ouverture du navigateur", "Transmission du lien officiel à Windows…"));
        try { openBrowser(finalUrl); }
        catch (Exception error)
        { return Failure("BROWSER_OPEN_FAILED", "Windows n’a pas confirmé l’ouverture du navigateur. Vérifie ton navigateur par défaut avant de réessayer.", error); }
        data["LaunchRequested"] = true;
        return new(true, "Demande d’ouverture transmise au navigateur.", data);
    }
}
