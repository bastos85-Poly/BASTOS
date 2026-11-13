using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class ProcessExecutionService
{
	public async Task<CommandResult> RunAsync(string fileName, IEnumerable<string> arguments, bool elevate = false, int timeoutMinutes = 30, bool showWindow = false, bool terminateOnTimeout = false, TimeSpan? timeoutOverride = null, Action<int, DateTime>? onStarted = null)
	{
		ProcessStartInfo processStartInfo = new ProcessStartInfo(fileName)
		{
			UseShellExecute = elevate,
			CreateNoWindow = (!elevate && !showWindow),
			WindowStyle = ((!showWindow) ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal)
		};
		if (elevate)
		{
			processStartInfo.Verb = "runas";
		}
		else
		{
			processStartInfo.RedirectStandardOutput = true;
			processStartInfo.RedirectStandardError = true;
		}
		foreach (string argument in arguments)
		{
			processStartInfo.ArgumentList.Add(argument);
		}
		try
		{
			using Process process = Process.Start(processStartInfo) ?? throw new InvalidOperationException("Le processus n’a pas démarré.");
            // A receipt failure must not abandon a running process or imply it stopped.
            try { onStarted?.Invoke(process.Id, process.StartTime.ToUniversalTime()); }
            catch (Exception) { }
			Task<string> stdout = (Task<string>)(elevate ? ((Task)Task.FromResult(string.Empty)) : ((Task)process.StandardOutput.ReadToEndAsync()));
			Task<string> stderr = (Task<string>)(elevate ? ((Task)Task.FromResult(string.Empty)) : ((Task)process.StandardError.ReadToEndAsync()));
			using CancellationTokenSource timeout = new CancellationTokenSource(timeoutOverride ?? TimeSpan.FromMinutes(timeoutMinutes));
			try { await process.WaitForExitAsync(timeout.Token); }
			catch (OperationCanceledException)
			{
				bool stopped = process.HasExited;
				if (terminateOnTimeout && !stopped)
				{
					try
					{
						process.Kill(entireProcessTree: true);
						using var stopWait = new CancellationTokenSource(TimeSpan.FromSeconds(5));
						await process.WaitForExitAsync(stopWait.Token);
						stopped = process.HasExited;
					}
					catch (Exception) { stopped = false; }
				}
				return new CommandResult(false, -2, "", stopped ? "Délai maximal dépassé ; processus arrêté." : "Délai maximal dépassé ; arrêt du processus non confirmé.") { ProcessStopped = stopped };
			}
			bool flag = process.ExitCode == 0;
			int exitCode = process.ExitCode;
			bool success = flag;
			int exitCode2 = exitCode;
			return new CommandResult(success, exitCode2, await stdout, await stderr);
		}
		catch (OperationCanceledException)
		{
			return new CommandResult(Success: false, -2, string.Empty, "Délai maximal dépassé ; arrêt non confirmé.") { ProcessStopped = false };
		}
		catch (Win32Exception ex2) when (ex2.NativeErrorCode == 1223)
		{
			return new CommandResult(Success: false, 1223, string.Empty, "Demande administrateur annulée.");
		}
		catch (Exception ex3)
		{
			return new CommandResult(Success: false, -1, string.Empty, ex3.Message);
		}
	}

	public static string? FindExecutable(string name, params string[] candidates)
	{
		foreach (string item in candidates.Where((string path) => !string.IsNullOrWhiteSpace(path)))
		{
			if (File.Exists(item))
			{
				return Path.GetFullPath(item);
			}
		}
		string[] array = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
		foreach (string text in array)
		{
			try
			{
				string text2 = Path.Combine(text.Trim(), name);
				if (File.Exists(text2))
				{
					return text2;
				}
			}
			catch
			{
			}
		}
		return null;
	}
}
