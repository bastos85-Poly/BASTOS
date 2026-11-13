using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Threading;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public static class WindowsDownloadCatalog
{
    public static readonly string[] Pages = { "windows_11_links", "windows_10_links" };
    private static readonly HttpClient Client = new HttpClient { Timeout = TimeSpan.FromSeconds(25) };
    private static readonly Regex Tokens = new Regex(@"<strong\b[^>]*>(?<title>.*?)</strong>|<table\b[^>]*>(?<table>.*?)</table>", RegexOptions.Singleline | RegexOptions.IgnoreCase);
    private static string Text(string html) => WebUtility.HtmlDecode(Regex.Replace(html, "<[^>]+>", "")).Trim();

    public static IReadOnlyList<WindowsDownloadChoice> ReadBundled()
    {
        using var stream = typeof(WindowsDownloadCatalog).Assembly.GetManifestResourceStream("Bastos.WindowsDownloadCatalog.json");
        return stream == null ? Array.Empty<WindowsDownloadChoice>() :
            (JsonSerializer.Deserialize<WindowsDownloadChoice[]>(stream) ?? Array.Empty<WindowsDownloadChoice>()).Where(IsSupportedChoice).ToArray();
    }

    public static async Task<(IReadOnlyList<WindowsDownloadChoice> Items, string Message)> RefreshAsync(IReadOnlyList<WindowsDownloadChoice> fallback, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var results = await Task.WhenAll(Pages.Select(async page =>
        {
            string url = "https://massgrave.dev/" + page;
            try
            {
                var items = ParsePage(await Client.GetStringAsync(url, cancellationToken), url);
                if (items.Count == 0) throw new InvalidDataException("Aucune ISO trouvée");
                return (Items: items, Failed: false);
            }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested && (error is HttpRequestException || error is TaskCanceledException || error is InvalidDataException))
            {
                return (Items: (IReadOnlyList<WindowsDownloadChoice>)fallback.Where(item => item.SourcePage == url).ToArray(), Failed: true);
            }
        }));
        cancellationToken.ThrowIfCancellationRequested();
        var combined = results.SelectMany(result => result.Items).Where(IsSupportedChoice)
            .DistinctBy(item => item.Url + "|" + item.FileName).ToArray();
        int failed = results.Count(result => result.Failed);
        return (combined, failed == 0 ? $"Catalogue actualisé : {combined.Length} ISO — massgrave.dev — {DateTime.Now:dd/MM/yyyy HH:mm}."
            : $"{combined.Length} ISO disponibles. {failed} rubrique(s) inaccessible(s) : liste précédente conservée pour ces rubriques.");
    }

    public static bool IsSupportedChoice(WindowsDownloadChoice item) =>
        (item.Family == "Windows 10" || item.Family == "Windows 11") &&
        item.Version.Contains(" Consumer ", StringComparison.OrdinalIgnoreCase) &&
        !item.Version.Contains("26H1", StringComparison.OrdinalIgnoreCase);

    public static IReadOnlyList<WindowsDownloadChoice> ParsePage(string html, string sourcePage)
    {
        if (!Pages.Any(page => sourcePage == "https://massgrave.dev/" + page)) throw new ArgumentException("Rubrique inconnue");
        var items = new List<WindowsDownloadChoice>();
        string version = "";
        foreach (Match token in Tokens.Matches(html))
        {
            if (token.Groups["title"].Success)
            {
                string title = Text(token.Groups["title"].Value);
                if (Regex.IsMatch(title, @"^Windows (?:10|11|Server)\b", RegexOptions.IgnoreCase) && title.Length < 95 && !title.Contains("activated", StringComparison.OrdinalIgnoreCase))
                    version = title;
                continue;
            }
            if (version.Length == 0) continue;
            string table = token.Groups["table"].Value;
            foreach (string row in Regex.Split(table, @"<tr\b[^>]*>", RegexOptions.IgnoreCase))
            {
                var cells = Regex.Matches(row, @"<td\b[^>]*>(.*?)(?=<td\b|</tr>|</tbody>|$)", RegexOptions.Singleline | RegexOptions.IgnoreCase);
                if (cells.Count < 3) continue;
                string language = Text(cells[0].Groups[1].Value);
                string arch = Text(cells[1].Groups[1].Value).ToLowerInvariant();
                if (arch != "x64" && arch != "x86" && arch != "arm64") continue;
                foreach (Match anchor in Regex.Matches(cells[2].Groups[1].Value, "<a\\b[^>]*href=(?:\"(?<url>[^\"]+)\"|'(?<url>[^']+)'|(?<url>[^\\s>]+))[^>]*>(?<name>.*?)</a>", RegexOptions.Singleline | RegexOptions.IgnoreCase))
                {
                    string fileName = Regex.Replace(Text(anchor.Groups["name"].Value), @"\s+\((?:Buzzheavier|ZeroFS)\)$", "", RegexOptions.IgnoreCase);
                    string url = WebUtility.HtmlDecode(anchor.Groups["url"].Value);
                    if (!fileName.EndsWith(".iso", StringComparison.OrdinalIgnoreCase) || fileName != Path.GetFileName(fileName) || !Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https") continue;
                    string family = version.StartsWith("Windows Server", StringComparison.OrdinalIgnoreCase) ? "Windows Server"
                        : version.StartsWith("Windows 11", StringComparison.OrdinalIgnoreCase) ? "Windows 11" : "Windows 10";
                    if (sourcePage.EndsWith("windows_ltsc_links")) family += family == "Windows 11" ? " LTSC" : " LTSC / LTSB";
                    items.Add(new WindowsDownloadChoice(family, version, language, FindLocale(fileName, language), arch, fileName, url, sourcePage));
                }
            }
        }
        return items.GroupBy(item => item.FileName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(item => new Uri(item.Url).Host == "zerofs.link" ? 0 : 1).First()).ToArray();
    }

    private static string FindLocale(string fileName, string language)
    {
        var prefix = Regex.Match(fileName, @"^(?<locale>[a-z]{2}(?:-[a-z]{4})?-[a-z]{2})_", RegexOptions.IgnoreCase);
        if (prefix.Success)
        {
            try { return CultureInfo.GetCultureInfo(prefix.Groups["locale"].Value).Name; }
            catch (CultureNotFoundException) { }
        }
        return language switch
        {
            "English" => "en-US", "French" => "fr-FR", "German" => "de-DE", "Arabic" => "ar-SA", "Bulgarian" => "bg-BG",
            "Chinese-Simplified" => "zh-CN", "Chinese-Traditional" => "zh-TW", "Czech" => "cs-CZ", "Danish" => "da-DK",
            "Dutch" or "Dutch-Netherlands" => "nl-NL", "Estonian" => "et-EE", "Finnish" => "fi-FI", "Greek" => "el-GR",
            "Hebrew" => "he-IL", "Hungarian" => "hu-HU", "Italian" => "it-IT", "Japanese" => "ja-JP", "Korean" => "ko-KR",
            "Latvian" => "lv-LV", "Lithuanian" => "lt-LT", "Norwegian" or "Norwegian-Bokmal" => "nb-NO", "Polish" => "pl-PL",
            "Portuguese-Brazil" => "pt-BR", "Portuguese-Portugal" => "pt-PT", "Romanian" => "ro-RO", "Russian" => "ru-RU",
            "Slovak" => "sk-SK", "Slovenian" => "sl-SI", "Spanish" => "es-ES", "Swedish" => "sv-SE", "Thai" => "th-TH",
            "Turkish" => "tr-TR", "Ukrainian" => "uk-UA", "Croatian" => "hr-HR", "Serbian-Latin" => "sr-Latn-RS",
            "English-United Kingdom" => "en-GB", "French-Canada" => "fr-CA", "Spanish-Mexico" => "es-MX", _ => ""
        };
    }
}
