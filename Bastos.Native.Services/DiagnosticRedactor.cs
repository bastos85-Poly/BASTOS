using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Bastos.Native.Services;

// Free text is opt-in. The default export contains no free text at all.
public sealed class DiagnosticRedactor
{
    private readonly string[] identities;
    public DiagnosticRedactor(IEnumerable<string>? identities = null)
    {
        this.identities = (identities ?? new[] { Environment.UserName, Environment.MachineName, Environment.UserDomainName })
            .Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase).OrderByDescending(s => s.Length).ToArray();
    }
    private static string Replace(string text, string pattern, string replacement) =>
        Regex.Replace(text, pattern, replacement, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
    public string Clean(string? source, int maximum = 1200)
    {
        if (string.IsNullOrEmpty(source)) return "";
        // Redact before truncating, so truncation cannot expose part of a secret.
        if (source.Length > 128 * 1024) return "[Détail trop volumineux retiré]";
        string text = source.Replace('\0', ' ');
        text = Replace(text, @"(?m)^.*(?:password|passwd|mot de passe|secret|token|authorization|api.?key|credential|cl[eé].?(?:produit|activation)|serial(?:number)?|num[eé]ro de s[eé]rie|ssid|bssid|username|computername|hostname|machineguid|utilisateur|compte local|nom du pc).*$", "[Ligne sensible retirée]");
        text = Replace(text, @"\b(?:https?|ftp)://[^\s<>""']+", "[URL retirée]");
        text = Replace(text, @"(?:[A-Z]:[\\/]|\\\\)[^\r\n<>""|]*", "[Chemin retiré]");
        text = Replace(text, @"(?<![\w:])/(?:Users|home|mnt|tmp|var|etc)/[^\r\n<>""|]*", "[Chemin retiré]");
        text = Replace(text, @"[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}", "[Adresse courriel retirée]");
        text = Replace(text, @"\bS-1-\d+(?:-\d+){1,15}\b", "[SID retiré]");
        text = Replace(text, @"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "[Identifiant retiré]");
        text = Replace(text, @"\b[0-9a-f]{32,128}\b", "[Empreinte retirée]");
        text = Replace(text, @"\b(?:\d{1,3}\.){3}\d{1,3}\b", "[Adresse IP retirée]");
        text = Replace(text, @"(?<!\w)(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]+", "[Adresse réseau retirée]");
        text = Replace(text, @"\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b", "[Adresse matérielle retirée]");
        text = Replace(text, @"\b(?:[A-Z0-9]{5}-){4}[A-Z0-9]{5}\b", "[Clé produit retirée]");
        foreach (string identity in identities)
            text = Replace(text, @"(?<![\p{L}\p{N}_])" + Regex.Escape(identity) + @"(?![\p{L}\p{N}_])", "[Identité retirée]");
        text = new string(text.Where(c => !char.IsControl(c) || c is '\n' or '\r' or '\t').ToArray());
        return text.Length <= maximum ? text : text[..maximum] + "\n[Détail tronqué]";
    }
}
