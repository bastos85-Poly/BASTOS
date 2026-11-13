using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class InterruptAffinityService(AppPaths paths, PowerShellWorkerService workers, OperationLogService log)
{
    private const string Script = "Manage-BASTOS-InterruptAffinity.ps1";

    public async Task<(bool Success, bool Applied, string Message)> ReadAsync(string profile)
    {
        var result = await ExecuteAsync("Get", profile, elevate: false);
        return (result.Success, result.Applied, result.Message);
    }

    public async Task<(bool Success, string Message)> SetAsync(string profile, bool enabled)
    {
        var result = await ExecuteAsync(enabled ? "Enable" : "Disable", profile, elevate: true);
        if (!result.Success) return (false, result.Message);
        var verified = enabled ? await ReadAsync(profile) : await ExecuteAsync("GetDefaults", profile, elevate: false);
        if (!verified.Success || !verified.Applied)
            return (false, result.Message + " Vérification des affinités incomplète : " + verified.Message);
        return (true, result.Message);
    }

    private async Task<(bool Success, bool Applied, string Message)> ExecuteAsync(string action, string profile, bool elevate)
    {
        if (profile is not ("Custom" or "SixCore" or "DualCcd" or "Intel" or "X3D"))
            return (false, false, "Profil d’affinité inconnu.");
        string? reportPath = null;
        try
        {
            string[] arguments;
            if (elevate)
            {
                Directory.CreateDirectory(paths.LogRoot);
                reportPath = Path.Combine(paths.LogRoot, $"InterruptAffinity-{Guid.NewGuid():N}.json");
                arguments = ["-Action", action, "-Profile", profile, "-ResultPath", reportPath];
            }
            else arguments = ["-Action", action, "-Profile", profile];
            CommandResult command = await workers.RunAsync(Script, arguments, elevate, timeoutMinutes: 5, terminateOnTimeout: false);
            string json = elevate && reportPath != null && File.Exists(reportPath)
                ? await File.ReadAllTextAsync(reportPath)
                : command.Output.Trim();
            if (string.IsNullOrWhiteSpace(json))
                return (false, false, command.Error.Length > 0 ? command.Error : "Aucun compte rendu d’affinité reçu.");
            using JsonDocument document = JsonDocument.Parse(json);
            var root = document.RootElement;
            bool reported = root.GetProperty("Success").GetBoolean();
            bool applied = root.TryGetProperty("Applied", out var value) && value.ValueKind == JsonValueKind.True;
            string message = root.GetProperty("Message").GetString() ?? "Compte rendu incomplet.";
            bool success = command.Success && reported;
            log.Write("Affinité des interruptions", message, !success);
            return (success, applied, message);
        }
        catch (Exception ex)
        {
            log.Write("Affinité des interruptions", ex.Message, true);
            return (false, false, "Lecture ou modification des affinités impossible : " + ex.Message);
        }
    }
}
