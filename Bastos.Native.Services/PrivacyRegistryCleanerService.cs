using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed record PrivacyRegistryEntry(string Id, string Name, string RegistryPath, int Count);
public sealed record PrivacyRegistryResult(int ClearedGroups, int SkippedGroups, IReadOnlyList<string> Errors, IReadOnlyList<string> Backups);

/// <summary>Clears allowlisted Explorer MRU values after an exact second read and a durable JSON backup.</summary>
public sealed class PrivacyRegistryCleanerService
{
    private sealed record Definition(string Name, string Path, string EntryPattern, bool ChildLists);
    private sealed record ValueSnapshot(string Subkey, string Name, RegistryValueKind Kind, string Data);
    private sealed record Snapshot(PrivacyRegistryEntry Entry, Definition Definition, string Fingerprint, IReadOnlyList<ValueSnapshot> Values);
    private static readonly string Explorer = @"Software\Microsoft\Windows\CurrentVersion\Explorer";
    private readonly IReadOnlyList<Definition> definitions;
    private readonly Dictionary<string, Snapshot> current = new(StringComparer.Ordinal);
    private DateTime createdUtc;
    public PrivacyRegistryCleanerService() : this(new[]
    {
        new Definition("Documents récents", Explorer + @"\RecentDocs", @"^(?:\d+|MRUListEx)$", true),
        new Definition("Historique Exécuter", Explorer + @"\RunMRU", @"^(?:[a-z]|MRUList)$", false),
        new Definition("Adresses de l’Explorateur", Explorer + @"\TypedPaths", @"^url\d+$", false),
        new Definition("Recherches de l’Explorateur", Explorer + @"\WordWheelQuery", @"^(?:\d+|MRUListEx)$", false),
        new Definition("Ouvrir et Enregistrer", Explorer + @"\ComDlg32\OpenSavePidlMRU", @"^(?:\d+|MRUListEx)$", true),
        new Definition("Dossiers récemment visités", Explorer + @"\ComDlg32\LastVisitedPidlMRU", @"^(?:\d+|MRUListEx)$", false),
        new Definition("Lecteurs réseau récents", Explorer + @"\Map Network Drive MRU", @"^(?:[a-z]|MRUList)$", false)
    }) { }
    private PrivacyRegistryCleanerService(IReadOnlyList<Definition> definitions) { this.definitions = definitions; }
    internal PrivacyRegistryCleanerService(string fixtureSubkey) : this(new[] { new Definition("Historique fixture", fixtureSubkey, @"^(?:[a-z]|MRUList)$", false) }) { }

    public Task<IReadOnlyList<PrivacyRegistryEntry>> ScanAsync(CancellationToken token = default) => Task.Run<IReadOnlyList<PrivacyRegistryEntry>>(() =>
    {
        var found = new List<Snapshot>();
        foreach (var definition in definitions)
        {
            token.ThrowIfCancellationRequested();
            var values = Read(definition);
            int count = values.Count(v => !v.Name.StartsWith("MRUList", StringComparison.OrdinalIgnoreCase));
            if (count == 0) continue;
            var entry = new PrivacyRegistryEntry(Guid.NewGuid().ToString("N"), definition.Name, @"HKCU\" + definition.Path, count);
            found.Add(new(entry, definition, Fingerprint(values), values));
        }
        lock (current)
        {
            current.Clear(); foreach (var snapshot in found) current.Add(snapshot.Entry.Id, snapshot);
            createdUtc = DateTime.UtcNow;
        }
        return found.Select(s => s.Entry).ToArray();
    }, token);

    public Task<PrivacyRegistryResult> CleanAsync(IEnumerable<string> ids, string backupRoot, CancellationToken token = default) => Task.Run<PrivacyRegistryResult>(() =>
    {
        var selected = ids.Distinct(StringComparer.Ordinal).ToArray(); Snapshot[] snapshots;
        lock (current)
        {
            if (createdUtc == default || DateTime.UtcNow - createdUtc > TimeSpan.FromMinutes(30) || selected.Any(id => !current.ContainsKey(id))) throw new InvalidOperationException("Analyse absente ou expirée. Relance l’analyse.");
            snapshots = selected.Select(id => current[id]).ToArray(); current.Clear(); createdUtc = default;
        }
        var errors = new List<string>(); var backups = new List<string>(); int cleared = 0, skipped = 0;
        foreach (var snapshot in snapshots)
        {
            if (token.IsCancellationRequested) { skipped += snapshots.Length - cleared - skipped; break; }
            try
            {
                var latest = Read(snapshot.Definition);
                if (Fingerprint(latest) != snapshot.Fingerprint) throw new IOException("Historique modifié depuis l’analyse.");
                Directory.CreateDirectory(backupRoot);
                string backup = Path.Combine(backupRoot, "privacy-registry-" + Guid.NewGuid().ToString("N") + ".json");
                File.WriteAllText(backup, JsonSerializer.Serialize(new { snapshot.Entry.RegistryPath, snapshot.Values }));
                backups.Add(backup);
                using var key = Registry.CurrentUser.OpenSubKey(snapshot.Definition.Path, true) ?? throw new IOException("Clé disparue.");
                foreach (var sub in snapshot.Values.GroupBy(v => v.Subkey))
                {
                    using var child = sub.Key.Length == 0 ? null : key.OpenSubKey(sub.Key, true);
                    var target = sub.Key.Length == 0 ? key : child ?? throw new IOException("Sous-clé disparue.");
                    foreach (var value in sub) target.DeleteValue(value.Name, false);
                }
                if (Read(snapshot.Definition).Count > 0) throw new IOException("Effacement incomplet ; sauvegarde conservée : " + backup);
                cleared++;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            { skipped++; errors.Add(snapshot.Entry.Name + " : " + e.Message); }
        }
        return new(cleared, skipped, errors.AsReadOnly(), backups.AsReadOnly());
    }, token);

    private static IReadOnlyList<ValueSnapshot> Read(Definition definition)
    {
        var values = new List<ValueSnapshot>();
        using var key = Registry.CurrentUser.OpenSubKey(definition.Path, false);
        if (key == null) return values;
        void Collect(RegistryKey source, string subkey)
        {
            foreach (string name in source.GetValueNames().OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                if (!Regex.IsMatch(name, definition.EntryPattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;
                var value = source.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                var kind = source.GetValueKind(name);
                string data = value is byte[] binary ? Convert.ToBase64String(binary) : value?.ToString() ?? "";
                values.Add(new(subkey, name, kind, data));
                if (values.Count > 5000) throw new IOException("Liste trop longue : aucune action.");
            }
        }
        Collect(key, "");
        if (definition.ChildLists)
        {
            var subkeys = key.GetSubKeyNames();
            if (subkeys.Length > 5000) throw new IOException("Trop de sous-clés : aucune action.");
            foreach (string subkey in subkeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                using var child = key.OpenSubKey(subkey, false);
                if (child != null) Collect(child, subkey);
            }
        }
        return values;
    }
    private static string Fingerprint(IReadOnlyList<ValueSnapshot> values) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(values))));
}
