using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class NetworkDiscoveryViewModel : ObservableObject
{
    private readonly Func<IProgress<WorkerProgress>, Task<HardwareAnalysisResult>> analyze;
    private readonly Func<DriverRecommendation, Task<(bool Success, string Message)>> open;
    private bool busy;
    private string status = "Analyse le PC pour identifier ses cartes réseau et accéder aux pilotes officiels.";

    public NetworkDiscoveryViewModel(ModuleOperationService operations)
        : this(progress => operations.AnalyzeHardwareAsync(progress), recommendation => operations.OpenOfficialDriverAsync(recommendation)) { }

    public NetworkDiscoveryViewModel(Func<IProgress<WorkerProgress>, Task<HardwareAnalysisResult>> analyze,
        Func<DriverRecommendation, Task<(bool Success, string Message)>> open)
    {
        this.analyze = analyze;
        this.open = open;
        AnalyzeCommand = new AsyncRelayCommand(AnalyzeAsync, () => !IsBusy, () => "Une opération matérielle est en cours. Attends sa fin.");
    }

    public ObservableCollection<NetworkDriverCard> Cards { get; } = new();
    public AsyncRelayCommand AnalyzeCommand { get; }
    public string Status { get => status; private set => SetProperty(ref status, value); }
    public bool IsBusy
    {
        get => busy;
        private set
        {
            SetProperty(ref busy, value);
            AnalyzeCommand.RaiseCanExecuteChanged();
            foreach (var card in Cards) card.DownloadCommand.RaiseCanExecuteChanged();
        }
    }

    private async Task AnalyzeAsync()
    {
        IsBusy = true;
        Cards.Clear();
        Status = "Analyse matérielle en cours…";
        try
        {
            var progress = new Progress<WorkerProgress>(item => { if (IsBusy) Status = $"{item.Percent} % — {item.Phase} : {item.Message}"; });
            ApplyAnalysis(await analyze(progress));
        }
        catch (Exception error) { Status = "Analyse impossible : " + error.Message; }
        finally { IsBusy = false; }
    }

    // Also receives the result of the existing Hardware page: no second inventory is necessary.
    public void ApplyAnalysis(HardwareAnalysisResult result)
    {
        Cards.Clear();
        if (!result.Success) { Status = "Analyse impossible : " + result.Message; return; }
        foreach (var gpu in result.Inventory.Where(item => IsNetwork(item.Category)))
        {
            var recommendation = result.Recommendations.FirstOrDefault(item => IsNetwork(item.Category)
                && string.Equals(item.Hardware, gpu.Name, StringComparison.OrdinalIgnoreCase) && !item.Sensitive);
            Cards.Add(new NetworkDriverCard(gpu, recommendation,
                new AsyncRelayCommand(() => OpenAsync(recommendation), () => !IsBusy && recommendation != null, () => IsBusy ? "Une opération matérielle est en cours. Attends sa fin." : "Aucun lien officiel associé. Consulte Mise à jour matériel.")));
        }
        Status = Cards.Count == 0 ? "Aucune carte réseau identifiée. Réessaie l’analyse ou consulte Mise à jour matériel."
            : $"{Cards.Count} carte(s) réseau détectée(s). L’icône ouvre la page officielle de téléchargement, sans installation automatique.";
        if (result.Operation?.State == OperationState.Partial) Status = result.Message + " " + Status;
    }

    private static bool IsNetwork(string category) => category != null && (category.StartsWith("Réseau", StringComparison.OrdinalIgnoreCase) || category.StartsWith("Reseau", StringComparison.OrdinalIgnoreCase) || category.StartsWith("Ethernet", StringComparison.OrdinalIgnoreCase) || category.StartsWith("Wi-Fi", StringComparison.OrdinalIgnoreCase)) && category.IndexOf("Bluetooth", StringComparison.OrdinalIgnoreCase) < 0;

    private async Task OpenAsync(DriverRecommendation recommendation)
    {
        if (recommendation == null || IsBusy) return;
        IsBusy = true;
        Status = "Recherche de la page officielle pour " + recommendation.Hardware + "…";
        try
        {
            var result = await open(recommendation);
            Status = result.Success
                ? result.Message + " Télécharge le pilote réseau correspondant à ta version de Windows sur le site du fabricant."
                : "Ouverture impossible : " + result.Message;
        }
        catch (Exception error) { Status = "Ouverture impossible : " + error.Message; }
        finally { IsBusy = false; }
    }
}

public sealed class NetworkDriverCard
{
    public NetworkDriverCard(HardwareInventoryItem hardware, DriverRecommendation recommendation, AsyncRelayCommand downloadCommand)
    {
        Name = hardware.Name;
        Details = hardware.Details;
        Source = recommendation == null ? "Aucun lien officiel associé : téléchargement indisponible."
            : recommendation.SourceName + " — " + recommendation.Reason;
        DownloadHint = recommendation == null ? Source : "Ouvrir les pilotes officiels pour " + hardware.Name + "\n" + recommendation.OfficialUrl;
        DownloadCommand = downloadCommand;
    }
    public string Name { get; }
    public string Details { get; }
    public string Source { get; }
    public string DownloadHint { get; }
    public AsyncRelayCommand DownloadCommand { get; }
}
