using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed record EnvironmentCleanerEntry(string Id, string Scope, string Name, string Value, bool IsPathEntry);
public sealed record EnvironmentCleanerResult(int Removed, int Skipped, IReadOnlyList<string> Errors, string? BackupPath);

/// <summary>Finds missing local paths in registry-backed environment settings, then rechecks and backs up exact values before mutation.</summary>
public sealed class EnvironmentCleanerService
{
    private readonly Dictionary<string, EnvironmentCleanerEntry> current = new(StringComparer.Ordinal);
    private readonly string? fixtureSubkey;
    public EnvironmentCleanerService() { }
    internal EnvironmentCleanerService(string fixtureSubkey) { this.fixtureSubkey = fixtureSubkey; }
    private DateTime createdUtc;
    private static readonly string[] FolderVariables = { "JAVA_HOME", "JDK_HOME", "JRE_HOME", "GOROOT", "GOBIN", "CARGO_HOME", "RUSTUP_HOME", "NVM_HOME", "NVM_DIR", "NVM_SYMLINK", "CONDA_HOME", "PYENV_ROOT", "ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_NDK_ROOT", "FLUTTER_ROOT", "MAVEN_HOME", "GRADLE_HOME" };
    private (RegistryKey Root, string Path) RegistryLocation(string scope) => fixtureSubkey != null ? (Registry.CurrentUser, fixtureSubkey)
        : scope == "Utilisateur" ? (Registry.CurrentUser, @"Environment") : (Registry.LocalMachine, @"SYSTEM\CurrentControlSet\Control\Session Manager\Environment");

    public Task<IReadOnlyList<EnvironmentCleanerEntry>> ScanAsync(CancellationToken token = default) => Task.Run<IReadOnlyList<EnvironmentCleanerEntry>>(() =>
    {
        var found = new List<EnvironmentCleanerEntry>();
        foreach (string scope in fixtureSubkey != null ? new[] { "Utilisateur" } : new[] { "Utilisateur", "Machine" })
        {
            token.ThrowIfCancellationRequested();
            var (root, path) = RegistryLocation(scope);
            using var key = root.OpenSubKey(path, false);
            if (key == null) continue;
            string? pathValue = key.GetValue("Path", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
            if (pathValue != null)
                foreach (string segment in pathValue.Split(';', StringSplitOptions.TrimEntries))
                    if (IsMissingLocalPath(segment)) found.Add(new(Guid.NewGuid().ToString("N"), scope, "Path", segment, true));
            foreach (string name in FolderVariables)
            {
                string? value = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                if (value != null && IsMissingLocalPath(value)) found.Add(new(Guid.NewGuid().ToString("N"), scope, name, value, false));
            }
        }
        lock (current)
        {
            current.Clear(); foreach (var entry in found) current.Add(entry.Id, entry);
            createdUtc = DateTime.UtcNow;
        }
        return found.AsReadOnly();
    }, token);

    private static bool IsMissingLocalPath(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return false;
        string expanded = Environment.ExpandEnvironmentVariables(raw.Trim().Trim('"'));
        if (expanded.Contains('%') || expanded.StartsWith(@"\\", StringComparison.Ordinal) || !Path.IsPathFullyQualified(expanded)) return false;
        try
        {
            string? root = Path.GetPathRoot(expanded);
            if (root == null || !Directory.Exists(root)) return false;
            return !Directory.Exists(expanded) && !File.Exists(expanded);
        }
        catch { return false; }
    }

    public Task<EnvironmentCleanerResult> CleanAsync(IEnumerable<string> ids, string backupRoot, CancellationToken token = default) => Task.Run<EnvironmentCleanerResult>(() =>
    {
        var selected = ids.Distinct(StringComparer.Ordinal).ToArray();
        EnvironmentCleanerEntry[] entries;
        lock (current)
        {
            if (createdUtc == default || DateTime.UtcNow - createdUtc > TimeSpan.FromMinutes(30) || selected.Any(id => !current.ContainsKey(id)))
                throw new InvalidOperationException("Analyse absente ou expirée. Relance l’analyse.");
            entries = selected.Select(id => current[id]).ToArray(); current.Clear(); createdUtc = default;
        }
        var errors = new List<string>(); int removed = 0, skipped = 0; string? backup = null;
        if (entries.Length == 0) return new(0, 0, errors.AsReadOnly(), null);
        var originals = new List<object>();
        foreach (var entry in entries)
        {
            var (root, path) = RegistryLocation(entry.Scope);
            using var key = root.OpenSubKey(path, false);
            if (key == null) throw new IOException("Clé du registre indisponible : aucune modification.");
            string? currentValue = key.GetValue(entry.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
            if (currentValue == null || !CurrentStillContains(entry, currentValue) || !IsMissingLocalPath(entry.Value))
                throw new IOException("Une valeur a changé depuis l’analyse : aucune modification. Relance l’analyse.");
            originals.Add(new { entry.Scope, entry.Name, Value = currentValue, Kind = key.GetValueKind(entry.Name).ToString() });
        }
        Directory.CreateDirectory(backupRoot);
        backup = Path.Combine(backupRoot, "environment-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N") + ".json");
        File.WriteAllText(backup, JsonSerializer.Serialize(originals));
        foreach (var entry in entries)
        {
            if (token.IsCancellationRequested) { skipped += entries.Length - removed - skipped; break; }
            try
            {
                var (root, path) = RegistryLocation(entry.Scope);
                using var key = root.OpenSubKey(path, true) ?? throw new UnauthorizedAccessException("Droits insuffisants pour cette portée.");
                string value = key.GetValue(entry.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string ?? throw new IOException("Valeur disparue.");
                if (!CurrentStillContains(entry, value) || !IsMissingLocalPath(entry.Value)) throw new IOException("Valeur modifiée depuis l’analyse.");
                if (entry.IsPathEntry)
                {
                    var parts = value.Split(';').ToList(); int index = parts.FindIndex(part => part.Trim().Equals(entry.Value, StringComparison.OrdinalIgnoreCase));
                    if (index < 0) throw new IOException("Entrée PATH disparue.");
                    parts.RemoveAt(index); key.SetValue(entry.Name, string.Join(';', parts), key.GetValueKind(entry.Name));
                }
                else key.DeleteValue(entry.Name, false);
                removed++;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            { skipped++; errors.Add(entry.Scope + " / " + entry.Name + " : " + e.Message); }
        }
        if (removed > 0) BroadcastChange();
        return new(removed, skipped, errors.AsReadOnly(), backup);
    }, token);
    private static bool CurrentStillContains(EnvironmentCleanerEntry entry, string value) => entry.IsPathEntry
        ? value.Split(';').Any(part => part.Trim().Equals(entry.Value, StringComparison.OrdinalIgnoreCase)) : value.Equals(entry.Value, StringComparison.Ordinal);
    private static void BroadcastChange()
    {
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, "Environment", 0x0002, 5000, out _);
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wparam, string lparam, uint flags, uint timeout, out IntPtr result);
}

