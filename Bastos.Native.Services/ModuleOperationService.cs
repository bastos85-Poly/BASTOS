using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;

namespace Bastos.Native.Services;

public sealed class ModuleOperationService(AppPaths paths, PowerShellWorkerService workers, ProcessExecutionService runner, OperationLogService log)
{
	public string IsoLibrary
	{
		get
		{
			string text = "D:\\ISO";
			string obj = (Directory.Exists("D:\\") ? text : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "BASTOS-ISO"));
			Directory.CreateDirectory(obj);
			return obj;
		}
	}

	public void Open(string target)
	{
		Process.Start(new ProcessStartInfo(target)
		{
			UseShellExecute = true
		});
		log.Write("Ouverture", target);
	}

	private readonly VerifiedOperationService verified = new VerifiedOperationService(paths.LogRoot,
		(script, arguments) => workers.RunAsync(script, arguments, timeoutMinutes: 20, terminateOnTimeout: script != "Cleanup-BASTOS-Temp.ps1"),
		(area, message, error) => log.Write(area, message, error));

	public Task<OperationResult> PrepareRufusAsync()
	{
		string output = Path.Combine(paths.DataRoot, "Tools", "Rufus", "rufus.exe");
		return verified.RunAsync("Téléchargement de Rufus", "Download-BASTOS-Rufus.ps1", new[] { "-OutputPath", output },
			payload => OperationVerifiers.RufusAsync(output, payload), resumeIntent: new("RufusDownload"));
	}

	public async Task<(bool Success, string Message)> DownloadRufusAsync()
	{
		OperationResult operation = await PrepareRufusAsync();
		if (!operation.Success) return (false, operation.UserMessage);
		try
		{
			Open(Path.Combine(paths.DataRoot, "Tools", "Rufus", "rufus.exe"));
			return (true, operation.Message + " Ouverture demandée à Windows.");
		}
		catch (Exception error)
		{
			log.Write("Rufus", $"[{operation.OperationId}] Ouverture impossible : {error}", true);
			return (false, "Rufus est téléchargé et vérifié, mais Windows n’a pas pu l’ouvrir. Référence : " + operation.OperationId + ". Consulte le journal.");
		}
	}
	public Task<OperationResult> RunCleanupAsync(bool analyzeOnly)
	{
		return verified.RunAsync(analyzeOnly ? "Analyse des fichiers temporaires" : "Nettoyage des fichiers temporaires",
			"Cleanup-BASTOS-Temp.ps1", analyzeOnly ? new[] { "-AnalyzeOnly" } : Array.Empty<string>(),
			payload => OperationVerifiers.CleanupAsync(analyzeOnly, payload));
	}
	public async Task<(bool Success, string Message)> HardwareAnalysisAsync()
	{
		HardwareAnalysisResult hardwareAnalysisResult = await AnalyzeHardwareAsync();
		if (hardwareAnalysisResult.Success && File.Exists(hardwareAnalysisResult.ReportPath))
		{
			Open(hardwareAnalysisResult.ReportPath);
		}
		return (Success: hardwareAnalysisResult.Success, Message: hardwareAnalysisResult.Message);
	}

	public async Task<HardwareAnalysisResult> AnalyzeHardwareAsync(IProgress<WorkerProgress>? progressReporter = null)
	{
		List<HardwareInventoryItem> inventory = new();
		List<DriverRecommendation> recommendations = new();
		int detected = 0, problems = 0;
		OperationResult operation = await verified.RunAsync("Analyse matérielle", "Hardware-Analysis-Worker.ps1", Array.Empty<string>(),
			async payload =>
			{
				var validation = await OperationVerifiers.HardwareAsync(payload);
				if (validation.Valid)
				{
					var report = payload.GetProperty("Report");
					inventory = BuildInventory(report);
					recommendations = BuildRecommendations(payload);
					detected = report.GetProperty("Summary").GetProperty("DetectedDevices").GetInt32();
					problems = report.GetProperty("Summary").GetProperty("ProblemCount").GetInt32();
				}
				return validation;
			}, progressReporter);
		if (!operation.Success)
			return new HardwareAnalysisResult(false, operation.UserMessage, Array.Empty<HardwareInventoryItem>(), Array.Empty<DriverRecommendation>(), 0, 0, operation.WorkerReportPath) { Operation = operation };
		string message = operation.Message + $" {detected} périphérique(s), {recommendations.Count} lien(s) de pilote officiel, {problems} problème(s).";
		return new HardwareAnalysisResult(true, message, inventory, recommendations, detected, problems, operation.WorkerReportPath) { Operation = operation };
	}
	public async Task<(bool Success, string Message)> LaunchGraphicsInstallerAsync(bool debloated = false)
	{
        WorkerIntegrityLease? integrity = null;
		try
		{
			integrity = await Task.Run(() => new WorkerIntegrityService(paths.Root).Acquire("Install-BASTOS-GraphicsDriver.ps1"));
			string script = paths.Script("Install-BASTOS-GraphicsDriver.ps1");
			string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
			string resultPath = Path.Combine(paths.LogRoot, $"GraphicsDriver-{Guid.NewGuid():N}.json");
			Process process = Process.Start(new ProcessStartInfo(powershell)
			{
				UseShellExecute = true,
				Verb = "runas",
				Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Mode " + (debloated ? "Debloat" : "Standard") + " -ResultPath \"" + resultPath + "\"",
				WindowStyle = ProcessWindowStyle.Normal,
				WorkingDirectory = paths.Root
			});
			if (process == null) return (false, "La fenêtre de pilotes n’a pas pu être ouverte.");
			try
			{
				await process.WaitForExitAsync();
				bool success = process.ExitCode == 0 && File.Exists(resultPath);
				string message = success ? "Installateur de pilote terminé." : "Le parcours de pilote s’est arrêté sans compte rendu. Relance-le pour voir le message d’erreur.";
				if (File.Exists(resultPath))
				{
					using JsonDocument report = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
					success &= report.RootElement.GetProperty("Success").GetBoolean();
					message = report.RootElement.GetProperty("Message").GetString() ?? message;
				}
				log.Write("Pilotes graphiques", message, !success);
				return (success, message);
			}
			finally { process.Dispose(); }
		}
        catch (WorkerIntegrityException ex) {
            try { log.Write("Contrôle des fichiers", ex.Code + " : " + ex.Message, true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            return (false, ex.Message);
        }
		catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
		{
			return (false, "Autorisation administrateur annulée. Relance le bouton pour réessayer.");
		}
		catch (Exception ex)
		{
			return (false, "Impossible de lancer le parcours de pilotes : " + ex.Message);
		}
        finally { integrity?.Dispose(); }
	}
	public async Task<(bool Success, string Message)> OpenOfficialDriverAsync(DriverRecommendation recommendation)
	{
		var driver = new OfficialDriverService(Path.Combine(paths.Root, "Official-Sources.json"), Open,
			text => System.Windows.Application.Current.Dispatcher.Invoke(() => System.Windows.Clipboard.SetText(text)));
		var result = await verified.RunNativeAsync("Ouverture du site de pilotes",
			"official-driver|" + JsonSerializer.Serialize(new[] { recommendation.OfficialUrl, recommendation.ResolutionStrategy }),
			progress => driver.ExecuteAsync(recommendation.OfficialUrl, recommendation.ResolutionStrategy, recommendation.SearchTerm, progress),
			async payload => {
				var domains = await driver.ReadDomainsAsync();
				return await OperationVerifiers.OfficialDriverAsync(recommendation.OfficialUrl, recommendation.ResolutionStrategy, domains, payload);
			});
		return (result.Success, result.UserMessage);
	}
	private static List<HardwareInventoryItem> BuildInventory(JsonElement report)
	{
		List<HardwareInventoryItem> list = new List<HardwareInventoryItem>();
		JsonElement property = report.GetProperty("System");
		list.Add(new HardwareInventoryItem("PC", (JsonString(property, "Manufacturer") + " " + JsonString(property, "Model")).Trim(), $"{JsonString(property, "WindowsEdition")} — {JsonString(property, "Architecture")} — {JsonNumber(property, "TotalMemoryGB")} Go de RAM"));
		JsonElement property2 = report.GetProperty("Motherboard");
		list.Add(new HardwareInventoryItem("Carte mère", (JsonString(property2, "Manufacturer") + " " + JsonString(property2, "Model")).Trim(), $"BIOS {JsonString(property2, "BiosVersion")} — UEFI {JsonString(property2, "FirmwareMode")} — Secure Boot {JsonString(property2, "SecureBoot")}"));
		foreach (JsonElement item in JsonArray(report, "Processors"))
		{
			list.Add(new HardwareInventoryItem("Processeur", JsonString(item, "Name"), $"{JsonInt(item, "Cores")} cœurs / {JsonInt(item, "Threads")} threads"));
		}
		foreach (JsonElement item2 in JsonArray(report, "Graphics"))
		{
			list.Add(new HardwareInventoryItem("Carte graphique", JsonString(item2, "Name"), "Pilote " + JsonString(item2, "DriverVersion") + " — état " + JsonString(item2, "Status")));
		}
		foreach (JsonElement item3 in JsonArray(report, "Storage"))
		{
			list.Add(new HardwareInventoryItem("Stockage", JsonString(item3, "Model"), $"{JsonString(item3, "Type")} — {JsonNumber(item3, "CapacityGB")} Go — santé {JsonString(item3, "Health")}"));
		}
		foreach (JsonElement item4 in JsonArray(report, "Network"))
		{
			list.Add(new HardwareInventoryItem("Réseau — " + JsonString(item4, "Type"), JsonString(item4, "Name"), JsonString(item4, "Manufacturer")));
		}
		foreach (JsonElement item5 in JsonArray(report, "Audio"))
		{
			list.Add(new HardwareInventoryItem("Audio", JsonString(item5, "Name"), JsonString(item5, "Manufacturer") + " — " + JsonString(item5, "Status")));
		}
		foreach (JsonElement item6 in JsonArray(report, "ProblemDevices"))
		{
			list.Add(new HardwareInventoryItem("Périphérique en erreur", JsonString(item6, "Name"), $"{JsonString(item6, "Status")} — code {JsonInt(item6, "ErrorCode")}", StatusTone.Danger));
		}
		return list;
	}

	private static List<DriverRecommendation> BuildRecommendations(JsonElement root)
	{
		List<DriverRecommendation> list = new List<DriverRecommendation>();
		foreach (JsonElement item in JsonArray(root, "Recommendations"))
		{
			list.Add(new DriverRecommendation(JsonString(item, "Category"), JsonString(item, "Hardware"), JsonString(item, "Manufacturer"), JsonString(item, "CurrentVersion"), JsonString(item, "SourceName"), JsonString(item, "OfficialUrl"), JsonString(item, "Confidence"), JsonString(item, "Reason"), JsonString(item, "SearchTerm"), JsonString(item, "ResolutionStrategy", string.Empty), item.TryGetProperty("Sensitive", out var value) && value.ValueKind == JsonValueKind.True));
		}
		return list;
	}

	private static IEnumerable<JsonElement> JsonArray(JsonElement element, string name)
	{
		if (!element.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Array)
		{
			return Array.Empty<JsonElement>();
		}
		return value.EnumerateArray().ToArray();
	}

	private static string JsonString(JsonElement element, string name, string fallback = "Information indisponible")
	{
		if (!element.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null)
		{
			return fallback;
		}
		return value.ToString();
	}

	private static int JsonInt(JsonElement element, string name)
	{
		if (!element.TryGetProperty(name, out var value) || !value.TryGetInt32(out var value2))
		{
			return 0;
		}
		return value2;
	}

	private static string JsonNumber(JsonElement element, string name)
	{
		if (!element.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Number)
		{
			return "?";
		}
		return value.ToString();
	}

	public Task<OperationResult> NetworkTestAsync(IProgress<WorkerProgress>? progress = null)
	{
		var network = new NetworkDiagnosticsService();
		return verified.RunNativeAsync("Mesure de latence réseau", "network-diagnostics", network.ExecuteAsync, OperationVerifiers.NetworkAsync, progress);
	}

	public void OpenQuickAssist()
	{
		string text = Path.Combine(Environment.SystemDirectory, "quickassist.exe");
		Open(File.Exists(text) ? text : "ms-quick-assist:");
	}
}
