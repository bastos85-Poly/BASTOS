using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Bastos.Native.Models;
using Bastos.Native.Services;

string root = Path.GetFullPath(args[0]);
Directory.CreateDirectory(root);
string sourceRoot=Environment.GetEnvironmentVariable("BASTOS_TEST_SOURCE") ?? throw new InvalidOperationException("BASTOS_TEST_SOURCE is required for real worker tests.");
string fixtureRoot=Environment.GetEnvironmentVariable("BASTOS_RELEASE_FIXTURES") ?? Path.GetFullPath("work");
int passed = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception("FAIL: " + name); Console.WriteLine("OK: " + name); passed++; }
JsonElement Json(object value) => JsonSerializer.SerializeToElement(value);
async Task<OperationResult> Scenario(string name, Func<string, Dictionary<string, object>> payload, CommandResult process,
    OperationState expected, string code, Func<JsonElement, Task<OperationVerification>> verifier = null, bool malformed = false)
{
    var engine = new VerifiedOperationService(Path.Combine(root, name), async (script, argv) =>
    {
        string id = argv[Array.IndexOf(argv.ToArray(), "-OperationId") + 1];
        string report = argv[Array.IndexOf(argv.ToArray(), "-ResultPath") + 1];
        if (malformed) await File.WriteAllTextAsync(report, "{truncated");
        else if (payload != null) await File.WriteAllTextAsync(report, JsonSerializer.Serialize(payload(id)));
        return process;
    }, (area, message, error) => { });
    var result = await engine.RunAsync(name, "test.ps1", Array.Empty<string>(), verifier ?? (_ => Task.FromResult(new OperationVerification(true, "Vérifié.", Array.Empty<OperationCheck>()))));
    Check(result.State == expected && result.ErrorCode == code && result.Success == (expected is OperationState.Succeeded or OperationState.Partial), name);
    var stored = JsonDocument.Parse(await File.ReadAllTextAsync(result.JournalPath)).RootElement;
    Check(stored.GetProperty("OperationId").GetString() == result.OperationId && stored.GetProperty("State").GetString() == expected.ToString(), name + " journal corrélé");
    return result;
}
Dictionary<string, object> Valid(string id) => new() { ["SchemaVersion"] = 1, ["OperationId"] = id, ["Success"] = true };
var ok = new CommandResult(true, 0, "", "");
await Scenario("success", Valid, ok, OperationState.Succeeded, "");
await Scenario("missing-report", null, ok, OperationState.Unconfirmed, "REPORT_MISSING");
await Scenario("invalid-json", null, ok, OperationState.Unconfirmed, "REPORT_UNREADABLE", malformed: true);
await Scenario("missing-success", id => new() { ["SchemaVersion"] = 1, ["OperationId"] = id }, ok, OperationState.Unconfirmed, "REPORT_INVALID");
await Scenario("stale-report", id => Valid("another-operation"), ok, OperationState.Unconfirmed, "REPORT_INVALID");
await Scenario("future-schema", id => { var data = Valid(id); data["SchemaVersion"] = 99; return data; }, ok, OperationState.Unconfirmed, "REPORT_INVALID");
await Scenario("wrong-schema-type", id => { var data = Valid(id); data["SchemaVersion"] = "1"; return data; }, ok, OperationState.Unconfirmed, "REPORT_INVALID");
await Scenario("worker-exit-failed", Valid, new(false, 1, "", "test failure"), OperationState.Failed, "WORKER_FAILED");
await Scenario("reported-failure", id => { var data = Valid(id); data["Success"] = false; data["Message"] = "read failure"; return data; }, ok, OperationState.Failed, "WORKER_FAILED");
await Scenario("admin-cancelled", null, new(false, 1223, "", "cancelled"), OperationState.Cancelled, "ADMIN_CANCELLED");
await Scenario("timeout-stopped", null, new(false, -2, "", "timeout"), OperationState.TimedOut, "TIMEOUT_STOPPED");
await Scenario("timeout-unknown", Valid, new CommandResult(false, -2, "", "timeout") { ProcessStopped = false }, OperationState.Unconfirmed, "TIMEOUT_UNCONFIRMED");
await Scenario("verification-failed", Valid, ok, OperationState.Unconfirmed, "VERIFICATION_FAILED", _ => Task.FromResult(new OperationVerification(false, "Fichier absent.", new[] { new OperationCheck("file", false, "absent") })));
await Scenario("verifier-exception", Valid, ok, OperationState.Unconfirmed, "VERIFICATION_ERROR", _ => throw new IOException("locked"));
bool launched = false;
string notDirectory = Path.Combine(root, "not-a-directory"); await File.WriteAllTextAsync(notDirectory, "file");
var blocked = await new VerifiedOperationService(notDirectory, (script, argv) => { launched = true; return Task.FromResult(ok); }, (_, _, _) => { })
    .RunAsync("blocked", "test.ps1", Array.Empty<string>(), _ => Task.FromResult(new OperationVerification(true, "", Array.Empty<OperationCheck>())));
