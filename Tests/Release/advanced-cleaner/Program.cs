using Bastos.Native.Services;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Text;

int checks = 0;
void Check(bool pass, string name) { if (!pass) throw new Exception("FAIL: " + name); checks++; Console.WriteLine("PASS: " + name); }
string fixture = Path.Combine(Path.GetTempPath(), "BASTOS-Advanced-Cleaner-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(fixture);
string registryPath = @"Software\BastosCleanerFixture\" + Guid.NewGuid().ToString("N");
string privacyPath = @"Software\BastosCleanerFixture\" + Guid.NewGuid().ToString("N");
string missing1 = Path.Combine(fixture, "not-installed"), missing2 = Path.Combine(fixture, "missing-sdk");
try
{
    using (var key = Registry.CurrentUser.CreateSubKey(registryPath)!)
    {
        key.SetValue("Path", missing1 + ";" + fixture, RegistryValueKind.ExpandString);
        key.SetValue("JAVA_HOME", missing2, RegistryValueKind.String);
    }
    var env = new EnvironmentCleanerService(registryPath);
    var preview = await env.ScanAsync();
    Check(preview.Count == 2 && preview.All(e => !string.IsNullOrEmpty(e.Id)), "Deux valeurs orphelines découvertes dans la clé fixture");
    var pathEntry = preview.Single(e => e.IsPathEntry);
    var envResult = await env.CleanAsync(new[] { pathEntry.Id }, Path.Combine(fixture, "backups"));
    using (var key = Registry.CurrentUser.OpenSubKey(registryPath)!)
    {
        Check(envResult.Removed == 1 && key.GetValue("Path", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string == fixture, "Seule l’entrée PATH choisie est retirée");
        Check(key.GetValue("JAVA_HOME") as string == missing2, "Variable non choisie conservée");
        Check(key.GetValueKind("Path") == RegistryValueKind.ExpandString, "Type ExpandString conservé");
    }
    Check(envResult.BackupPath != null && File.Exists(envResult.BackupPath) && System.Text.Json.JsonDocument.Parse(File.ReadAllText(envResult.BackupPath)).RootElement[0].GetProperty("Value").GetString()!.Contains(missing1), "Valeur complète sauvegardée avant changement");
    bool replay = false; try { await env.CleanAsync(new[] { pathEntry.Id }, Path.Combine(fixture, "backups")); } catch (InvalidOperationException) { replay = true; }
    Check(replay, "Aperçu environnement à usage unique");

    string db = Path.Combine(fixture, "sample.db");
    IntPtr handle = IntPtr.Zero;
    try
    {
        Check(sqlite3_open_v2(Encoding.UTF8.GetBytes(db + "\0"), out handle, 0x00000002 | 0x00000004, IntPtr.Zero) == 0, "Base SQLite fixture créée");
        Check(sqlite3_exec(handle, Encoding.UTF8.GetBytes("CREATE TABLE t(x BLOB); INSERT INTO t VALUES(randomblob(350000)); DELETE FROM t;\0"), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) == 0, "Base SQLite avec espace libre préparée");
    }
    finally { if (handle != IntPtr.Zero) sqlite3_close(handle); }
    File.SetLastWriteTimeUtc(db, DateTime.UtcNow.AddHours(-2));
    long before = new FileInfo(db).Length;
    var databases = new DatabaseCleanerService(fixture);
    var found = await databases.ScanAsync();
    Check(found.Count == 1 && found[0].Path == db && File.Exists(db), "Analyse SQLite en lecture seule");
    var dbResult = await databases.CleanAsync(new[] { found[0].Id }, Path.Combine(fixture, "backups"));
    Check(dbResult.Optimized == 1 && dbResult.Skipped == 0 && dbResult.BytesRecovered > 0 && new FileInfo(db).Length < before, "VACUUM appliqué uniquement à la fixture");
    Check(dbResult.Backups.Count == 1 && File.Exists(dbResult.Backups[0]), "Copie SQLite récupérable conservée");
    bool dbReplay = false; try { await databases.CleanAsync(new[] { found[0].Id }, Path.Combine(fixture, "backups")); } catch (InvalidOperationException) { dbReplay = true; }
    Check(dbReplay, "Aperçu SQLite à usage unique");
    using (var key = Registry.CurrentUser.CreateSubKey(privacyPath)!)
    {
        key.SetValue("a", "old-command", RegistryValueKind.String);
        key.SetValue("MRUList", "a", RegistryValueKind.String);
        key.SetValue("Preserve", "unrelated", RegistryValueKind.String);
    }
    var privacy = new PrivacyRegistryCleanerService(privacyPath);
    var registryItems = await privacy.ScanAsync();
    Check(registryItems.Count == 1 && registryItems[0].Count == 1, "Liste d’activité fixture détectée sans suppression");
    using (var key = Registry.CurrentUser.OpenSubKey(privacyPath, true)!) key.SetValue("a", "changed-command");
    var changed = await privacy.CleanAsync(new[] { registryItems[0].Id }, Path.Combine(fixture, "backups"));
    Check(changed.ClearedGroups == 0 && changed.SkippedGroups == 1, "Historique modifié depuis l’analyse conservé");
    registryItems = await privacy.ScanAsync();
    var cleared = await privacy.CleanAsync(new[] { registryItems[0].Id }, Path.Combine(fixture, "backups"));
    using (var key = Registry.CurrentUser.OpenSubKey(privacyPath)!)
        Check(cleared.ClearedGroups == 1 && key.GetValue("a") == null && key.GetValue("MRUList") == null && key.GetValue("Preserve") as string == "unrelated", "Seules les valeurs d’activité ciblées sont retirées");
    Check(cleared.Backups.Count == 1 && File.Exists(cleared.Backups[0]), "Liste du Registre sauvegardée avant effacement");
}
finally
{
    if (registryPath.StartsWith(@"Software\BastosCleanerFixture\", StringComparison.Ordinal)) Registry.CurrentUser.DeleteSubKeyTree(registryPath, false);
    if (privacyPath.StartsWith(@"Software\BastosCleanerFixture\", StringComparison.Ordinal)) Registry.CurrentUser.DeleteSubKeyTree(privacyPath, false);
}
Console.WriteLine($"PASS {checks} contrôles avancés. Sauvegardes fixture : {fixture}");

[DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
[DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr callback, IntPtr userData, IntPtr error);
[DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);

