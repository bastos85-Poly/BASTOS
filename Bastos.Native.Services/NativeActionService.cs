using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class NativeActionService(ProcessExecutionService runner, OperationLogService log)
{
	public async Task<NativeActionResult> RunElevatedAsync(string action, IProgress<RepairProgress>? progress = null)
	{
		string processPath = Environment.ProcessPath;
		if (string.IsNullOrWhiteSpace(processPath))
		{
			return new NativeActionResult(Success: false, "Chemin de BASTOS introuvable.", -1);
		}
		string resultPath = Path.Combine(Path.GetTempPath(), $"BASTOS-Native-{Guid.NewGuid():N}.json");
		string progressPath = resultPath + ".progress";
		using var cancellation = new CancellationTokenSource();
		var poll = progress == null ? Task.CompletedTask : WatchProgress(progressPath, progress, cancellation.Token);
		try
		{
			CommandResult run = await runner.RunAsync(processPath, new string[4] { "--native-worker", action, "--result", resultPath }, elevate: true, action is "repair-sfc" or "repair-dism" or "sfc-verify" or "dism-scan" ? 120 : 45);
			cancellation.Cancel();
			await poll;
			if (File.Exists(resultPath))
			{
				NativeActionResult nativeActionResult = JsonSerializer.Deserialize<NativeActionResult>(await File.ReadAllTextAsync(resultPath));
				if ((object)nativeActionResult != null)
				{
					log.Write("Native", action + ": " + nativeActionResult.Message, !nativeActionResult.Success);
					return nativeActionResult;
				}
			}
			string text = run.Success ? "Le rapport de la commande est absent : résultat non confirmé." : run.Error;
			log.Write("Native", action + ": " + text, true);
			return new NativeActionResult(false, text, run.ExitCode == 0 ? 1 : run.ExitCode);
		}
		finally
		{
			cancellation.Cancel();
			try
			{
				File.Delete(resultPath);
				File.Delete(progressPath);
			}
			catch
			{
			}
		}
	}

	private static async Task WatchProgress(string path, IProgress<RepairProgress> progress, CancellationToken token)
	{
		string? last = null;
		while (!token.IsCancellationRequested)
		{
			try
			{
				if (File.Exists(path))
				{
					var text = await File.ReadAllTextAsync(path, token);
					if (text != last && JsonSerializer.Deserialize<RepairProgress>(text) is { } item) { last = text; progress.Report(item); }
				}
			}
			catch (OperationCanceledException) { break; }
			catch (IOException) { }
			catch (UnauthorizedAccessException) { }
			catch (JsonException) { }
			try { await Task.Delay(250, token); } catch (OperationCanceledException) { break; }
		}
	}
}