Check(!launched && blocked.ErrorCode == "JOURNAL_UNWRITABLE" && !blocked.Success, "journal refusé : aucun worker lancé");
var workerStarted = new TaskCompletionSource();
var workerMayFinish = new TaskCompletionSource();
int invocations = 0;
var serializedEngine = new VerifiedOperationService(Path.Combine(root, "concurrent"), async (script, argv) =>
{
    invocations++; workerStarted.TrySetResult(); await workerMayFinish.Task;
    string id = argv[Array.IndexOf(argv.ToArray(), "-OperationId") + 1];
    string path = argv[Array.IndexOf(argv.ToArray(), "-ResultPath") + 1];
    await File.WriteAllTextAsync(path, JsonSerializer.Serialize(Valid(id))); return ok;
}, (_, _, _) => { });
Task<OperationResult> StartSame() => serializedEngine.RunAsync("same", "same.ps1", Array.Empty<string>(), _ => Task.FromResult(new OperationVerification(true, "OK", Array.Empty<OperationCheck>())));
var first = StartSame(); await workerStarted.Task;
var duplicate = await StartSame();
Check(duplicate.ErrorCode == "OPERATION_BUSY" && invocations == 1, "deux lancements concurrents : second refusé");
workerMayFinish.SetResult(); Check((await first).Success && (await StartSame()).Success, "action relançable après fin confirmée");
int unknownLaunches = 0;
var unknownEngine = new VerifiedOperationService(Path.Combine(root, "unknown-running"), (script, argv) =>
{ unknownLaunches++; return Task.FromResult(new CommandResult(false, -2, "", "") { ProcessStopped = false }); }, (_, _, _) => { });
Task<OperationResult> StartUnknown() => unknownEngine.RunAsync("unknown", "same.ps1", Array.Empty<string>(), _ => Task.FromResult(new OperationVerification(true, "", Array.Empty<OperationCheck>())));
await StartUnknown(); var refusedRetry = await StartUnknown();
Check(refusedRetry.ErrorCode == "OPERATION_BUSY" && unknownLaunches == 1, "arrêt non confirmé : pas de relance dans cette session");

Dictionary<string, object> Hardware(string id, bool partial = false, bool empty = false)
{
    var data = Valid(id);
    data["Report"] = new { System = new { }, Motherboard = new { }, Summary = new { DetectedDevices = 1, ProblemCount = 0 },
        Processors = empty ? Array.Empty<object>() : new object[] { new { Name = "Test CPU" } }, Graphics = Array.Empty<object>(), Storage = Array.Empty<object>(),
        Network = Array.Empty<object>(), Audio = Array.Empty<object>(), ProblemDevices = Array.Empty<object>(),
        CollectionErrors = partial ? new object[] { new { Category = "CIM", Message = "Unavailable" } } : Array.Empty<object>() };
    data["Recommendations"] = Array.Empty<object>();
    return data;
}
await Scenario("hardware-valid", id => Hardware(id), ok, OperationState.Succeeded, "", OperationVerifiers.HardwareAsync);
await Scenario("hardware-partial", id => Hardware(id, true), ok, OperationState.Partial, "", OperationVerifiers.HardwareAsync);
await Scenario("hardware-empty-failed", id => Hardware(id, true, true), ok, OperationState.Unconfirmed, "VERIFICATION_FAILED", OperationVerifiers.HardwareAsync);
await Scenario("hardware-incomplete", Valid, ok, OperationState.Unconfirmed, "VERIFICATION_FAILED", OperationVerifiers.HardwareAsync);

string binary = Path.Combine(root, "fixture.exe"); await File.WriteAllBytesAsync(binary, new byte[] { 77, 90, 1, 2, 3 });
Dictionary<string, object> Rufus(string id)
{
    var data = Valid(id); data["Path"] = binary; data["FileLength"] = 5; data["ExpectedLength"] = 5;
    data["Sha256"] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(binary))); data["SignatureStatus"] = "Valid"; data["SignerSubject"] = "CN=Akeo Consulting"; return data;
}
await Scenario("rufus-proof-fixture", Rufus, ok, OperationState.Succeeded, "", payload => OperationVerifiers.RufusAsync(binary, payload));
foreach (string field in new[] { "Path", "FileLength", "ExpectedLength", "Sha256", "SignatureStatus", "SignerSubject" })
    await Scenario("rufus-invalid-" + field, id => { var data = Rufus(id); data[field] = field.Contains("Length") ? 999 : "invalid"; return data; }, ok, OperationState.Unconfirmed, "VERIFICATION_FAILED", payload => OperationVerifiers.RufusAsync(binary, payload));

