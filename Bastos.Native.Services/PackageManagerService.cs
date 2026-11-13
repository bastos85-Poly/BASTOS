using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class PackageManagerService(AppPaths paths, PowerShellWorkerService workers, OperationLogService log)
{
    public string LastInstallationDetail { get; private set; } = "";
    public string LastUninstallationDetail { get; private set; } = "";
	public async Task<(bool Success, string Message)> EnsureReadyOnceAsync()
	{
		if (File.Exists(paths.PackageManagerReadyMarker))
		{
			return (Success: true, Message: "Gestionnaire déjà préparé lors d’un précédent démarrage.");
		}
		PackageManagerInfo manager = Detect();
		bool flag = (object)manager != null;
		if (flag)
		{
			flag = (await new ProcessExecutionService().RunAsync(manager.Path, new string[1] { "--version" }, elevate: false, 1)).Success;
		}
		if (flag)
		{
			WriteReadyMarker(manager.DisplayName);
			return (Success: true, Message: manager.DisplayName + " est prêt.");
		}
		var (flag2, item) = await RepairAsync();
		if (flag2)
		{
			WriteReadyMarker(Detect()?.DisplayName ?? "gestionnaire disponible");
		}
		return (Success: flag2, Message: item);
	}

	private void WriteReadyMarker(string manager)
	{
		Directory.CreateDirectory(paths.StateRoot);
		File.WriteAllText(paths.PackageManagerReadyMarker, $"{manager}\r\n{DateTime.UtcNow:O}\r\n", new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
	}

	public IReadOnlyList<SoftwarePackage> ReadCatalog()
	{
		string path = paths.Script("Software-Catalog.json");
		if (!File.Exists(path))
		{
			return Array.Empty<SoftwarePackage>();
		}
		return (JsonSerializer.Deserialize<List<SoftwarePackage>>(File.ReadAllText(path), new JsonSerializerOptions
		{
			PropertyNameCaseInsensitive = true
		}) ?? new List<SoftwarePackage>()).Where((SoftwarePackage item) => !string.IsNullOrWhiteSpace(item.Name) && !item.Category.Equals("Navigateurs Web", StringComparison.OrdinalIgnoreCase) && (Regex.IsMatch(item.Id ?? string.Empty, "^[A-Za-z0-9][A-Za-z0-9.+_-]{1,127}$") || !string.IsNullOrWhiteSpace(item.CustomAction))).ToArray();
	}

	public PackageManagerInfo? Detect()
	{
		string folderPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
		string text = ProcessExecutionService.FindExecutable("winget.exe", Path.Combine(folderPath, "Microsoft", "WindowsApps", "winget.exe"), Path.Combine(folderPath, "Microsoft", "WindowsApps", "AppInstallerCLI.exe"));
		if (text != null)
		{
			return new PackageManagerInfo("winget", text, "WinGet");
		}
		string text2 = ProcessExecutionService.FindExecutable("choco.exe", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "chocolatey", "bin", "choco.exe"));
		if (text2 != null)
		{
			return new PackageManagerInfo("chocolatey", text2, "Chocolatey");
		}
		return null;
	}

	public async Task<(bool Success, string Message)> RepairAsync()
	{
		Directory.CreateDirectory(paths.LogRoot);
		string resultPath = Path.Combine(paths.LogRoot, $"PackageManager-Repair-{Guid.NewGuid():N}.json");
		CommandResult commandResult = await workers.RunAsync("Repair-BASTOS-PackageManager.ps1", new string[3] { "-ResultPath", resultPath, "-AllowChocolatey" }, elevate: true);
		try
		{
			if (File.Exists(resultPath))
			{
				using (JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath)))
				{
					bool flag = jsonDocument.RootElement.TryGetProperty("Success", out var value) && value.GetBoolean();
					string text = (jsonDocument.RootElement.TryGetProperty("Manager", out var value2) ? (value2.GetString() ?? string.Empty) : string.Empty);
					return (Success: flag, Message: flag ? (text + " est prêt.") : "La préparation du gestionnaire a échoué. Consulte le journal.");
				}
			}
			return (Success: commandResult.Success, Message: commandResult.Success ? "Gestionnaire préparé." : commandResult.Error);
		}
		finally
		{
			try
			{
				File.Delete(resultPath);
			}
			catch
			{
			}
		}
	}

	public async Task<(bool Success, string Message)> InstallAsync(SoftwarePackage package)
	{
		return await InstallManyAsync(new SoftwarePackage[1] { package });
	}

	public async Task<(bool Success, string Message)> InstallManyAsync(IEnumerable<SoftwarePackage> requestedPackages)
	{
        LastInstallationDetail = "";
		SoftwarePackage[] selectedPackages = requestedPackages.Where((SoftwarePackage softwarePackage) => string.IsNullOrWhiteSpace(softwarePackage.CustomAction)).ToArray();
		if (selectedPackages.Length == 0)
		{
			return (Success: false, Message: "Aucune application standard à installer.");
		}
		PackageManagerInfo manager = Detect();
		if ((object)manager == null)
		{
			(bool, string) obj = await RepairAsync();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			manager = Detect();
			if (!item || (object)manager == null)
			{
				return (Success: false, Message: "WinGet et Chocolatey sont indisponibles. " + item2);
			}
			WriteReadyMarker(manager.DisplayName);
		}
		Directory.CreateDirectory(paths.LogRoot);
		string text = Guid.NewGuid().ToString("N");
		string selection = Path.Combine(paths.LogRoot, "Software-Selection-" + text + ".json");
		string progress = Path.Combine(paths.LogRoot, "Software-Progress-" + text + ".txt");
		string result = Path.Combine(paths.LogRoot, "Software-Result-" + text + ".json");
		await File.WriteAllTextAsync(selection, JsonSerializer.Serialize(selectedPackages), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
		CommandResult commandResult = await workers.RunAsync("Install-BASTOS-SoftwareSelection.ps1", new[] { "-SelectionPath", selection, "-ProgressPath", progress, "-ResultPath", result, "-Manager", manager.Name, "-ManagerPath", manager.Path, "-ExpectedUserSid", System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value }, elevate: false, 65);
		try
		{
			if (File.Exists(result))
			{
                var summary = SoftwareInstallationReport.Read(await File.ReadAllBytesAsync(result), selectedPackages.Select(p=>p.Id).ToArray(), commandResult.Success, System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value);
                LastInstallationDetail = "Rapport : " + result + Environment.NewLine + summary.Detail;
                log.Write("Logiciels", summary.Message + " Rapport : " + result, !summary.Success);
                return (summary.Success, summary.Message);
			}
            LastInstallationDetail = commandResult.Error;
            return (false, "Aucun rapport d’installation exploitable. Résultat non confirmé. " + commandResult.Error);
		}
		finally
		{
			string[] array = new string[2] { selection, progress };
			foreach (string path in array)
			{
				try
				{
					File.Delete(path);
				}
				catch
				{
				}
			}
		}
	}

	public async Task<(bool Success, string Message)> UninstallManyAsync(IEnumerable<SoftwarePackage> requestedPackages)
	{
        LastUninstallationDetail = "";
		SoftwarePackage[] array = requestedPackages.Where((SoftwarePackage item) => string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
		if (array.Length == 0)
		{
			return (Success: false, Message: "Aucune application standard à désinstaller.");
		}
		int succeeded = 0;
		List<string> failures = new List<string>();
		SoftwarePackage[] array2 = array;
		SoftwarePackage[] array3 = array2;
		foreach (SoftwarePackage package in array3)
		{
			var (flag, text) = await UninstallAsync(package);
			if (flag)
			{
				succeeded++;
			}
			else
			{
				failures.Add(package.Name + " : " + text);
			}
		}
		return (Success: failures.Count == 0, Message: (failures.Count == 0) ? $"{succeeded} application(s) désinstallée(s)." : $"{succeeded} supprimée(s), {failures.Count} échec(s) : {string.Join(" | ", failures)}");
	}

	public async Task<(bool Success, string Message)> ManageCustomManyAsync(IEnumerable<SoftwarePackage> requestedPackages, string action)
	{
		SoftwarePackage[] array = requestedPackages.Where((SoftwarePackage item) => !string.IsNullOrWhiteSpace(item.CustomAction)).ToArray();
		if (array.Length == 0)
		{
			return (Success: true, Message: string.Empty);
		}
		int succeeded = 0;
		List<string> successMessages = new List<string>();
		List<string> failures = new List<string>();
		SoftwarePackage[] array2 = action.Equals("Uninstall", StringComparison.OrdinalIgnoreCase)
			? array.OrderByDescending(item => item.CustomAction == "AudioTool:Peace").ToArray()
			: array.OrderByDescending(item => item.CustomAction == "AudioTool:EqualizerAPO").ToArray();
		SoftwarePackage[] array3 = array2;
		foreach (SoftwarePackage package in array3)
		{
			string resultPath = Path.Combine(paths.LogRoot, $"SpecialSoftware-{Guid.NewGuid():N}.json");
			CommandResult commandResult = package.CustomAction == "RAMMap"
				? await workers.RunAsync("Manage-BASTOS-RAMMap.ps1", new string[4] { "-Action", action, "-ResultPath", resultPath }, elevate: false)
				: await workers.RunAsync("Manage-BASTOS-SpecialSoftware.ps1", new string[6] { "-CustomAction", package.CustomAction, "-Action", action, "-ResultPath", resultPath }, elevate: true);
			bool success = commandResult.Success;
			string message = (commandResult.Success ? "Action terminée." : commandResult.Error);
			try
			{
				if (File.Exists(resultPath))
				{
					using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
					success = jsonDocument.RootElement.TryGetProperty("Success", out var value) && value.GetBoolean();
					message = (jsonDocument.RootElement.TryGetProperty("Message", out var value2) ? (value2.GetString() ?? message) : message);
				}
			}
			catch
			{
			}
			finally
			{
				try
				{
					File.Delete(resultPath);
				}
				catch
				{
				}
			}
			if (success)
			{
				succeeded++;
				successMessages.Add(message);
			}
			else
			{
				failures.Add(package.Name + " : " + message);
			}
		}
		string value3 = (action.Equals("Uninstall", StringComparison.OrdinalIgnoreCase) ? "supprimée(s)" : "installée(s) ou lancée(s)");
		return (Success: failures.Count == 0, Message: (failures.Count == 0) ? ((array.Length == 1 && successMessages.Count == 1) ? successMessages[0] : $"{succeeded} application(s) spéciale(s) {value3}.") : $"{succeeded} réussie(s), {failures.Count} échec(s) : {string.Join(" | ", failures)}");
	}

	public async Task<HashSet<string>> DetectInstalledIdsAsync(IEnumerable<SoftwarePackage> catalog)
	{
		HashSet<string> installed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
		PackageManagerInfo packageManagerInfo = Detect();
		_ = string.Empty;
		if (packageManagerInfo?.Name == "winget")
		{
			string text = (await new ProcessExecutionService().RunAsync(packageManagerInfo.Path, new string[3] { "list", "--accept-source-agreements", "--disable-interactivity" }, elevate: false, 5)).Output ?? string.Empty;
			foreach (SoftwarePackage item in catalog)
			{
				if (text.Contains(item.Id, StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(text, "(?im)^" + Regex.Escape(item.Name) + "\\s{2,}"))
				{
					installed.Add(item.Id);
				}
			}
			if (text.Contains("OpenAI.Codex", StringComparison.OrdinalIgnoreCase))
			{
				installed.Add("9PLM9XGG6VKS");
			}
		}
		string text2 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "Software", "Portable");
        if(File.Exists(Path.Combine(text2,"ProcessExplorer","procexp64.exe")) && File.Exists(Path.Combine(text2,"ProcessExplorer","BASTOS-installed.json")))
            installed.Add("Microsoft.Sysinternals.ProcessExplorer");
		if (File.Exists(Path.Combine(text2, "RAMMap", "RAMMap64.exe")) && File.Exists(Path.Combine(text2, "RAMMap", "BASTOS-installed.json")))
		{
			installed.Add("BASTOS.RAMMap");
		}
		if (File.Exists(Path.Combine(text2, "AMDCleanupUtility", "amdcleanuputility.exe")))
		{
			installed.Add("BASTOS.AMDCleanupUtility");
		}
		if (File.Exists(Path.Combine(text2, "VibranceGUI", "vibranceGUI.exe")))
		{
			installed.Add("BASTOS.VibranceGUI");
		}
		if (File.Exists(Path.Combine(text2, "RadeonSoftwareSlimmer", "RadeonSoftwareSlimmer.exe")))
		{
			installed.Add("GitHub.GSDragoon.RadeonSoftwareSlimmer");
		}
		if (File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "EqualizerAPO", "Editor.exe")))
		{
			installed.Add("BASTOS.EqualizerAPO");
		}
		if (File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "EqualizerAPO", "config", "Peace.exe")))
		{
			installed.Add("BASTOS.PeaceEqualizer");
		}
		if (File.Exists(Path.Combine(text2, "RadeonTuner", "RadeonTuner.exe")))
		{
			installed.Add("GitHub.dumbie.RadeonTuner");
		}
		if (File.Exists(Path.Combine(text2, "ScaledResolutionEditor", "SRE.exe")))
		{
			installed.Add("ToastyX.ScaledResolutionEditor");
		}
		if (File.Exists(Path.Combine(text2, "NSudo", "NSudo Launcher", "x64", "NSudoLG.exe")))
		{
			installed.Add("BASTOS.NSudo");
		}
		if (File.Exists(Path.Combine(text2, "DriverView", "DriverView.exe")))
		{
			installed.Add("BASTOS.DriverView");
		}
		if (File.Exists(Path.Combine(text2, "WUManager", "wumgr.exe")))
		{
			installed.Add("BASTOS.WUManager");
		}
		if (File.Exists(Path.Combine(text2, "MouseTester", "MouseTester.exe")))
		{
			installed.Add("BASTOS.MouseTester");
		}
		if (File.Exists(Path.Combine(text2, "MeasureSleep", "MeasureSleep.exe")))
		{
			installed.Add("BASTOS.MeasureSleep");
		}
		if (File.Exists(Path.Combine(text2, "OCAT", "OCAT.installed")))
		{
			installed.Add("BASTOS.OCAT");
		}
		if (File.Exists(Path.Combine(text2, "PerfMeasurement", "PerfMeasurement.installed")))
		{
			installed.Add("BASTOS.PerfMeasurement");
		}
		if (File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "Tools", "REAL", "REAL.exe")))
		{
			installed.Add("miniant-git/REAL");
		}
		return installed;
	}

	public async Task<(bool Success, string Message)> UpdateAllAsync()
	{
		PackageManagerInfo packageManagerInfo = Detect();
		if ((object)packageManagerInfo == null)
		{
			(bool, string) obj = await RepairAsync();
			bool item = obj.Item1;
			string item2 = obj.Item2;
			packageManagerInfo = Detect();
			if (!item || (object)packageManagerInfo == null)
			{
				return (Success: false, Message: "Aucun gestionnaire disponible. " + item2);
			}
			WriteReadyMarker(packageManagerInfo.DisplayName);
		}
		CommandResult commandResult = ((packageManagerInfo.Name == "winget") ? (await new ProcessExecutionService().RunAsync(packageManagerInfo.Path, new string[6] { "upgrade", "--all", "--silent", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity" }, elevate: false, 90)) : (await new ProcessExecutionService().RunAsync(packageManagerInfo.Path, new string[4] { "upgrade", "all", "--yes", "--no-progress" }, elevate: true, 90)));
		CommandResult commandResult2 = commandResult;
		string text = (commandResult2.Success ? "Mise à jour globale terminée." : $"Mise à jour terminée avec le code {commandResult2.ExitCode}.");
		log.Write("Logiciels", text, !commandResult2.Success);
		return (Success: commandResult2.Success, Message: text);
	}

	public async Task<(bool Success, string Message)> UninstallAsync(SoftwarePackage package)
	{
		PackageManagerInfo packageManagerInfo = Detect();
		if ((object)packageManagerInfo == null)
		{
			return (Success: false, Message: "Aucun gestionnaire disponible.");
		}
		CommandResult commandResult;
		if (packageManagerInfo.Name == "winget")
		{
            var service = new SoftwareUninstallationService((exe, args, admin) => new ProcessExecutionService().RunAsync(exe, args, elevate: admin));
            var result = await service.UninstallWingetAsync(packageManagerInfo.Path, package);
            LastUninstallationDetail += service.Detail + "\n";
            log.Write("Logiciels", service.Detail + "\n" + result.Message, !result.Success);
            return result;
		}
		else
		{
			if (string.IsNullOrWhiteSpace(package.ChocolateyId))
			{
				return (Success: false, Message: "La désinstallation de " + package.Name + " nécessite WinGet.");
			}
			commandResult = await new ProcessExecutionService().RunAsync(packageManagerInfo.Path, new string[4] { "uninstall", package.ChocolateyId, "--yes", "--no-progress" }, elevate: true);
		}
		string text = (commandResult.Success ? (package.Name + " a été désinstallé.") : $"Échec de la désinstallation (code {commandResult.ExitCode}).");
		log.Write("Logiciels", text, !commandResult.Success);
		return (Success: commandResult.Success, Message: text);
	}
}
