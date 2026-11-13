using System;
using System.IO;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class MainWindow
{
    private static async Task RunStorageSmokeAsync()
    {
        var paths = new AppPaths();
        var runner = new ProcessExecutionService();
        var log = new OperationLogService(paths);
        var workers = new PowerShellWorkerService(paths, runner, log);
        var modules = new ModuleOperationService(paths, workers, runner, log);
        var service = new ReinstallService(paths, workers, modules, log);
        var options = new RufusInstallOptions();
        var first = await service.PreviewRecoveryAsync(options);
        if (!first.Success || string.IsNullOrWhiteSpace(first.DiskSnapshot))
            throw new InvalidOperationException("Plan de disque non confirmé : " + first.Message);
        options.WindowsDiskIdentity = first.DiskIdentity;
        options.RecoveryPartitionGuid = first.PartitionGuid;
        options.DiskSafetySnapshot = first.DiskSnapshot;
        var second = await service.PreviewRecoveryAsync(options);
        if (!second.Success || second.DiskSnapshot != first.DiskSnapshot)
            throw new InvalidOperationException("Plan du disque divergent entre les deux lectures : " + second.Message);
        if (second.Partitions.Count == 0 || second.RecoveryFreeBytes < 0 || second.RecoverySizeBytes <= 0 ||
            !System.Linq.Enumerable.Any(second.Partitions, p => p.Decision == "CONSERVER" && System.Guid.Parse(p.Guid) == System.Guid.Parse(second.PartitionGuid)) ||
            !System.Linq.Enumerable.Any(second.Partitions, p => p.Decision == "EFFACER"))
            throw new InvalidOperationException("Bilan des partitions ou espace Recovery non confirmé.");
        var missingIso = await service.ReviewRecoveryAsync(new IsoChoice("ISO absente de test", Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".iso")), options, true);
        if (missingIso.CanContinue || !System.Linq.Enumerable.Any(missingIso.Blockers, b => b.StartsWith("ISO non vérifiée")))
            throw new InvalidOperationException("Le service de bilan n’a pas bloqué l’ISO absente.");
        var altered = JsonNode.Parse(first.DiskSnapshot)!;
        altered["Disks"]!["InstallDisk"]!["Serial"] = "BASTOS-SIMULATED-DIFFERENT-DISK";
        options.DiskSafetySnapshot = altered.ToJsonString();
        var refused = await service.PreviewRecoveryAsync(options);
        if (refused.Success || !refused.Message.Contains("DISK_PLAN_CHANGED"))
            throw new InvalidOperationException("Le plan divergent simulé n’a pas été refusé.");
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "BASTOS-Storage-SmokeTest.txt"),
            "OK : service C# et worker réels ; plan D: généré, figé puis revalidé ; détail des partitions conservées/effacées et espace libre relus ; bilan avec ISO absente bloqué ; identifiant divergent simulé refusé. Aucune option utilisateur enregistrée, aucun formatage, aucune préparation ni aucun redémarrage.");
    }
}
