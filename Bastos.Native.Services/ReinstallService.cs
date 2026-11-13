using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed partial class ReinstallService(AppPaths paths, PowerShellWorkerService workers, ModuleOperationService operations, OperationLogService log)
{
	private readonly VerifiedOperationService prerequisites = new(paths.LogRoot,
        (script, arguments) => workers.RunAsync(script, arguments, timeoutMinutes: 10, terminateOnTimeout: false),
        (area, message, error) => log.Write(area, message, error));

    private readonly VerifiedOperationService deployment = new(paths.LogRoot,
        (script, arguments) => workers.RunAsync(script, arguments, elevate: true,
            timeoutMinutes: script == "Build-BASTOS-ISO.ps1" ? 240 : 60, terminateOnTimeout: false),
        (area, message, error) => log.Write(area, message, error));

    public string RufusOptionsPath => Path.Combine(paths.StateRoot, "Rufus-Reinstall-Options.json");
    public void OpenCatalogLink(WindowsDownloadChoice item, bool sourcePage)
    {
        string target = sourcePage ? item.SourcePage : item.Url;
        if (!Uri.TryCreate(target, UriKind.Absolute, out var uri) || uri.Scheme != "https")
            throw new InvalidOperationException("Le lien de téléchargement doit utiliser HTTPS.");
        operations.Open(target);
        log.Write("Catalogue ISO", item.FileName + " — " + target);
    }
    public bool HasRufusOptions => File.Exists(RufusOptionsPath);

    public async Task<(bool Success, string Message)> FinalizeTemporaryRecoveryAsync(bool apply)
    {
        Directory.CreateDirectory(paths.LogRoot);
        string result = Path.Combine(paths.LogRoot, $"Recovery-Finalization-{Guid.NewGuid():N}.json");
        string[] arguments = apply
            ? new[] { "-Apply", "-ResultPath", result }
            : new[] { "-ResultPath", result };
        CommandResult command = await workers.RunAsync("Finalize-BASTOS-TemporaryRecovery.ps1", arguments,
            elevate: apply, timeoutMinutes: apply ? 60 : 5, terminateOnTimeout: false);
        if (!command.ProcessStopped) return (false, "La finalisation travaille encore. Consulte le Journal avant de réessayer.");
        if (!File.Exists(result)) return (false, command.Error.Length > 0 ? command.Error : "Aucun diagnostic de finalisation reçu.");
        using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(result));
        string status = GetString(report.RootElement, "Status");
        string message = GetString(report.RootElement, "Message");
        bool success = command.Success && status == (apply ? "Completed" : "Ready");
        log.Write("Finalisation Recovery", message, !success);
        return (success, message);
    }

    public RufusInstallOptions ReadRufusOptions()
    {
        if (!HasRufusOptions) return new RufusInstallOptions();
        var options = JsonSerializer.Deserialize<RufusInstallOptions>(File.ReadAllText(RufusOptionsPath))
            ?? throw new InvalidOperationException("Les options de réinstallation sont illisibles.");
        options.ApplySimplifiedProfile();
        return options;
    }

    public void SaveRufusOptions(RufusInstallOptions options)
    {
        options.ApplySimplifiedProfile();
        Directory.CreateDirectory(paths.StateRoot);
        string temporary = RufusOptionsPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(options, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, RufusOptionsPath, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private string FreezeRecoveryOptions(RufusInstallOptions options)
    {
        if (string.IsNullOrWhiteSpace(options.DiskSafetySnapshot))
            throw new InvalidOperationException("Le plan des disques doit être revérifié et enregistré dans Compte, nom du PC, nettoyage et partitions.");
        Directory.CreateDirectory(paths.LogRoot);
        string file = Path.Combine(paths.LogRoot, "Recovery-Options-" + Guid.NewGuid().ToString("N") + ".json");
        File.WriteAllText(file, JsonSerializer.Serialize(options));
        return file;
    }

    public async Task<WindowsIsoEditionCatalog> ReadIsoEditionsAsync(IsoChoice iso)
    {
        Directory.CreateDirectory(paths.LogRoot);
        string result = Path.Combine(paths.LogRoot, "Iso-Editions-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            var worker = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1",
                new[] { "-Action", "ListEditions", "-IsoPath", iso.Path, "-ResultPath", result }, timeoutMinutes: 10);
            if (!File.Exists(result)) throw new InvalidOperationException("Lecture des éditions impossible. " + worker.Error);
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(result));
            var data = document.RootElement;
            if (!worker.Success || !data.TryGetProperty("Success", out var ok) || !ok.GetBoolean())
                throw new InvalidOperationException(GetString(data, "Message"));
            var editions = new List<WindowsIsoEdition>();
            foreach (var item in data.GetProperty("Images").EnumerateArray())
                editions.Add(new WindowsIsoEdition(item.GetProperty("ImageIndex").GetInt32(),
                    GetString(item, "ImageName"), GetString(item, "EditionId"))
                {
                    Languages = item.TryGetProperty("Languages", out var languages)
                        ? languages.EnumerateArray().Select(language => language.GetString() ?? "").Where(language => language.Length > 0).ToArray()
                        : Array.Empty<string>(),
                    DefaultUILanguage = GetString(item, "DefaultUILanguage")
                });
            if (editions.Count == 0) throw new InvalidOperationException("Aucune édition Windows 11 x64 disponible dans cet ISO.");
            return new WindowsIsoEditionCatalog(GetString(data, "IsoPath"), GetString(data, "IsoSha256"), editions);
        }
        finally { if (File.Exists(result)) File.Delete(result); }
    }

    public async Task<RecoveryDiskPreview> PreviewRecoveryAsync(RufusInstallOptions options, string? isoPath = null)
    {
        Directory.CreateDirectory(paths.LogRoot);
        string token = Guid.NewGuid().ToString("N");
        string request = Path.Combine(paths.LogRoot, "Rufus-Preview-Options-" + token + ".json");
        string result = Path.Combine(paths.LogRoot, "Rufus-Preview-" + token + ".json");
        await File.WriteAllTextAsync(request, JsonSerializer.Serialize(options));
        try
        {
            var arguments = new List<string> { "-Action", "PreviewPlan", "-OptionsPath", request, "-ResultPath", result,
                    "-RecoveryMode", "Novice", "-PostInstallMode", "WindowsOnly" };
            if (!string.IsNullOrEmpty(isoPath)) arguments.AddRange(new[] { "-IsoPath", isoPath });
            var worker = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1", arguments, timeoutMinutes: 10);
              if (!File.Exists(result)) return new(false, worker.Error, "", "", "", "");
            using var json = JsonDocument.Parse(await File.ReadAllTextAsync(result));
            var data = json.RootElement;
              bool success = worker.Success && worker.ProcessStopped && data.TryGetProperty("Success", out var ok) && ok.GetBoolean();
              return new(success, GetString(data, "Message"), GetString(data, "TargetDescription"),
                  GetString(data, "RecoveryPartitionGuid"), GetString(data, "WindowsDiskIdentity"), GetString(data, "DiskSafetySnapshot"))
              {
                  Partitions = data.TryGetProperty("Partitions", out var parts) ? parts.EnumerateArray().Select(p => new RecoveryPartitionPreview(
                      p.GetProperty("Number").GetInt32(), GetString(p, "Guid"), GetString(p, "Location"), p.GetProperty("SizeBytes").GetInt64(), GetString(p, "Decision"))).ToArray() : Array.Empty<RecoveryPartitionPreview>(),
                  RecoverySizeBytes = data.TryGetProperty("RecoverySizeBytes", out var size) ? size.GetInt64() : 0,
                  RecoveryFreeBytes = data.TryGetProperty("RecoveryFreeBytes", out var free) ? free.GetInt64() : -1,
                  DiskDescription = GetString(data, "DiskDescription"),
                  CreateEfi = data.TryGetProperty("CreateEfi", out var efi) && efi.GetBoolean(),
                  CacheCleanupProfile = success && data.TryGetProperty("CachePlan", out var profile) && profile.ValueKind == JsonValueKind.Object ? GetString(profile, "CleanupProfile") : "",
                  CacheMode = success && data.TryGetProperty("CachePlan", out var cache) && cache.ValueKind == JsonValueKind.Object ? GetString(cache, "Mode") : "Full",
                  CacheRequiredFreeBytes = success && data.TryGetProperty("CachePlan", out var cp) && cp.ValueKind == JsonValueKind.Object ? cp.GetProperty("RequiredFreeBytes").GetInt64() : 0,
                  CacheIsoSha256 = success && data.TryGetProperty("CachePlan", out var identity) && identity.ValueKind == JsonValueKind.Object ? GetString(identity, "IsoSha256") : ""
              };
        }
        finally
        {
            File.Delete(request);
            File.Delete(result);
        }
    }

	public IReadOnlyList<string> ReadDefaultAppxRemovals()
	{
		string path = paths.Script("Remove-Appx.txt");
		if (!File.Exists(path)) return Array.Empty<string>();
		return File.ReadAllLines(path).Select(line => line.Trim())
			.Where(line => line.Length > 0 && !line.StartsWith('#'))
			.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
	}

	public string? ReadWebView2Version() => WebView2RuntimeService.ReadVersion();

	public Task<OperationResult> ProbeWebView2RuntimeAsync()
	{
		return prerequisites.RunNativeAsync("Vérification de WebView2", "webview2-presence", _ => {
			string? version = ReadWebView2Version();
			bool present = WebView2RuntimeService.IsInstalledVersion(version);
			return Task.FromResult(new NativeOperationReport(present,
				present ? "Version de WebView2 détectée." : "WebView2 n’est pas détecté dans Windows.",
				new Dictionary<string, object?> { ["Version"] = version ?? "", ["Status"] = "AlreadyInstalled", ["InstallerStarted"] = false },
				present ? "" : "WEBVIEW2_NOT_DETECTED"));
		}, payload => OperationVerifiers.WebView2Async(Path.Combine(paths.DataRoot, "Tools", "WebView2"), ReadWebView2Version, payload), resumeIntent: new("WebView2"));
	}

	public async Task<(bool Success, string Message)> EnsureWebView2RuntimeAsync()
	{
		// A completed background installation can be rechecked without relaunching its worker.
		if (ReadWebView2Version() != null)
		{
			var presence = await ProbeWebView2RuntimeAsync();
			return (presence.Success, presence.UserMessage);
		}
		string cacheRoot = Path.Combine(paths.DataRoot, "Tools", "WebView2");
		var result = await prerequisites.RunAsync("Préparation de WebView2", "Install-BASTOS-WebView2Runtime.ps1", Array.Empty<string>(),
			payload => OperationVerifiers.WebView2Async(cacheRoot, ReadWebView2Version, payload), resumeIntent: new("WebView2"));
		return (result.Success, result.UserMessage);
	}
	public IReadOnlyList<IsoChoice> FindIsos()
	{
		return (from path in GetIsoSearchFolders().Where(Directory.Exists).SelectMany((string folder) => Directory.EnumerateFiles(folder, "*.iso", SearchOption.TopDirectoryOnly)).Distinct<string>(StringComparer.OrdinalIgnoreCase)
			select new FileInfo(path) into file
			where file.Length > 16 * 1024 * 1024
			orderby file.LastWriteTimeUtc descending
			select file).Select(delegate(FileInfo file)
		{
			string value = Path.GetFullPath(operations.IsoLibrary).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
			bool flag = Path.GetFullPath(file.FullName).StartsWith(value, StringComparison.OrdinalIgnoreCase) || file.Name.StartsWith("BASTOS-Windows11", StringComparison.OrdinalIgnoreCase);
			return new IsoChoice((flag ? "BASTOS personnalisée" : "Microsoft d’origine") + " — " + file.Name, file.FullName, flag, file.Length, file.CreationTime, file.LastWriteTime);
		}).ToArray();
	}

	public (bool Success, string Message) DeleteIso(IsoChoice iso)
	{
		try
		{
			string fullPath = Path.GetFullPath(iso.Path);
			if (!string.Equals(Path.GetExtension(fullPath), ".iso", StringComparison.OrdinalIgnoreCase))
			{
				return (Success: false, Message: "Suppression refusée : le fichier sélectionné n’est pas une ISO.");
			}
			if (!File.Exists(fullPath))
			{
				return (Success: false, Message: "L’ISO sélectionnée n’existe plus.");
			}
			string parent = Path.GetDirectoryName(fullPath);
			if (parent == null || !GetIsoSearchFolders().Any((string folder) => string.Equals(Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar), Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)))
			{
				return (Success: false, Message: "Suppression refusée : l’ISO n’est pas directement dans la bibliothèque BASTOS ou dans Téléchargements.");
			}
			if ((File.GetAttributes(fullPath) & FileAttributes.ReparsePoint) != FileAttributes.None)
			{
				return (Success: false, Message: "Suppression refusée : les liens et points de réanalyse ne sont pas autorisés.");
			}
			if (!FindIsos().Any((IsoChoice item) => string.Equals(Path.GetFullPath(item.Path), fullPath, StringComparison.OrdinalIgnoreCase)))
			{
				return (Success: false, Message: "Suppression refusée : l’ISO ne fait plus partie du catalogue vérifié.");
			}
			long length = new FileInfo(fullPath).Length;
			File.Delete(fullPath);
			if (File.Exists(fullPath))
			{
				return (Success: false, Message: "Windows n’a pas confirmé la suppression de l’ISO.");
			}
			string text = $"ISO supprimée : {Path.GetFileName(fullPath)} — {(double)length / 1024.0 / 1024.0 / 1024.0:N2} Go libérés.";
			log.Write("Réinstallation", text);
			return (Success: true, Message: text);
		}
		catch (Exception ex) when (((ex is IOException || ex is UnauthorizedAccessException || ex is SecurityException) ? 1 : 0) != 0)
		{
			string text2 = "Suppression impossible : " + ex.Message;
			log.Write("Réinstallation", text2, error: true);
			return (Success: false, Message: text2);
		}
	}

	private string[] GetIsoSearchFolders()
	{
		return new string[2]
		{
			operations.IsoLibrary,
			Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")
		};
	}

	public async Task<(bool Success, string Message, string? IsoPath)> DownloadWindowsAsync(LanguageChoice language, NamedChoice release, IProgress<IsoDownloadProgress>? progress = null)
	{
		Directory.CreateDirectory(paths.LogRoot);
		string result = Path.Combine(paths.LogRoot, $"WindowsIso-{Guid.NewGuid():N}.json");
		string text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
		Directory.CreateDirectory(text);
		List<string> list = new List<string>
		{
			"-Architecture",
			"x64",
			"-Language",
			language.Value,
			"-LanguageDisplay",
			language.Display,
			"-DownloadDirectory",
			text,
			"-ResultPath",
			result,
			"-Release",
			release.Value,
			"-TimeoutSeconds",
			(release.Value == "Insider26H2") ? "900" : "120"
		};
		if (release.Value == "Retail25H2")
		{
			list.Add("-Hidden");
		}
		Task<CommandResult> workerTask = workers.RunAsync("Download-BASTOS-WindowsIso.ps1", list, elevate: false, (release.Value == "Insider26H2") ? 90 : 30, release.Value == "Insider26H2");
		long previousBytes = 0L;
		DateTime previousSample = DateTime.UtcNow;
		string previousSnapshot = string.Empty;
		while (!workerTask.IsCompleted)
		{
			PublishIsoProgress(result, progress, ref previousBytes, ref previousSample, ref previousSnapshot);
			await Task.WhenAny(workerTask, Task.Delay(250));
		}
		CommandResult commandResult = await workerTask;
		PublishIsoProgress(result, progress, ref previousBytes, ref previousSample, ref previousSnapshot, force: true);
		try
		{
			if (File.Exists(result))
			{
				using (JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(result)))
				{
					JsonElement rootElement = jsonDocument.RootElement;
					string text2 = GetString(rootElement, "Status");
					string text3 = GetString(rootElement, "Message");
					string text4 = GetString(rootElement, "FilePath");
					bool flag;
					switch (text2)
					{
					case "Completed":
					case "DownloadStarted":
					case "LinkReady":
						flag = true;
						break;
					default:
						flag = false;
						break;
					}
					bool flag2 = flag;
					log.Write("Réinstallation", $"Téléchargement {release.Display}: {text2} — {text3}", !flag2);
					return (Success: flag2, Message: string.IsNullOrWhiteSpace(text3) ? text2 : text3, IsoPath: File.Exists(text4) ? text4 : null);
				}
			}
			return (Success: commandResult.Success, Message: commandResult.Success ? "Assistant Microsoft terminé. Actualise la liste des ISO." : commandResult.Error, IsoPath: null);
		}
		finally
		{
			try
			{
				File.Delete(result);
			}
			catch
			{
			}
		}
	}

	private static void PublishIsoProgress(string resultPath, IProgress<IsoDownloadProgress>? progress, ref long previousBytes, ref DateTime previousSample, ref string previousSnapshot, bool force = false)
	{
		if (progress == null || !File.Exists(resultPath))
		{
			return;
		}
		try
		{
			string text = File.ReadAllText(resultPath);
			if (!force && string.Equals(text, previousSnapshot, StringComparison.Ordinal))
			{
				return;
			}
			using JsonDocument jsonDocument = JsonDocument.Parse(text);
			JsonElement rootElement = jsonDocument.RootElement;
			string status = GetString(rootElement, "Status");
			string filePath = GetString(rootElement, "FilePath");
			long num = ((rootElement.TryGetProperty("Bytes", out var value) && value.TryGetInt64(out var value2)) ? value2 : 0);
			long num2 = ((rootElement.TryGetProperty("TotalBytes", out var value3) && value3.TryGetInt64(out var value4)) ? value4 : 0);
			DateTime utcNow = DateTime.UtcNow;
			double num3 = Math.Max(0.001, (utcNow - previousSample).TotalSeconds);
			double bytesPerSecond = ((num >= previousBytes) ? ((double)(num - previousBytes) / num3) : 0.0);
			double percent = ((num2 > 0) ? Math.Clamp((double)num * 100.0 / (double)num2, 0.0, 100.0) : 0.0);
			progress.Report(new IsoDownloadProgress(status, num, num2, percent, bytesPerSecond, filePath));
			previousBytes = num;
			previousSample = utcNow;
			previousSnapshot = text;
		}
		catch (IOException)
		{
		}
		catch (JsonException)
		{
		}
	}

	public async Task<(bool Success, string Message, string? IsoPath)> BuildBastosIsoAsync(IsoChoice source, LanguageChoice language, KeyboardChoice keyboard, string userName, IReadOnlyCollection<string> selectedAppxRemovals, bool removeOneDrive, bool disableConsumerContent, IProgress<IsoBuildProgress>? buildProgress = null, OperationCancellation? cancellation = null)
	{
		ValidateUserName(userName);
		if (!File.Exists(source.Path))
		{
			return (Success: false, Message: "L’ISO source est introuvable.", IsoPath: null);
		}
		if (source.IsBastosCustom)
		{
			return (Success: false, Message: "Sélectionne l’ISO Microsoft d’origine pour créer une nouvelle ISO BASTOS.", IsoPath: null);
		}
		buildProgress?.Report(new IsoBuildProgress(0.0, "Prérequis", "Vérification des Outils de déploiement Microsoft…", 0, 7, IsIndeterminate: true));
		cancellation?.ThrowIfRequested();
        cancellation?.Lock("La vérification ou l’installation des outils ADK doit se terminer. Aucun installateur ne sera arrêté de force.");
		var adk = await EnsureAdkDeploymentToolsAsync(buildProgress);
        bool flag = adk.Success; string text = adk.UserMessage;
		if (!flag)
		{
			buildProgress?.Report(new IsoBuildProgress(0.0, "Échec des prérequis", text, 0, 7));
			log.Write("Réinstallation", "Prérequis ISO : " + text, error: true);
			return (Success: false, Message: text, IsoPath: null);
		}
        cancellation?.AllowRead();
        cancellation?.ThrowIfRequested();
		Directory.CreateDirectory(operations.IsoLibrary);
		Directory.CreateDirectory(paths.LogRoot);
		string selectionId = Guid.NewGuid().ToString("N");
		string selectedAppxPath = Path.Combine(paths.LogRoot, "Iso-Appx-Selection-" + selectionId + ".txt");
		string removalOptionsPath = Path.Combine(paths.LogRoot, "Iso-Removal-Options-" + selectionId + ".json");
		await File.WriteAllLinesAsync(selectedAppxPath, selectedAppxRemovals, new System.Text.UTF8Encoding(false));
		await File.WriteAllTextAsync(removalOptionsPath,
			JsonSerializer.Serialize(new { RemoveOneDrive = removeOneDrive, DisableConsumerContent = disableConsumerContent }),
			new System.Text.UTF8Encoding(false));
		string value = keyboard.InputLocale switch
		{
			"0409:00000409" => "US-QWERTY", 
			"0409:00020409" => "US-International-QWERTY", 
			"0809:00000809" => "UK-QWERTY", 
			"040C:0000040C" => "FR-AZERTY", 
			"080C:0000080C" => "BE-AZERTY", 
			"0C0C:00001009" => "CA-QWERTY", 
			"100C:0000100C" => "CH-QWERTZ", 
			"0407:00000407" => "DE-QWERTZ", 
			"040A:0000040A" => "ES-QWERTY", 
			_ => "Clavier-personnalise", 
		};
		string output = Path.Combine(operations.IsoLibrary, $"BASTOS-Windows11_Langue-{language.Locale}_Clavier-{value}_{DateTime.Now:yyyyMMdd-HHmmss}-{selectionId[..8]}.iso");
        static async Task<string> HashAsync(string path)
        {
            using var stream = File.OpenRead(path);
            return Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(stream));
        }
        var expected = new IsoBuildExpectation(source.Path, output, language.Locale, keyboard.InputLocale, userName.Trim(),
            await HashAsync(Path.Combine(paths.Root, "BASTOS-App-Manifest.json")), await HashAsync(paths.NativeExecutable), await HashAsync(selectedAppxPath), await HashAsync(removalOptionsPath));
        string cancel = cancellation?.BindWorker(paths.LogRoot) ?? Path.Combine(paths.LogRoot, "IsoBuild-Cancel-" + selectionId + ".request");
        var arguments = new[] { "-SourceIso", source.Path, "-OutputIso", output, "-WindowsLocale", language.Locale,
            "-KeyboardLayout", keyboard.InputLocale, "-LocalUserName", userName.Trim(), "-BrowserId", "None",
            "-RemoveListPath", selectedAppxPath, "-RemovalOptionsPath", removalOptionsPath,
            "-CancellationPath", cancel, "-AdkEvidencePath", adk.WorkerReportPath };
        var progress = new Progress<WorkerProgress>(item => buildProgress?.Report(new IsoBuildProgress(
            item.Percent == 100 ? 100 : Math.Clamp(10 + item.Percent * 0.9, 10, 99), item.Phase, item.Message, item.Step, 7)));
        var running = deployment.RunAsync("Construction de l’ISO BASTOS", "Build-BASTOS-ISO.ps1", arguments,
            payload => DeploymentOperationVerifiers.IsoAsync(expected, payload), progress, concurrencyKey: "iso-build",
            resumeIntent: new("IsoBuild",source.Path,JsonSerializer.Serialize(expected)));
        var result = cancellation == null ? await running : await cancellation.TrackAsync(running);
        buildProgress?.Report(new IsoBuildProgress(result.Success ? 100 : 0, result.Success ? "ISO vérifiée" : "Construction non validée", result.UserMessage, result.Success ? 7 : 0, 7));
        return (result.Success, result.UserMessage + (result.Success && cancellation?.Requested == true ? " La publication finale avait déjà commencé ; l’annulation n’a pas été effectuée." : ""), result.Success ? output : null);
    }

    private Task<OperationResult> EnsureAdkDeploymentToolsAsync(IProgress<IsoBuildProgress>? buildProgress)
    {
        string cache = Path.Combine(paths.DataRoot, "Prerequisites", "WindowsADK");
        var arguments = new[] { "-InstallerPath", Path.Combine(cache, "adksetup.exe"),
            "-PatchPath", Path.Combine(cache, "Windows_ADK_10.1.26100.2454_Update_KB5101684.zip"), "-DownloadDirectory", cache };
        var progress = new Progress<WorkerProgress>(item => buildProgress?.Report(new IsoBuildProgress(Math.Clamp(item.Percent / 10d, 0, 10), item.Phase, item.Message, 0, 7)));
        return deployment.RunAsync("Préparation de Windows ADK", "Install-BASTOS-AdkDeploymentTools.ps1", arguments,
            payload => DeploymentOperationVerifiers.AdkAsync(payload, AdkInstallationService.ReadVersion, AdkInstallationService.ReadPatchState, AdkInstallationService.OscdimgCandidates(), Path.Combine(cache, "Windows_ADK_10.1.26100.2454_Update_KB5101684.zip")), progress, resumeIntent: new("Adk"));
    }
	public async Task<(bool Success, string Message)> PrepareUsbAsync(IsoChoice iso)
	{
		if (!File.Exists(iso.Path))
		{
			return (Success: false, Message: "L’ISO sélectionnée est introuvable.");
		}
		string text = Path.Combine(paths.DataRoot, "Tools", "Rufus");
		string rufus = Path.Combine(text, "rufus.exe");
		Directory.CreateDirectory(text);
		Directory.CreateDirectory(paths.LogRoot);
		if (!File.Exists(rufus))
		{
			var preparation = await operations.PrepareRufusAsync();
			if (!preparation.Success) return (false, preparation.UserMessage);
		}
		string result = Path.Combine(paths.LogRoot, $"Rufus-Launch-{Guid.NewGuid():N}.json");
		CommandResult launch = await workers.RunAsync("Launch-BASTOS-Rufus.ps1", new string[6] { "-RufusPath", rufus, "-IsoPath", iso.Path, "-ResultPath", result }, elevate: false, 5, showWindow: true);
		string message = "Rufus est ouvert avec l’ISO présélectionnée. Choisis la clé USB puis clique sur Démarrer.";
		if (File.Exists(result))
		{
			using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(result));
			string text4 = GetString(jsonDocument.RootElement, "Message");
			if (!string.IsNullOrWhiteSpace(text4))
			{
				message = text4;
			}
		}
		log.Write("Réinstallation", message, !launch.Success);
		return (Success: launch.Success, Message: message);
	}

	public async Task<(bool Success, string Message)> TestRecoveryAsync()
	{
		string result = Path.Combine(paths.LogRoot, $"Recovery-Diagnostic-{Guid.NewGuid():N}.json");
		CommandResult commandResult = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1", new string[8] { "-Action", "DiagnosticBoot", "-ResultPath", result, "-RecoveryMode", "Novice", "-PostInstallMode", "BastosAutonomous" }, elevate: true, 10);
		string message = ReadResultMessage(result, commandResult.Success ? "Le test Recovery est programmé." : commandResult.Error);
		if (!commandResult.Success)
		{
			log.Write("Réinstallation", message, error: true);
			return (Success: false, Message: message);
		}
		ProcessStartInfo processStartInfo = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "shutdown.exe"))
		{
			UseShellExecute = false,
			CreateNoWindow = true
		};
		string[] array = new string[7] { "/r", "/t", "15", "/d", "p:4:1", "/c", "Test non destructif BASTOS_RECOVERY" };
		foreach (string item in array)
		{
			processStartInfo.ArgumentList.Add(item);
		}
		using Process process = Process.Start(processStartInfo);
		if (process == null)
		{
			return (Success: false, Message: "Le test est armé, mais Windows n’a pas accepté la commande de redémarrage.");
		}
		await process.WaitForExitAsync();
		if (process.ExitCode != 0)
		{
			return (Success: false, Message: $"Le test est armé, mais le redémarrage a échoué (code {process.ExitCode}).");
		}
		string text = message + " Windows redémarrera dans 15 secondes. Aucune partition ne sera modifiée.";
		log.Write("Réinstallation", text);
		return (Success: true, Message: text);
	}

	public async Task<(bool Success, string Message)> CheckAutonomousCompatibilityAsync()
	{
		Directory.CreateDirectory(paths.LogRoot);
		string result = Path.Combine(paths.LogRoot, $"Autonomous-Status-{Guid.NewGuid():N}.json");
		CommandResult commandResult = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1", new string[10] { "-Action", "Status", "-ResultPath", result, "-RecoverySizeGB", "40", "-RecoveryMode", "Novice", "-PostInstallMode", "BastosAutonomous" }, elevate: false, 5);
		string item = ReadResultMessage(result, commandResult.Success ? "Le contrôle de compatibilité n’a pas produit de rapport vérifiable." : commandResult.Error);
		bool compatible = false;
		if (commandResult.Success && File.Exists(result))
		{
			try
			{
				using JsonDocument report = JsonDocument.Parse(File.ReadAllText(result));
				compatible = report.RootElement.TryGetProperty("CanProvision", out JsonElement canProvision) &&
					(canProvision.ValueKind == JsonValueKind.True || canProvision.ValueKind == JsonValueKind.False) &&
					canProvision.GetBoolean();
			}
			catch (JsonException) { }
			catch (IOException) { }
		}
		return (Success: compatible, Message: item);
	}

	public async Task<(bool Success, string Message)> PrepareRecoveryPartitionAsync()
	{
		Directory.CreateDirectory(paths.LogRoot);
		string result = Path.Combine(paths.LogRoot, $"Recovery-Partition-{Guid.NewGuid():N}.json");
		CommandResult command = await workers.RunAsync("Initialize-BASTOS-Recovery.ps1",
			new[] { "-Action", "PreparePartition", "-ResultPath", result, "-RecoverySizeGB", "40", "-RecoveryMode", "Novice", "-PostInstallMode", "BastosAutonomous" },
			elevate: true, timeoutMinutes: 30, terminateOnTimeout: false);
		string message = ReadResultMessage(result, command.Success ? "La préparation de D: n’a pas produit de rapport vérifiable." : command.Error);
		bool prepared = false;
		if (command.Success && command.ProcessStopped && File.Exists(result))
		{
			try
			{
				using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(result));
				prepared = report.RootElement.TryGetProperty("Success", out JsonElement success) && success.ValueKind == JsonValueKind.True &&
					report.RootElement.TryGetProperty("RecoveryExists", out JsonElement exists) && exists.ValueKind == JsonValueKind.True &&
					report.RootElement.TryGetProperty("DiskNumber", out JsonElement disk) && disk.ValueKind == JsonValueKind.Number;
			}
			catch (JsonException) { }
			catch (IOException) { }
		}
		if (!command.ProcessStopped) message += " L’outil peut encore travailler : vérifie le Journal avant de réessayer.";
		log.Write("Réinstallation", message, !prepared);
		return (prepared, message);
	}

	public async Task<(bool Success, string Message)> PrepareAutonomousAsync(IsoChoice? iso, LanguageChoice language, KeyboardChoice keyboard, string userName, int editionIndex = 0)
	{
		ValidateUserName(userName);
		if ((object)iso == null || !File.Exists(iso.Path))
		{
			return (Success: false, Message: "Sélectionne d’abord l’ISO BASTOS créée dans Réinstallation facile Windows.");
		}
		var (flag, text) = await ProvisionRecoveryAsync(iso, language, keyboard, userName, null, forceBastosAutonomous: true, editionIndex: editionIndex);
		log.Write("Installation autonome", text, !flag);
		return (Success: flag, Message: text);
	}

    public async Task<(bool Success, string Message)> StartAutonomousAsync()
    {
        string file = @"D:\BASTOS-MEDIA-STATE.json";
        if (!File.Exists(file) || new FileInfo(file).Length > 4 * 1024 * 1024)
            return (false, "Le média préparé n’est pas identifiable. Sélectionne l’ISO et prépare BASTOS_RECOVERY avant de démarrer.");
        using var media = JsonDocument.Parse(await File.ReadAllTextAsync(file));
        string source = GetString(media.RootElement, "IsoPath");
        if (!File.Exists(source)) return (false, "L’ISO source doit être disponible pour vérifier le média avant le démarrage.");
        return await BootRecoveryAsync(new IsoChoice(Path.GetFileName(source), source, true), forceBastosAutonomous: true);
    }
	public void OpenIsoLibrary(string? selectedIsoPath = null)
	{
		if (!string.IsNullOrWhiteSpace(selectedIsoPath) && File.Exists(selectedIsoPath))
		{
			string? selectedFolder = Path.GetDirectoryName(Path.GetFullPath(selectedIsoPath));
			if (!string.IsNullOrWhiteSpace(selectedFolder) && Directory.Exists(selectedFolder))
			{
				operations.Open(selectedFolder);
				return;
			}
		}
		operations.Open(operations.IsoLibrary);
	}

	private static string GetString(JsonElement root, string name)
	{
		if (!root.TryGetProperty(name, out var value))
		{
			return string.Empty;
		}
		return value.GetString() ?? string.Empty;
	}

	private static string ReadResultMessage(string path, string fallback)
	{
		try
		{
			if (File.Exists(path))
			{
				using JsonDocument jsonDocument = JsonDocument.Parse(File.ReadAllText(path));
				string text = GetString(jsonDocument.RootElement, "Message");
				if (!string.IsNullOrWhiteSpace(text))
				{
					return text;
				}
			}
		}
		catch
		{
		}
		return fallback;
	}

	private static void ValidateUserName(string value)
	{
		string text = value.Trim();
		int length = text.Length;
		if (length < 1 || length > 20 || false || text.IndexOfAny("\\/:*?\"<>|@;,.".ToCharArray()) >= 0)
		{
			throw new InvalidOperationException("Le nom du compte doit contenir 1 à 20 caractères sans caractère interdit.");
		}
	}
}
