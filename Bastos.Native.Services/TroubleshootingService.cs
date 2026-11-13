using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class TroubleshootingService(AppPaths paths, PowerShellWorkerService workers, OperationLogService log)
{
	public async Task<TroubleshootingSnapshot> ReadAsync()
	{
		string resultPath = Path.Combine(paths.LogRoot, $"Troubleshooting-State-{Guid.NewGuid():N}.json");
		try
		{
			await workers.RunAsync("Manage-BASTOS-Troubleshooting.ps1", new string[4] { "-Action", "Get", "-ResultPath", resultPath }, elevate: false, 2);
			if (!File.Exists(resultPath))
			{
				return new TroubleshootingSnapshot(new Dictionary<string, bool>(), new Dictionary<string, string>());
			}
			using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
			Dictionary<string, bool> dictionary = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
			Dictionary<string, string> dictionary2 = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
			if (jsonDocument.RootElement.TryGetProperty("States", out var value))
			{
				foreach (JsonProperty item in value.EnumerateObject())
				{
					dictionary[item.Name] = item.Value.GetBoolean();
				}
			}
			if (jsonDocument.RootElement.TryGetProperty("Choices", out var value2))
			{
				foreach (JsonProperty item2 in value2.EnumerateObject())
				{
					dictionary2[item2.Name] = item2.Value.GetString() ?? string.Empty;
				}
			}
			return new TroubleshootingSnapshot(dictionary, dictionary2);
		}
		catch (Exception ex)
		{
			log.Write("Personnalisation", "Lecture des réglages : " + ex.Message, error: true);
			return new TroubleshootingSnapshot(new Dictionary<string, bool>(), new Dictionary<string, string>());
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

	public async Task<(bool Success, string Message)> SetToggleAsync(string option, bool enabled)
	{
		return await RunAsync(enabled ? "Enable" : "Disable", option, null);
	}

	public async Task<(bool Success, string Message)> ApplyChoiceAsync(string option, string value)
	{
		return await RunAsync("Apply", option, value);
	}

	private async Task<(bool Success, string Message)> RunAsync(string action, string option, string? value)
	{
		Directory.CreateDirectory(paths.LogRoot);
		string resultPath = Path.Combine(paths.LogRoot, $"Troubleshooting-{option}-{Guid.NewGuid():N}.json");
		List<string> list = new List<string> { "-Action", action, "-Option", option, "-ResultPath", resultPath };
		if (!string.IsNullOrWhiteSpace(value))
		{
			list.Add("-Value");
			list.Add(value);
		}
		CommandResult commandResult = await workers.RunAsync("Manage-BASTOS-Troubleshooting.ps1", list, elevate: true, 5);
		try
		{
			bool flag = commandResult.Success;
			string message = (flag ? "Réglage appliqué." : commandResult.Error);
			if (File.Exists(resultPath))
			{
				using JsonDocument jsonDocument = JsonDocument.Parse(await File.ReadAllTextAsync(resultPath));
				flag = jsonDocument.RootElement.TryGetProperty("Success", out var value2) && value2.GetBoolean();
				message = (jsonDocument.RootElement.TryGetProperty("Message", out var value3) ? (value3.GetString() ?? message) : message);
			}
			log.Write("Personnalisation", option + " : " + message, !flag);
			return (Success: flag, Message: message);
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
}
