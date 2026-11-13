using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Services;
using Bastos.Native.Models;

namespace Bastos.Native;

public partial class MainWindow
{
    private static async Task RunVerifiedOperationSmokeAsync()
    {
        var paths = new AppPaths();
        var runner = new ProcessExecutionService();
        var log = new OperationLogService(paths);
        var workers = new PowerShellWorkerService(paths, runner, log);
        var service = new ModuleOperationService(paths, workers, runner, log);
        var reinstall = new ReinstallService(paths, workers, service, log);
        string? adkVersion = AdkInstallationService.ReadVersion();
        var webView = await reinstall.ProbeWebView2RuntimeAsync();
        bool webViewPresent = reinstall.ReadWebView2Version() != null;
        if (webView.ExecutionKind != "Native" || webView.Success != webViewPresent ||
            (!webViewPresent && webView.ErrorCode != "WEBVIEW2_NOT_DETECTED") || !File.Exists(webView.JournalPath))
            throw new InvalidOperationException("Échec du contrôle WebView2 en lecture seule : " + webView.UserMessage);
        var full = await service.AnalyzeHardwareAsync();
        var refused = await service.OpenOfficialDriverAsync(new DriverRecommendation("Test", "Test", "Test", "", "Test",
            "https://nvidia.com.attacker.invalid/", "", "", "", "", false));
        if (refused.Success || !refused.Message.Contains("refusé"))
            throw new InvalidOperationException("Le chemin natif des pilotes n’a pas refusé le lien de test.");
        var network = await service.NetworkTestAsync();
        if (!network.Success || network.ExecutionKind != "Native" || network.Checks.Count < 3 || !File.Exists(network.JournalPath))
            throw new InvalidOperationException("Échec de l’intégration réseau C# : " + network.UserMessage);
        if (!full.Success || full.Operation?.Success != true || full.Inventory.Count == 0 || full.Operation.Checks.Count < 4 ||
            !full.Inventory.Any(item => item.Category.StartsWith("Carte graphique", StringComparison.OrdinalIgnoreCase)) || !File.Exists(full.Operation.JournalPath))
            throw new InvalidOperationException("Échec de l’intégration du moteur vérifié ou GPU absent de l’inventaire commun : " + full.Message);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "BASTOS-Operations-SmokeTest.txt"),
            $"OK : analyse matérielle réelle avec GPU présent dans l’inventaire commun, détection ADK en lecture seule ({adkVersion ?? "absent"}), détection WebView2 en lecture seule ({webView.ErrorCode}), lien pilote non officiel refusé par le service C#, huit mesures ICMP réelles vérifiées ({network.State}) ; {full.Inventory.Count} composants ; journaux {full.Operation.OperationId}, {network.OperationId} et {webView.OperationId}. Aucun navigateur ouvert, aucun outil d’installation exécuté, aucune partition modifiée.");
    }
}
