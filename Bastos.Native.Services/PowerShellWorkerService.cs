using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Linq;
using System.Text.Json;

namespace Bastos.Native.Services;

public sealed class PowerShellWorkerService(AppPaths paths, ProcessExecutionService runner, OperationLogService log)
{
	public async Task<CommandResult> RunAsync(string scriptName, IEnumerable<string> arguments, bool elevate = false, int timeoutMinutes = 30, bool showWindow = false, bool terminateOnTimeout = false)
	{
		if (Path.GetFileName(scriptName) != scriptName || !scriptName.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
		{
			return new CommandResult(false, -20, "", "Nom de script refusé. Aucun script n’a été lancé.") { ExecutionBlocked = true, ErrorCode = "ENGINE_FILE_UNLISTED" };
		}
        WorkerIntegrityLease integrity;
        try { integrity = await Task.Run(() => new WorkerIntegrityService(paths.Root).Acquire(scriptName)); }
        catch (WorkerIntegrityException ex)
        {
            try { log.Write("Contrôle des fichiers", ex.Code + " : " + ex.Message, true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            return new(false, -20, "", ex.Message) { ExecutionBlocked = true, ErrorCode = ex.Code };
        }
        using var integrityLease = integrity;
		string text = paths.Script(scriptName);
        log.Write("Contrôle des fichiers", integrity.CheckedFiles + " fichiers du moteur vérifiés avant " + scriptName);
		List<string> list = new List<string> { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", text };
		list.AddRange(arguments);
        string[] values = list.ToArray();
        int operationIndex = Array.IndexOf(values, "-OperationId");
        string id = operationIndex >= 0 && operationIndex + 1 < values.Length ? values[operationIndex + 1] : "";
        int resultIndex = Array.IndexOf(values, "-ResultPath");
        string reportedPath = resultIndex >= 0 && resultIndex + 1 < values.Length ? values[resultIndex + 1] : "";
        bool mainWorker = Guid.TryParseExact(id, "N", out _) && string.Equals(reportedPath, Path.Combine(paths.LogRoot, "Operations", id + ".worker.json"), StringComparison.OrdinalIgnoreCase);
        Action<int, DateTime>? receipt = mainWorker ? (pid, started) => {
            string directory = Path.Combine(paths.LogRoot, "Operations");
            Directory.CreateDirectory(directory);
            string file = Path.Combine(directory, id + ".process.json");
            string temporary = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try{
                using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))JsonSerializer.Serialize(output,new { SchemaVersion = 1, OperationId = id, ProcessId = pid, StartedUtc = started });
                File.Move(temporary, file, true);
            }finally{if(File.Exists(temporary))File.Delete(temporary);}
        } : null;
		log.Write("Worker", "Démarrage de " + scriptName);
		string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
		CommandResult commandResult = await runner.RunAsync(powershell, list, elevate, timeoutMinutes, showWindow, terminateOnTimeout, onStarted: receipt);
		log.Write("Worker", $"{scriptName} terminé avec le code {commandResult.ExitCode}", !commandResult.Success);
		return commandResult;
	}
}