var runner = new ProcessExecutionService();
string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
string sleepScript = Path.Combine(root, "sleep.ps1"); await File.WriteAllTextAsync(sleepScript, "param([string]$PidPath)\n[IO.File]::WriteAllText($PidPath,[string]$PID)\nStart-Sleep -Seconds 60");
foreach (bool stop in new[] { true, false })
{
    string pidFile = Path.Combine(root, "pid-" + stop + ".txt");
    // Exercise a real timeout even when the host execution policy blocks local scripts.
    var timeout = await runner.RunAsync(powershell, new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", sleepScript, "-PidPath", pidFile }, terminateOnTimeout: stop, timeoutOverride: TimeSpan.FromSeconds(8));
    Check(timeout.ExitCode == -2 && timeout.ProcessStopped == stop, "processus réel délai dépassé : arrêt demandé=" + stop);
    int pid = int.Parse(await File.ReadAllTextAsync(pidFile));
    try { using var process = Process.GetProcessById(pid); if (!stop) { process.Kill(true); await process.WaitForExitAsync(); } else Check(process.HasExited, "arrêt du processus confirmé"); }
    catch (ArgumentException) { Check(stop, "processus arrêté absent de la liste"); }
}

// Real opted-in workers, never launch downloaded software or change a disk.
if (args.Contains("--real"))
{
    string originalSource = Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_SOURCE")!, "InstallerScripts");
    string source = Path.Combine(root, "real-workers");
    Directory.CreateDirectory(source);
    foreach (string name in new[] { "Download-BASTOS-Rufus.ps1", "Hardware-Analysis-Worker.ps1", "Bastos.Operation.psm1", "Driver-Recommendation-Service.psm1" })
        File.Copy(Path.Combine(originalSource, name), Path.Combine(source, name), true);
    File.Copy(Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_RUNTIME")!,"Official-Sources.json"), Path.Combine(source, "Official-Sources.json"), true);
    var engine = new VerifiedOperationService(Path.Combine(root, "real"),
        (script, argv) => runner.RunAsync(powershell, new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(source, script) }.Concat(argv), timeoutMinutes: 20, terminateOnTimeout: true),
        (area, message, error) => Console.WriteLine(message));
    foreach (string scope in new[] { "Graphics", "Full" })
    {
        var result = await engine.RunAsync("Analyse réelle " + scope, "Hardware-Analysis-Worker.ps1", new[] { "-Scope", scope }, OperationVerifiers.HardwareAsync);
        Check(result.Success, "analyse réelle " + scope + " : " + result.Message + " — " + result.JournalPath);
    }
    string rufusPath = Path.Combine(root, "real-rufus", "rufus.exe");
    var rufusResult = await engine.RunAsync("Rufus réel sans exécution", "Download-BASTOS-Rufus.ps1", new[] { "-OutputPath", rufusPath }, payload => OperationVerifiers.RufusAsync(rufusPath, payload));
    Check(rufusResult.Success, "Rufus réel signé, empreinte relue, aucun lancement : " + rufusResult.Message + " — " + rufusResult.JournalPath);
}
// Stage 2: exercise production cleanup in isolated TEMP roots, never the user's TEMP.
string fixtures = Path.Combine(root, "cleanup-fixtures");
string tempRoot = Path.Combine(fixtures, "user", "Temp"), windowsRoot = Path.Combine(fixtures, "windows");
Directory.CreateDirectory(tempRoot); Directory.CreateDirectory(Path.Combine(windowsRoot, "Temp"));
string oldFile = Path.Combine(tempRoot, "old.bin"), recentFile = Path.Combine(tempRoot, "recent.bin"), lockedFile = Path.Combine(tempRoot, "locked.bin");
await File.WriteAllBytesAsync(oldFile, new byte[100]); await File.WriteAllBytesAsync(recentFile, new byte[200]); await File.WriteAllBytesAsync(lockedFile, new byte[300]);
File.SetLastWriteTimeUtc(oldFile, DateTime.UtcNow.AddDays(-3)); File.SetLastWriteTimeUtc(lockedFile, DateTime.UtcNow.AddDays(-3));
string outside = Path.Combine(fixtures, "outside"); Directory.CreateDirectory(outside);
string sentinel = Path.Combine(outside, "sentinel.bin"); await File.WriteAllTextAsync(sentinel, "keep"); File.SetLastWriteTimeUtc(sentinel, DateTime.UtcNow.AddDays(-3));
string powershell5 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
string junction = Path.Combine(tempRoot, "redirected");
if (!Directory.Exists(junction))
{
    var linkInfo = new ProcessStartInfo(powershell5) { UseShellExecute=false, CreateNoWindow=true };
    foreach (string value in new[] { "-NoProfile", "-Command", "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:BASTOS_TEST_LINK -Target $env:BASTOS_TEST_TARGET | Out-Null" }) linkInfo.ArgumentList.Add(value);
    linkInfo.Environment["BASTOS_TEST_LINK"] = junction; linkInfo.Environment["BASTOS_TEST_TARGET"] = outside;
    using var linkProcess = Process.Start(linkInfo)!; await linkProcess.WaitForExitAsync();
    if (linkProcess.ExitCode != 0) throw new Exception("Fixture junction creation failed");
}
string installerScripts = Path.Combine(root, "step2-workers"); Directory.CreateDirectory(installerScripts);
foreach (string name in new[] { "Cleanup-BASTOS-Temp.ps1", "Bastos.Operation.psm1", "Open-BASTOS-OfficialDriver.ps1", "Driver-Recommendation-Service.psm1" })
    File.Copy(Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_SOURCE")!, "InstallerScripts", name), Path.Combine(installerScripts, name), true);
File.Copy(Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_RUNTIME")!,"Official-Sources.json"), Path.Combine(installerScripts, "Official-Sources.json"), true);
// Only replace the Windows TEMP environment lookup in the test copy; do not change SystemRoot of a running CLR.
string cleanupCopy = Path.Combine(installerScripts, "Cleanup-BASTOS-Temp.ps1");
File.WriteAllText(cleanupCopy, File.ReadAllText(cleanupCopy).Replace("$env:SystemRoot", "$env:BASTOS_TEST_WINDOWSROOT"));
async Task<CommandResult> Worker(string script, IReadOnlyList<string> argv)
{
    var psi = new ProcessStartInfo(powershell5) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardError=true, RedirectStandardOutput=true };
    foreach (string arg in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(Environment.GetEnvironmentVariable("BASTOS_TEST_SOURCE")!, "Tests", "Release", "engine", "IsolatedWorker.ps1"), Path.Combine(installerScripts, script) }.Concat(argv)) psi.ArgumentList.Add(arg);
    psi.Environment["TEMP"] = tempRoot; psi.Environment["TMP"] = tempRoot; psi.Environment["BASTOS_TEST_WINDOWSROOT"] = windowsRoot; psi.Environment["BASTOS_TEST_BROWSER_CAPTURE"] = Path.Combine(root, "browser-request.txt");
    using var process = Process.Start(psi)!;
    var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
    await process.WaitForExitAsync();
    return new(process.ExitCode == 0, process.ExitCode, await output, await error);
}
var cleanupEngine = new VerifiedOperationService(Path.Combine(root, "cleanup"), Worker, (_,_,_) => {});
var analysis = await cleanupEngine.RunAsync("Analyse", "Cleanup-BASTOS-Temp.ps1", new[] { "-AnalyzeOnly" }, payload => OperationVerifiers.CleanupAsync(true, payload));
Check(analysis.State == OperationState.Succeeded, "cleanup analyse worker réel : " + analysis.TechnicalDetail + analysis.Message);
Check(analysis.Payload!.Value.GetProperty("EligibleBytes").GetInt64() == 400 && analysis.Payload.Value.GetProperty("Bytes").GetInt64() == 600, "cleanup ne compte pas les fichiers récents comme récupérables");
Check(File.Exists(oldFile) && File.Exists(recentFile), "cleanup analyse ne supprime rien");
using (var locked = new FileStream(lockedFile, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
{
    var clean = await cleanupEngine.RunAsync("Nettoyage", "Cleanup-BASTOS-Temp.ps1", Array.Empty<string>(), payload => OperationVerifiers.CleanupAsync(false, payload));
    Check(clean.State == OperationState.Partial, "cleanup fichier verrouillé = résultat partiel : " + clean.Message);
    Check(clean.Payload!.Value.GetProperty("RemovedBytes").GetInt64() == 100 && clean.Payload.Value.GetProperty("Failed").GetInt64() == 1, "cleanup compte seulement les suppressions confirmées");
    Check(!File.Exists(oldFile) && File.Exists(recentFile) && File.Exists(lockedFile) && File.Exists(sentinel), "cleanup conserve récent, verrouillé et hors cible");
}
var inconsistent = analysis.Payload!.Value.EnumerateObject().ToDictionary(x => x.Name, x => (object)x.Value.Clone()); inconsistent["RemovedBytes"] = 99999;
Check(!(await OperationVerifiers.CleanupAsync(true, Json(inconsistent))).Valid, "cleanup rejette compteurs incohérents");
string url = "https://www.nvidia.com/fr-fr/drivers/";
JsonElement Driver(string final) => Json(new { Url=final, RequestedUrl=url, LaunchRequested=true });
Check((await OperationVerifiers.OfficialDriverAsync(url, "", new[] { "nvidia.com" }, Driver(url))).Valid, "pilote lien officiel vérifié");
foreach (string rejected in new[] { "https://nvidia.com.attacker.test/", "http://www.nvidia.com/", "https://user@nvidia.com/", "https://nvidia.com:444/" })
    Check(!(await OperationVerifiers.OfficialDriverAsync(url, "", new[] { "nvidia.com" }, Driver(rejected))).Valid, "pilote refuse " + rejected);
var denied = await new VerifiedOperationService(Path.Combine(root, "driver-denied"), Worker, (_,_,_)=>{})
    .RunAsync("Lien interdit", "Open-BASTOS-OfficialDriver.ps1", new[] { "-OfficialUrl", "https://nvidia.com.attacker.test/" }, _ => throw new Exception("verifier must not run"));
Check(denied.State == OperationState.Failed && denied.Payload!.Value.GetProperty("Success").GetBoolean() == false, "worker pilote refuse domaine non officiel avant ouverture");

Check(analysis.Payload!.Value.GetProperty("SkippedLinks").GetInt64() > 0 && File.Exists(sentinel), "cleanup ignore jonction et conserve sa cible");
var driverEngine = new VerifiedOperationService(Path.Combine(root, "driver-allowed"), Worker, (_,_,_)=>{});
var opened = await driverEngine.RunAsync("Pilote officiel", "Open-BASTOS-OfficialDriver.ps1", new[] { "-OfficialUrl", url },
    payload => OperationVerifiers.OfficialDriverAsync(url, "", new[] { "nvidia.com" }, payload));
Check(opened.State == OperationState.Succeeded && await File.ReadAllTextAsync(Path.Combine(root, "browser-request.txt")) == url,
    "worker pilote succès réel, ouverture navigateur simulée : " + opened.Message + opened.TechnicalDetail);
Check(!opened.Message.Contains("Page officielle ouverte"), "pilote ne prétend pas avoir chargé la page");
// Stage 3: native actions use exactly the same journal and verification path.
string nativeLogs = Path.Combine(root, "native");
int powershellCalls = 0;
var nativeEngine = new VerifiedOperationService(nativeLogs, (_,_) => { powershellCalls++; throw new Exception("No worker expected"); }, (_,_,_)=>{});
OperationVerification Verified() => new(true, "Vérifié.", Array.Empty<OperationCheck>());
Task<OperationResult> Native(string key, Func<IProgress<WorkerProgress>,Task<NativeOperationReport>> action, Func<JsonElement,Task<OperationVerification>> verify = null, IProgress<WorkerProgress> progress = null)
    => nativeEngine.RunNativeAsync(key,key,action,verify ?? (_=>Task.FromResult(Verified())),progress);
var noData = new Dictionary<string,object?>();
bool journalExistsBeforeAction = false;
var nativeOk = await Native("native-success", _ => {
    journalExistsBeforeAction = Directory.GetFiles(Path.Combine(nativeLogs,"Operations"),"*.operation.json").Any(file => File.ReadAllText(file).Contains("Running"));
    return Task.FromResult(new NativeOperationReport(true,"ok",new Dictionary<string,object?> { ["OperationId"]="forged", ["Success"]=false, ["SchemaVersion"]=999 }));
});
Check(journalExistsBeforeAction && nativeOk.State == OperationState.Succeeded && nativeOk.ExecutionKind == "Native" && nativeOk.WorkerExitCode == null, "natif journal créé avant action, aucun faux code de processus");
Check(nativeOk.Payload!.Value.GetProperty("OperationId").GetString() == nativeOk.OperationId && nativeOk.Payload.Value.GetProperty("Success").GetBoolean(), "natif enveloppe autoritaire corrélée");
var failedNative = await Native("native-failure", _=>Task.FromResult(new NativeOperationReport(false,"Message utile",noData,"EXPECTED_FAILURE","technical")));
Check(failedNative.State == OperationState.Failed && failedNative.ErrorCode == "EXPECTED_FAILURE" && failedNative.Message == "Message utile" && failedNative.TechnicalDetail == "technical", "natif échec explicite et détail conservé");
var throwingNative = await Native("native-exception", _=>throw new IOException("unexpected"));
Check(throwingNative.State == OperationState.Unconfirmed, "natif exception inattendue ne déclare pas un succès");
var invalidNative = await Native("native-invalid", _=>Task.FromResult(new NativeOperationReport(true,"ok",noData)), _=>Task.FromResult(new OperationVerification(false,"Preuve invalide",Array.Empty<OperationCheck>())));
Check(invalidNative.State == OperationState.Unconfirmed, "natif vérification négative ne déclare pas un succès");
bool nativeLaunched = false;
var noJournalNative = await new VerifiedOperationService(notDirectory,(_,_)=>throw new Exception(),(_,_,_)=>{})
    .RunNativeAsync("blocked","blocked",_=>{nativeLaunched=true;return Task.FromResult(new NativeOperationReport(true,"",noData));},_=>Task.FromResult(Verified()));
Check(!nativeLaunched && noJournalNative.ErrorCode == "JOURNAL_UNWRITABLE", "natif journal inaccessible : aucune action lancée");
var nativeStarted = new TaskCompletionSource(); var nativeFinish = new TaskCompletionSource(); int nativeCount = 0;
Task<OperationResult> ConcurrentNative() => Native("same-native",async _=>{nativeCount++; nativeStarted.TrySetResult();await nativeFinish.Task;return new(true,"ok",noData);});
var nativeFirst = ConcurrentNative(); await nativeStarted.Task; var nativeDuplicate = await ConcurrentNative();
Check(nativeDuplicate.ErrorCode == "OPERATION_BUSY" && nativeCount == 1, "natif double clic concurrent bloqué");
nativeFinish.SetResult(); Check((await nativeFirst).Success && (await ConcurrentNative()).Success, "natif relance possible après fin");
bool validated = false, premature100 = false; var percentages = new List<int>();
var nativeProgress = new ImmediateProgress(p=>{ percentages.Add(p.Percent); if (p.Percent == 100 && !validated) premature100 = true; });
await Native("native-progress", p=>{p.Report(new(100,"Avant vérification",""));return Task.FromResult(new NativeOperationReport(true,"ok",noData));},
    _=>{validated=true;return Task.FromResult(Verified());},nativeProgress);
Check(!premature100 && percentages.Contains(99) && percentages.Last() == 100, "natif progression 100 uniquement après vérification");

string driverConfig = Path.Combine(root,"native-sources.json");
await File.WriteAllTextAsync(driverConfig, "{\"allowedDomains\":[\"nvidia.com\",\"intel.com\"]}");
int browserCalls = 0, clipboardCalls = 0; string browserUrl = "";
var nativeDriver = new OfficialDriverService(driverConfig, value=>{browserCalls++;browserUrl=value;},_=>clipboardCalls++);
Task<OperationResult> DriverNative(string address,string strategy="",string term="") => Native("driver-"+address+strategy,
    p=>nativeDriver.ExecuteAsync(address,strategy,term,p), payload=>OperationVerifiers.OfficialDriverAsync(address,strategy,new[]{"nvidia.com","intel.com"},payload));
foreach (string address in new[] { "https://nvidia.com.attacker.test/", "http://nvidia.com/", "https://user@nvidia.com/", "https://nvidia.com:444/", "file:///C:/Windows/", "not a url" })
{
    var refused = await DriverNative(address,"NVIDIA_LATEST_GEFORCE","must not copy");
    Check(refused.State == OperationState.Failed && refused.ErrorCode == "DRIVER_URL_REFUSED" && browserCalls == 0 && clipboardCalls == 0, "pilote C# refuse avant navigateur/presse-papiers : " + address);
}
var nativeOpened = await DriverNative("https://www.intel.com/content/www/fr/fr/download-center/home.html","","Test model");
Check(nativeOpened.Success && browserCalls == 1 && clipboardCalls == 1 && browserUrl.Contains("intel.com"), "pilote C# ouvre lien officiel et copie recherche");
var nativeNvidia = await DriverNative("https://www.nvidia.com/","nvidia_latest_geforce");
Check(nativeNvidia.Success && browserUrl == OfficialDriverService.NvidiaDriversUrl, "pilote C# résolution NVIDIA conservée sans dépendance PowerShell");
var brokenBrowser = new OfficialDriverService(driverConfig,_=>throw new System.ComponentModel.Win32Exception("no browser"));
var browserFailure = await Native("browser-failure",p=>brokenBrowser.ExecuteAsync(url,"","",p));
Check(browserFailure.State == OperationState.Failed && browserFailure.ErrorCode == "BROWSER_OPEN_FAILED", "pilote C# erreur navigateur compréhensible");
var missingSources = new OfficialDriverService(Path.Combine(root,"missing-config.json"),_=>throw new Exception("must not open"));
var sourcesFailure = await Native("missing-sources",p=>missingSources.ExecuteAsync(url,"","",p));
Check(sourcesFailure.ErrorCode == "OFFICIAL_SOURCES_UNAVAILABLE", "pilote C# sources absentes : refus avant ouverture");
var clipboardUnavailable = new OfficialDriverService(driverConfig,_=>{},_=>throw new InvalidOperationException("clipboard busy"));
var clipboardResult = await Native("clipboard-unavailable",p=>clipboardUnavailable.ExecuteAsync(url,"","model",p));
Check(clipboardResult.Success && !clipboardResult.Payload!.Value.GetProperty("SearchTermCopied").GetBoolean(), "pilote C# presse-papiers indisponible sans faux échec navigateur");

async Task<OperationResult> NetworkScenario(string name, Func<int,NetworkProbeReply> reply)
{
    int index = 0;
    var diagnostics = new NetworkDiagnosticsService((host, timeout)=> {
        if (host != "1.1.1.1" || timeout != 1000) throw new Exception("Unexpected target");
        return Task.FromResult(reply(++index));
    });
    return await Native(name,diagnostics.ExecuteAsync,OperationVerifiers.NetworkAsync);
}
var networkAll = await NetworkScenario("network-all",i=>new("Success",i*10));
Check(networkAll.State == OperationState.Succeeded && networkAll.Message.Contains("8/8") && networkAll.Message.Contains("45") && networkAll.Message.Contains("80 ms"), "réseau C# 8 réponses : statistiques vérifiées");
var networkLoss = await NetworkScenario("network-loss",i=>i%2 == 0 ? new("TimedOut",null) : new("Success",10));
Check(networkLoss.State == OperationState.Partial && networkLoss.Message.Contains("4/8") && networkLoss.Message.Contains("50"), "réseau C# pertes : résultat partiel");
var networkNone = await NetworkScenario("network-none",i=>new("TimedOut",null));
Check(networkNone.State == OperationState.Partial && networkNone.Message.Contains("0/8") && networkNone.Message.Contains("ne suffit pas"), "réseau C# zéro réponse ne prétend pas à une panne Internet");
var networkErrors = await NetworkScenario("network-errors",i=>throw new System.Net.NetworkInformation.PingException("denied"));
Check(networkErrors.State == OperationState.Failed && networkErrors.ErrorCode == "ICMP_UNAVAILABLE", "réseau C# erreurs ICMP : échec explicite");
foreach (var badReply in new[] { new NetworkProbeReply("Success",-1), new NetworkProbeReply("Success",null), new NetworkProbeReply("TimedOut",50), new NetworkProbeReply("invented",null) })
{
    var incoherentNetwork = await NetworkScenario("network-invalid-"+badReply.Status+badReply.RoundtripMs,i=>badReply);
    Check(incoherentNetwork.State == OperationState.Unconfirmed, "réseau C# réponse incohérente refusée : " + badReply);
}
var localPing = await NetworkDiagnosticsService.SendAsync("127.0.0.1",1000);
Check(localPing.Status == "Success" && localPing.RoundtripMs >= 0, "réseau C# vrai ping local sans accès Internet");
Check(powershellCalls == 0, "toutes les nouvelles actions natives sans worker PowerShell");

// Stage 4: registry presence, signed bootstrapper and installer lifecycle.
foreach (string versionText in new[] { "", "0.0.0.0", "garbage", "-1.2.3.4" })
    Check(!WebView2RuntimeService.IsInstalledVersion(versionText), "WebView2 refuse version invalide : " + versionText);
Check(WebView2RuntimeService.IsInstalledVersion("150.0.1.2"), "WebView2 accepte version officielle non nulle");
var actualWebViewDownload = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(fixtureRoot,"webview4-download.json"))).RootElement.Clone();
string actualCacheRoot = Path.GetFullPath(Path.Combine(fixtureRoot,"webview4-real-download/BASTOS/Tools/WebView2"));
Check((await OperationVerifiers.WebView2BootstrapperAsync(actualCacheRoot,actualWebViewDownload)).Valid, "WebView2 téléchargement Microsoft réel : taille, signature rapportée et SHA relue, aucune exécution");
Check(!(await OperationVerifiers.WebView2Async(actualCacheRoot,()=>null,actualWebViewDownload)).Valid, "WebView2 téléchargement seul ne prouve pas une installation");
Dictionary<string,object?> WebViewReport(string status="AlreadyInstalled",bool started=false) => new() { ["Status"]=status,["Version"]="150.0.1.2",["InstallerStarted"]=started,["InstallerExitCode"]=null };
Check((await OperationVerifiers.WebView2Async(actualCacheRoot,()=>"150.0.1.2",Json(WebViewReport()))).Valid, "WebView2 déjà présent : version indépendante correspondante");
Check((await OperationVerifiers.WebView2Async(actualCacheRoot,()=>"151.0.1.2",Json(WebViewReport()))).Valid, "WebView2 mise à jour parallèle plus récente acceptée");
foreach(string absentVersion in new[]{"", "0.0.0.0", "invalid", "149.0.1.2"})
    Check(!(await OperationVerifiers.WebView2Async(actualCacheRoot,()=>absentVersion,Json(WebViewReport()))).Valid, "WebView2 rapport succès mais version absente/incohérente refusé : " + absentVersion);
Check(!(await OperationVerifiers.WebView2Async(actualCacheRoot,()=>"150.0.1.2",Json(WebViewReport("Downloaded")))).Valid, "WebView2 état téléchargé refusé même si version présente");
var installedEvidence = actualWebViewDownload.EnumerateObject().ToDictionary(p=>p.Name,p=>(object?)p.Value.Clone());
installedEvidence["Status"]="Installed";installedEvidence["Version"]="150.0.1.2";installedEvidence["InstallerStarted"]=true;
Check((await OperationVerifiers.WebView2Async(actualCacheRoot,()=>"150.0.1.2",Json(installedEvidence))).Valid, "WebView2 installé : présence et bootstrapper contrôlés séparément");
foreach(var mutation in new Dictionary<string,object?> { ["SignatureStatus"]="NotSigned",["SignerSubject"]="O=Fake Microsoft Corporation",["Sha256"]="bad",["ExpectedLength"]=10,["FinalUrl"]="https://microsoft.com.attacker.test/file.exe" })
{
    var damaged=new Dictionary<string,object?>(installedEvidence);damaged[mutation.Key]=mutation.Value;
    Check(!(await OperationVerifiers.WebView2Async(actualCacheRoot,()=>"150.0.1.2",Json(damaged))).Valid,"WebView2 preuve incorrecte refusée : "+mutation.Key);
}
int pendingLaunches=0;
var pendingEngine=new VerifiedOperationService(Path.Combine(root,"pending-install"),async (_,argv)=>{
    pendingLaunches++;string[] values=argv.ToArray();string id=values[Array.IndexOf(values,"-OperationId")+1],file=values[Array.IndexOf(values,"-ResultPath")+1];
    var payload=Valid(id);payload["Success"]=false;payload["ActionCompletionUnconfirmed"]=true;
    await File.WriteAllTextAsync(file,JsonSerializer.Serialize(payload));return new(false,1,"","");
},(_,_,_)=>{});
Task<OperationResult> Pending() => pendingEngine.RunAsync("Installation en cours","install.ps1",Array.Empty<string>(),_=>throw new Exception("must not verify"));
var pendingInstall=await Pending(); var duplicateInstall=await Pending();
Check(pendingInstall.State==OperationState.Unconfirmed && pendingInstall.ActionCompletionUnconfirmed && pendingInstall.ProcessStopped,"WebView2 worker arrêté mais fin de l'installation non confirmée distingués");
Check(duplicateInstall.ErrorCode=="OPERATION_BUSY" && pendingLaunches==1,"WebView2 installation non confirmée : relance bloquée dans la session");

async Task<CommandResult> WebViewWorker(string scenario,IReadOnlyList<string> argv)
{
    var psi=new ProcessStartInfo(powershell5) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
    foreach(string value in new[]{"-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(sourceRoot,"Tests/Release/engine/WebViewWorkerHarness.ps1"),Path.Combine(sourceRoot,"InstallerScripts/Install-BASTOS-WebView2Runtime.ps1")}.Concat(argv)) psi.ArgumentList.Add(value);
    psi.Environment["BASTOS_WEBVIEW_SCENARIO"]=scenario;psi.Environment["BASTOS_WEBVIEW_CAPTURE"]=Path.Combine(root,"webview-mock-launches.txt");psi.Environment["LOCALAPPDATA"]=Path.Combine(root,"webview-local");
    using var process=Process.Start(psi)!;var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();await process.WaitForExitAsync();
    return new(process.ExitCode==0,process.ExitCode,await stdout,await stderr);
}
foreach(string scenario in new[]{"AlreadyInstalled","InvalidUri","ExistingActive","Installed","ExitFailure","InvalidSignature"})
{
    var engine=new VerifiedOperationService(Path.Combine(root,"webview-worker-"+scenario),(_,argv)=>WebViewWorker(scenario,argv),(_,_,_)=>{});
    var argv=scenario=="InvalidUri"?new[]{"-BootstrapperUri","https://evil.invalid/installer.exe"}:Array.Empty<string>();
    var outcome=await engine.RunAsync("WebView2 "+scenario,"Install-BASTOS-WebView2Runtime.ps1",argv,
        payload=>OperationVerifiers.WebView2Async(Path.Combine(root,"webview-local","BASTOS","Tools","WebView2"),()=>"150.0.1.2",payload));
    var expectedState=scenario is "AlreadyInstalled" or "Installed"?OperationState.Succeeded:scenario=="ExistingActive"?OperationState.Unconfirmed:OperationState.Failed;
    Check(outcome.State==expectedState,"WebView2 worker Windows PowerShell réel / scénario simulé "+scenario+" : "+outcome.Message+outcome.TechnicalDetail);
    if(scenario=="AlreadyInstalled") Check(!outcome.Payload!.Value.GetProperty("InstallerStarted").GetBoolean(),"WebView2 déjà présent : aucun installateur lancé");
}

// Deployment prerequisites and final ISO evidence. All ISO files below are synthetic fixtures.
string deploymentRoot=Path.Combine(root,"deployment-fixtures");Directory.CreateDirectory(deploymentRoot);
string oscdimgFixture=Path.Combine(deploymentRoot,"oscdimg.exe");await File.WriteAllBytesAsync(oscdimgFixture,new byte[]{77,90,1,2,3,4});
string oscdimgHash=Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(oscdimgFixture)));
Dictionary<string,object?> AdkReport(string version=AdkInstallationService.PatchedBase)=>new(){
 ["PatchArchiveSha256"]=AdkInstallationService.PatchArchiveSha256,["InstalledVersion"]=version,["Oscdimg"]=oscdimgFixture,["OscdimgLength"]=6,["OscdimgSha256"]=oscdimgHash,["SignatureStatus"]="Valid",["SignerSubject"]="O=Microsoft Corporation",
 ["ReadinessProfile"]=version==AdkInstallationService.CurrentRelease?"CurrentRelease":"PatchedBase",["PatchId"]=version==AdkInstallationService.CurrentRelease?"":"KB5101684",
 ["PatchStatus"]=version==AdkInstallationService.CurrentRelease?"DifferentRelease":"WindowsInstallerVerified",["RequiredPatches"]=new[]{new{PatchCode="{00000000-0000-0000-0000-000000000001}",ProductCode="{00000000-0000-0000-0000-000000000002}"}}};
Task<OperationVerification> VerifyAdk(Dictionary<string,object?> report,int? state=1,string version=AdkInstallationService.PatchedBase)=>DeploymentOperationVerifiers.AdkAsync(Json(report),()=>version,(_,_)=>state,new[]{oscdimgFixture},Path.GetFullPath(Path.Combine(fixtureRoot,"adk-reference-KB5101684.zip")));
Check((await VerifyAdk(AdkReport())).Valid,"ADK signature rapportée, taille, SHA relue, version et patch MSI verifies");
Check((await VerifyAdk(AdkReport(),2)).Valid,"ADK patch supersede accepte");
foreach(int? state in new int?[]{null,0,4,8}) Check(!(await VerifyAdk(AdkReport(),state)).Valid,"ADK patch non atteste refuse : "+state);
foreach(var changed in new Dictionary<string,object?>{["InstalledVersion"]="10.1.26100.3000",["OscdimgSha256"]="BAD",["SignatureStatus"]="NotSigned",["PatchId"]="KB0000000",["RequiredPatches"]=Array.Empty<object>(),["PatchArchiveSha256"]="WRONG",["RestartRequired"]=true})
{var report=AdkReport();report[changed.Key]=changed.Value;Check(!(await VerifyAdk(report)).Valid,"ADK preuve incorrecte refusee : "+changed.Key);}
Check((await VerifyAdk(AdkReport(AdkInstallationService.CurrentRelease),null,AdkInstallationService.CurrentRelease)).Valid,"ADK revision 9457 connue acceptee sans revendiquer KB5101684");
Check(!(await VerifyAdk(AdkReport(),1,AdkInstallationService.CurrentRelease)).Valid,"ADK changement d'installation entre rapport et verification refuse");
Check(AdkInstallationService.ReadPatchState("{00000000-0000-0000-0000-000000000001}","{00000000-0000-0000-0000-000000000002}")==null,"MSI API Windows reelle : faux produit non installe refuse");

string sourceFixture=Path.Combine(deploymentRoot,"source.iso"),outputFixture=Path.Combine(deploymentRoot,"output.iso");await File.WriteAllTextAsync(sourceFixture,"source fixture");
await using(var file=new FileStream(outputFixture,FileMode.Create,FileAccess.Write)){file.SetLength(17*1024*1024);file.Position=17*2048+1;await file.WriteAsync(System.Text.Encoding.ASCII.GetBytes("NSR02"));}
string outputHash=Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(outputFixture)));
var expectation=new IsoBuildExpectation(sourceFixture,outputFixture,"fr-FR","040C:0000040C","BastOS","APPHASH","APPNATIVE","SELECTIONHASH","OPTIONSHASH");
Dictionary<string,object?> IsoReport()=>new(){["OutputIso"]=outputFixture,["SourceIso"]=sourceFixture,["FileLength"]=new FileInfo(outputFixture).Length,["Sha256"]=outputHash,
 ["WindowsLocale"]="fr-FR",["KeyboardLayout"]="040C:0000040C",["LocalUserName"]="BastOS",["AppManifestSha256"]=new string('A',64),["SourceAppManifestSha256"]="APPHASH",["NativeAppSha256"]="APPNATIVE",["RequestRemoveSelectionSha256"]="SELECTIONHASH",["RequestRemovalOptionsSha256"]="OPTIONSHASH",
 ["MediaRemounted"]=true,["BootFilesVerified"]=true,["WindowsImageVerified"]=true,["EmbeddedFilesVerified"]=true,["VerifiedAppFileCount"]=399,["WindowsImageCount"]=1,["WindowsImageArchitecture"]=9,["WindowsImageName"]="Windows 11 Pro"};
