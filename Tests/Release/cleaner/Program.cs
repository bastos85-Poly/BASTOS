using Bastos.Native.Services;
using System.Security.Cryptography;

string sandbox = Path.Combine(Path.GetTempPath(), "BASTOS-Cleaner-Fixture-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(sandbox);
int checks = 0;
void Check(bool value, string name) { if (!value) throw new Exception("FAIL: " + name); Console.WriteLine("PASS: " + name); checks++; }
string Make(string relative, string data = "temporary-data", int days = 10)
{
    string path = Path.Combine(sandbox, relative); Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, data);
    File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddDays(-days)); return path;
}
SystemCleanerService Service(string root = "cache", int limit = 100000) => new(new[] { new SystemCleanerService.Rule("temp", Path.Combine(sandbox, root)) }, maximumFiles: limit);
var s = Service();
string old = Make("cache/old.tmp"), fresh = Make("cache/new.tmp", days: 0), excluded = Make("cache/keep/keep.tmp"), outside = Make("personal/document.txt"), locked = Make("cache/locked.tmp");
string personalHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(outside)));
var scan = await s.ScanAsync(new[] { "temp" }, new[] { Path.GetDirectoryName(excluded)! }, 7);
Check(scan.Complete && scan.Files.Count == 2, "Age et exclusions exactes; seulement les deux anciens fichiers autorisés");
string sharedFile = Make("cache/shared.tmp");
using (var shared = new FileStream(sharedFile, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite | FileShare.Delete))
{
    var sharedScan = await Service().ScanAsync(new[] { "temp" }, new[] { Path.GetDirectoryName(excluded)! }, 0);
    Check(sharedScan.Files.Any(f => Path.GetFileName(f.FullPath) == "shared.tmp"), "Fichier de cache ouvert visible dans l’aperçu");
}
Check(scan.Files.All(f => f.Root == Path.Combine(sandbox, "cache")), "Périmètre explicite conservé dans aperçu");
Check(File.Exists(old) && File.Exists(locked), "Analyse en lecture seule");
bool immutable = false; try { ((IList<CleanerFile>)scan.Files).Clear(); } catch (NotSupportedException) { immutable = true; }
Check(immutable, "Aperçu non modifiable");
bool forged = false; try { await s.CleanAsync(new CleanerScan(scan.CreatedUtc, scan.Files, scan.Warnings, true), scan.Files.Select(f => f.Id)); } catch (InvalidOperationException) { forged = true; }
Check(forged, "Aperçu forgé rejeté");
bool unknown = false; try { await s.CleanAsync(scan, new[] { "unlisted" }); } catch (ArgumentException) { unknown = true; }
Check(unknown, "Identifiant hors aperçu rejeté");
using (var held = new FileStream(locked, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))
{
    var result = await s.CleanAsync(scan, scan.Files.Select(f => f.Id));
    Check(result.DeletedCount == 1 && result.BytesRemoved > 0 && result.Skipped == 1 && !File.Exists(old) && File.Exists(locked), "Suppression sélective confirmée et fichier utilisé conservé");
    Check(result.RemovedFileIds.Count == 1 && result.Errors.Count == 1, "Résultats détaillés exacts");
}
Check(File.Exists(fresh) && File.Exists(excluded) && Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(outside))) == personalHash, "Fichiers récents, exclus et extérieurs préservés");
bool replay = false; try { await s.CleanAsync(scan, Array.Empty<string>()); } catch (InvalidOperationException) { replay = true; }
Check(replay, "Ancien aperçu non rejouable");
string modified = Make("changed/a.tmp", "before"); var changedService = Service("changed"); var changed = await changedService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
DateTime stamp = File.GetLastWriteTimeUtc(modified); File.WriteAllText(modified, "AFTER!"); File.SetLastWriteTimeUtc(modified, stamp);
var kept = await changedService.CleanAsync(changed, changed.Files.Select(f => f.Id));
Check(kept.DeletedCount == 0 && kept.Skipped == 1 && File.Exists(modified), "Modification même taille/date détectée par SHA-256");
string cancelFile = Make("cancel/a.tmp"); var cancelService = Service("cancel"); var cancelScan = await cancelService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
using (var cts = new CancellationTokenSource()) { cts.Cancel(); var cancelled = await cancelService.CleanAsync(cancelScan, cancelScan.Files.Select(f => f.Id), token: cts.Token); Check(cancelled.Cancelled && cancelled.DeletedCount == 0 && File.Exists(cancelFile), "Annulation avant suppression respectée"); }
using (var cts = new CancellationTokenSource()) { cts.Cancel(); bool cancelled = false; try { await s.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0, token: cts.Token); } catch (OperationCanceledException) { cancelled = true; } Check(cancelled, "Analyse annulable"); }
Make("limited/a"); Make("limited/b"); var limitedService = Service("limited", 1); var limited = await limitedService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(!limited.Complete && limited.Warnings.Count > 0, "Inventaire borné, état incomplet explicite");
bool incomplete = false; try { await limitedService.CleanAsync(limited, limited.Files.Select(f => f.Id)); } catch (InvalidOperationException) { incomplete = true; }
Check(incomplete, "Nettoyage interdit sur inventaire interrompu par limite");
DateTime clock = DateTime.UtcNow; string expiredFile = Make("expired/a"); var expiredService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("temp", Path.Combine(sandbox, "expired")) }, () => clock);
var expired = await expiredService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0); clock = clock.AddHours(1);
bool stale = false; try { await expiredService.CleanAsync(expired, expired.Files.Select(f => f.Id)); } catch (InvalidOperationException) { stale = true; }
Check(stale && File.Exists(expiredFile), "Aperçu périmé refusé");
string filterDir = Path.Combine(sandbox, "filter"); Make("filter/cache.db"); string useful = Make("filter/document.txt"); var filterService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("temp", filterDir, "*.db", false) });
var filtered = await filterService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0); await filterService.CleanAsync(filtered, filtered.Files.Select(f => f.Id)); Check(File.Exists(useful), "Filtre de fichiers respecté");
// A directory junction can be created without symbolic-link privilege. It is confined to this fixture.
string linkRoot = Path.Combine(sandbox, "junction"), link = Path.Combine(linkRoot, "redirect"); Directory.CreateDirectory(linkRoot);
var psi = new System.Diagnostics.ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
psi.ArgumentList.Add("/d"); psi.ArgumentList.Add("/c"); psi.ArgumentList.Add("mklink"); psi.ArgumentList.Add("/J"); psi.ArgumentList.Add(link); psi.ArgumentList.Add(Path.GetDirectoryName(outside)!);
using (var process = System.Diagnostics.Process.Start(psi)!) { process.WaitForExit(); Check(process.ExitCode == 0, "Fixture jonction créée"); }
var junctionService = Service("junction"); var junctionScan = await junctionService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(junctionScan.Files.Count == 0 && File.Exists(outside), "Jonction non suivie pendant analyse");
var linkedRootService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("temp", link) }); var linkedRoot = await linkedRootService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(linkedRoot.Files.Count == 0 && linkedRoot.Warnings.Count > 0, "Racine redirigée refusée explicitement");
Directory.Delete(link); // Delete the link itself; never recurse into its target.
string raceFile = Make("race/nested/a.tmp", "before");
var raceService = Service("race"); var raceScan = await raceService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
string originalDirectory = Path.GetDirectoryName(raceFile)!; string movedDirectory = Path.Combine(sandbox, "race-preserved");
// Both resolved paths are verified inside the fixture before the move.
Check(Path.GetFullPath(originalDirectory).StartsWith(sandbox + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) && Path.GetFullPath(movedDirectory).StartsWith(sandbox + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "Déplacement de fixture borné");
Directory.Move(originalDirectory, movedDirectory);
psi.ArgumentList.Clear(); psi.ArgumentList.Add("/d"); psi.ArgumentList.Add("/c"); psi.ArgumentList.Add("mklink"); psi.ArgumentList.Add("/J"); psi.ArgumentList.Add(originalDirectory); psi.ArgumentList.Add(movedDirectory);
using (var process = System.Diagnostics.Process.Start(psi)!) { process.WaitForExit(); Check(process.ExitCode == 0, "Fixture ancêtre remplacé par jonction"); }
var raceResult = await raceService.CleanAsync(raceScan, raceScan.Files.Select(f => f.Id));
Check(raceResult.DeletedCount == 0 && raceResult.Skipped == 1 && File.Exists(Path.Combine(movedDirectory, "a.tmp")), "Ancêtre redirigé après aperçu refusé au nettoyage");
Directory.Delete(originalDirectory);
string replacement = Make("replace/a.tmp", "original"); var replacementService = Service("replace"); var replacementScan = await replacementService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
DateTime replacedStamp = File.GetLastWriteTimeUtc(replacement); string replacementCopy = replacement + ".new"; File.WriteAllText(replacementCopy, "original"); File.SetLastWriteTimeUtc(replacementCopy, replacedStamp); File.Move(replacementCopy, replacement, true);
var replaced = await replacementService.CleanAsync(replacementScan, replacementScan.Files.Select(f => f.Id));
Check(replaced.DeletedCount == 0 && File.Exists(replacement), "Identité native changée malgré contenu/date identiques conservée");
Directory.CreateDirectory(Path.Combine(sandbox, "many-dirs", "one", "two")); var dirsService = Service("many-dirs", 1); var dirsScan = await dirsService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(!dirsScan.Complete && dirsScan.Warnings.Any(w => w.Contains("dossiers")), "Traversal des dossiers vide lui aussi borné");
string recentFile = Make("recency/recent.tmp", days: 0), oldFile = Make("recency/old.tmp", days: 2);
var recentService = Service("recency"); var recentScan = await recentService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(recentScan.Files.Count == 1 && Path.GetFullPath(recentScan.Files[0].FullPath).Equals(Path.GetFullPath(oldFile), StringComparison.OrdinalIgnoreCase), "Dernière heure protégée même sans filtre d’âge utilisateur");
string aged = Make("min-age/old.tmp", days: 20), tooYoung = Make("min-age/young.tmp", days: 10);
var minAgeService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("temp", Path.Combine(sandbox, "min-age"), MinAgeDays: 14) });
var minAgeScan = await minAgeService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0);
Check(minAgeScan.Files.Count == 1 && Path.GetFullPath(minAgeScan.Files[0].FullPath).Equals(Path.GetFullPath(aged), StringComparison.OrdinalIgnoreCase), "Âge minimum spécifique de la cible conservé");
var minAgeResult = await minAgeService.CleanAsync(minAgeScan, minAgeScan.Files.Select(f => f.Id));
Check(minAgeResult.DeletedCount == 1 && File.Exists(tooYoung), "Seule cible suffisamment ancienne supprimée");
var catalog = new SystemCleanerService().Catalog;
Check(catalog.Count == 20 && catalog.Select(c => c.Id).Distinct().Count() == 20 && catalog.All(c => c.DefaultSelected), "Catalogue 20 catégories analysées par défaut");
string webviewRoot = Path.Combine(sandbox, "webview", "TestApp", "EBWebView", "Default");
Directory.CreateDirectory(Path.Combine(webviewRoot, "Cache"));
Directory.CreateDirectory(Path.Combine(webviewRoot, "IndexedDB", "Cache"));
Directory.CreateDirectory(Path.Combine(sandbox, "webview", "Unrelated", "Cache"));
var webviewRules = new List<SystemCleanerService.Rule>();
SystemCleanerService.AddWebView2Rules(webviewRules, Path.Combine(sandbox, "webview"));
Check(webviewRules.Any(r => r.Root == Path.Combine(webviewRoot, "Cache")) && !webviewRules.Any(r => r.Root.Contains("IndexedDB") || r.Root.Contains("Unrelated")), "WebView2 limité aux caches sous EBWebView, stockage de profil conservé");
string updaterRoot=Path.Combine(sandbox,"app-updater"), updaterFile=Make("app-updater/installer.exe", days: 20);
var updaterService=new SystemCleanerService(new[] { new SystemCleanerService.Rule("apps", updaterRoot, "installer.exe", false, 14) });
var updaterScan=await updaterService.ScanAsync(new[] { "apps" }, Array.Empty<string>(), 0);
Check(updaterScan.Files.Count==1,"Ancien paquet de mise à jour proposé");
Directory.CreateDirectory(Path.Combine(updaterRoot,"pending"));
var updaterClean=await updaterService.CleanAsync(updaterScan,updaterScan.Files.Select(f=>f.Id));
Check(updaterClean.DeletedCount==0&&File.Exists(updaterFile),"Nouvelle mise à jour en attente protège le paquet à l’exécution");
string links = Path.Combine(sandbox, "shortcuts"); Directory.CreateDirectory(links);
var shellType = Type.GetTypeFromProgID("WScript.Shell")!; object shell = Activator.CreateInstance(shellType)!;
void Shortcut(string filename, string target)
{
    string shortcutPath = Path.Combine(links, filename);
    object shortcut = shellType.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath })!;
    shortcut.GetType().InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { target });
    shortcut.GetType().InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, shortcut, null);
    System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shortcut);
    File.SetLastWriteTimeUtc(shortcutPath, DateTime.UtcNow.AddDays(-2));
}
string missingTarget = Path.Combine(sandbox, "not-installed.exe"); Shortcut("broken.lnk", missingTarget); Shortcut("working.lnk", outside);
System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
var linkService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("shortcuts", links, "*.lnk") });
var linkScan = await linkService.ScanAsync(new[] { "shortcuts" }, Array.Empty<string>(), 0);
Check(linkScan.Files.Count == 1 && Path.GetFileName(linkScan.Files[0].FullPath) == "broken.lnk", "Raccourci cassé détecté et raccourci fonctionnel conservé");
var linkResult = await linkService.CleanAsync(linkScan, linkScan.Files.Select(f => f.Id));
Check(linkResult.DeletedCount == 1 && !File.Exists(Path.Combine(links, "broken.lnk")) && File.Exists(Path.Combine(links, "working.lnk")), "Seul le raccourci cassé de la fixture est retiré");
string firstRoot = Path.Combine(sandbox, "options", "first"), secondRoot = Path.Combine(sandbox, "options", "second");
Make("options/first/one.tmp"); Make("options/second/two.tmp");
var optionService = new SystemCleanerService(new[] { new SystemCleanerService.Rule("temp", firstRoot), new SystemCleanerService.Rule("temp", secondRoot) });
var firstOption = optionService.Options.Single(o => o.Path == firstRoot);
var optionScan = await optionService.ScanAsync(new[] { "temp" }, Array.Empty<string>(), 0, optionIds: new[] { firstOption.Id });
Check(optionScan.Files.Count == 1 && Path.GetFileName(optionScan.Files[0].FullPath) == "one.tmp", "Sous-option restreint réellement l’analyse aux chemins choisis");
Console.WriteLine($"PASS {checks} contrôles. Fixtures conservées : {sandbox}");





