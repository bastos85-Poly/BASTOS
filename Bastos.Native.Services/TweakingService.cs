using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class TweakingService(AppPaths paths, PowerShellWorkerService workers, OperationLogService log)
{
	public async Task<TweakingSnapshot> ReadAsync()
	{
		string resultPath = Path.Combine(paths.LogRoot, $"Tweaking-State-{Guid.NewGuid():N}.json");
		try
		{
			await workers.RunAsync("Manage-BASTOS-Tweaking.ps1", new _003C_003Ez__ReadOnlyArray<string>(new string[4] { "-Action", "Get", "-ResultPath", resultPath }), elevate: false, 2);
			if (!File.Exists(resultPath))
			{
				return new TweakingSnapshot(new Dictionary<string, bool>(), new Dictionary<string, string>(), 38);
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
			int quantum = (jsonDocument.RootElement.TryGetProperty("Quantum", out var value3) ? value3.GetInt32() : 38);
			return new TweakingSnapshot(dictionary, dictionary2, quantum);
		}
		catch (Exception ex)
		{
			log.Write("Réglages avancés", "Lecture : " + ex.Message, error: true);
			return new TweakingSnapshot(new Dictionary<string, bool>(), new Dictionary<string, string>(), 38);
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

	public Task<(bool Success, string Message)> SetToggleAsync(string option, bool enabled)
	{
		return RunAsync(enabled ? "Enable" : "Disable", option, null);
	}

	public Task<(bool Success, string Message)> ApplyChoiceAsync(string option, string value)
	{
		return RunAsync("Apply", option, value);
	}

	public Task<(bool Success, string Message)> ApplyQuantumAsync(int value)
	{
		return RunAsync("Apply", "Quantum", value.ToString());
	}

	public Task<(bool Success, string Message)> RestoreQuantumAsync()
	{
		return RunAsync("RestoreQuantum", "Quantum", null);
	}

	private async Task<(bool Success, string Message)> RunAsync(string action, string option, string? value)
	{
		Directory.CreateDirectory(paths.LogRoot);
		string resultPath = Path.Combine(paths.LogRoot, $"Tweaking-{option}-{Guid.NewGuid():N}.json");
		List<string> list = new List<string> { "-Action", action, "-Option", option, "-ResultPath", resultPath };
		if (value != null)
		{
			list.Add("-Value");
			list.Add(value);
		}
		CommandResult commandResult = await workers.RunAsync("Manage-BASTOS-Tweaking.ps1", list, elevate: true, 5);
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
			log.Write("Réglages avancés", option + " : " + message, !flag);
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
