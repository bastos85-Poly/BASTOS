using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Bastos.Native.Services;

public sealed class SoftwareUninstallationService
{
    private readonly Func<string, IEnumerable<string>, bool, Task<CommandResult>> run;
    public string Detail { get; private set; } = "";
    public SoftwareUninstallationService(Func<string, IEnumerable<string>, bool, Task<CommandResult>> run) => this.run = run;

    public async Task<(bool Success, string Message)> UninstallWingetAsync(string executable, SoftwarePackage package)
    {
        if (!Regex.IsMatch(package.Id ?? "", "^[A-Za-z0-9][A-Za-z0-9.+_-]{1,127}$"))
            return (false, "Identifiant de logiciel invalide.");
        // Open-Shell installs an all-users MSI. Silent MSI removal cannot request UAC itself.
        bool admin = package.Id.Equals("Open-Shell.Open-Shell-Menu", StringComparison.OrdinalIgnoreCase);
        var result = await run(executable, new[] { "uninstall", "--id", package.Id, "--exact", "--silent", "--accept-source-agreements", "--disable-interactivity" }, admin);
        Detail = $"{package.Name} — désinstallation : {result.ExitCode}\n{result.Output}\n{result.Error}";
        if (!result.ProcessStopped) return (false, "Désinstallation encore en cours ou arrêt non confirmé. Consulte le Journal avant de réessayer.");
        if (result.ExitCode == 1223) return (false, "Demande administrateur annulée ; désinstallation non effectuée.");
        const int noApplications = unchecked((int)0x8A150014);
        bool acceptable = result.ExitCode is 0 or 3010 || result.ExitCode == noApplications;
        if (!acceptable) return (false, $"Échec de la désinstallation (code {result.ExitCode}). Consulte les détails.");
        var check = await run(executable, new[] { "list", "--id", package.Id, "--exact", "--accept-source-agreements", "--disable-interactivity" }, false);
        Detail += $"\nVérification après suppression : {check.ExitCode}\n{check.Output}\n{check.Error}";
        if (!check.ProcessStopped || check.ExitCode != noApplications)
            return (false, check.ExitCode == 0 ? "Le logiciel est encore détecté après la désinstallation." : "Impossible de vérifier la suppression. Consulte les détails.");
        return (true, package.Name + " a été désinstallé, absence vérifiée." + (result.ExitCode == 3010 ? " Un redémarrage est nécessaire." : ""));
    }
}