Check((await DeploymentOperationVerifiers.IsoAsync(expectation,Json(IsoReport()))).Valid,"ISO jeu synthetique : descripteur UDF, SHA, profil et preuves de worker controles");
foreach(var changed in new Dictionary<string,object?>{["OutputIso"]=sourceFixture,["SourceIso"]=outputFixture,["FileLength"]=1,["Sha256"]="BAD",["WindowsLocale"]="en-US",["KeyboardLayout"]="0409:00000409",["LocalUserName"]="Other",["AppManifestSha256"]="OLD",["SourceAppManifestSha256"]="OTHER",["NativeAppSha256"]="OTHER",["RequestRemoveSelectionSha256"]="OTHER",["RequestRemovalOptionsSha256"]="OTHER",["MediaRemounted"]=false,["BootFilesVerified"]=false,["WindowsImageVerified"]=false,["EmbeddedFilesVerified"]=false,["VerifiedAppFileCount"]=0,["WindowsImageCount"]=2,["WindowsImageArchitecture"]=12,["WindowsImageName"]="Windows 10 Pro"})
{var report=IsoReport();report[changed.Key]=changed.Value;Check(!(await DeploymentOperationVerifiers.IsoAsync(expectation,Json(report))).Valid,"ISO preuve divergente refusee : "+changed.Key);}
await using(var file=new FileStream(outputFixture,FileMode.Open,FileAccess.Write,FileShare.None)){file.Position=17*2048+1;await file.WriteAsync(new byte[5]);}
var noUdf=IsoReport();noUdf["Sha256"]=Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(outputFixture)));
Check(!(await DeploymentOperationVerifiers.IsoAsync(expectation,Json(noUdf))).Valid,"ISO descripteur UDF absent refuse malgre empreinte coherente");
await Scenario("build-cancelled",id=>{var report=Valid(id);report["Success"]=false;report["Cancelled"]=true;report["CancellationScope"]="IsoBuildCheckpoint";report["CancellationCleanupVerified"]=true;return report;},new(false,2,"",""),OperationState.Cancelled,"OPERATION_CANCELLED");
await Scenario("iso-missing-proof",Valid,ok,OperationState.Unconfirmed,"VERIFICATION_ERROR",payload=>DeploymentOperationVerifiers.IsoAsync(expectation,payload));
var buildStarted=new TaskCompletionSource();var buildFinish=new TaskCompletionSource();int buildLaunches=0;
var sharedBuildEngine=new VerifiedOperationService(Path.Combine(root,"build-group"),async (_,argv)=>{
 buildLaunches++;buildStarted.TrySetResult();await buildFinish.Task;string[] values=argv.ToArray();string id=values[Array.IndexOf(values,"-OperationId")+1],file=values[Array.IndexOf(values,"-ResultPath")+1];await File.WriteAllTextAsync(file,JsonSerializer.Serialize(Valid(id)));return ok;
},(_,_,_)=>{});
Task<OperationResult> BuildGroup(string output)=>sharedBuildEngine.RunAsync("build","build.ps1",new[]{"-OutputIso",output},_=>Task.FromResult(Verified()),concurrencyKey:"iso-build");
var buildFirst=BuildGroup("first.iso");await buildStarted.Task;var buildDuplicate=await BuildGroup("second.iso");
Check(buildDuplicate.ErrorCode=="OPERATION_BUSY" && buildLaunches==1,"Deux constructions avec sorties differentes restent serialisees");buildFinish.SetResult();await buildFirst;
var observedSteps=new List<WorkerProgress>();
var stepEngine=new VerifiedOperationService(Path.Combine(root,"build-progress"),async(_,argv)=>{
 string[] v=argv.ToArray();string progress=v[Array.IndexOf(v,"-ProgressPath")+1],file=v[Array.IndexOf(v,"-ResultPath")+1],id=v[Array.IndexOf(v,"-OperationId")+1];
 await File.WriteAllTextAsync(progress,"100\tVerification ISO\tControle final\t7\t7");await Task.Delay(400);
 var data=Valid(id);data["Step"]=7;data["TotalSteps"]=7;await File.WriteAllTextAsync(file,JsonSerializer.Serialize(data));return ok;
},(_,_,_)=>{});
await stepEngine.RunAsync("build","build.ps1",Array.Empty<string>(),_=>Task.FromResult(Verified()),new ImmediateProgress(value=>observedSteps.Add(value)));
Check(observedSteps.Any(value=>value.Percent==99 && value.Step==7 && value.TotalSteps==7 && value.Message=="Controle final") && observedSteps.Last().Percent==100 && observedSteps.Last().Step==7,"Progression ISO preserve etapes et attend verification avant 100");

Console.WriteLine($"PASS : {passed} contrôles.");
sealed class ImmediateProgress(Action<WorkerProgress> report) : IProgress<WorkerProgress> { public void Report(WorkerProgress value) => report(value); }
