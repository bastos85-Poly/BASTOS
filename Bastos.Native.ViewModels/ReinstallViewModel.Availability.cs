namespace Bastos.Native.ViewModels;

public sealed partial class ReinstallViewModel
{
    // Pure presentation predicates. Disk, ISO and profile validation still runs
    // in the existing review before any preparation or reboot can be requested.
    public bool CanChooseLocalIso => !IsBusy && !IsCatalogRefreshing;
    private string WaitingReason => IsBusy ? "Une opération est en cours. Attends sa fin avant de continuer."
        : IsCatalogRefreshing ? "Le catalogue se met à jour. Attends la fin du chargement." : "";
    private string IsoActionReason => WaitingReason.Length > 0 ? WaitingReason
        : SelectedIso == null ? "Choisis une ISO à l’étape 2 · Mon ISO pour continuer." : "";
    private string DownloadReason => WaitingReason.Length > 0 ? WaitingReason
        : SelectedCatalogIso == null ? "Choisis une version, une langue et une architecture proposant une ISO." : "";

    private void RefreshActionAvailability()
    {
        RaisePropertyChanged(nameof(CanChooseLocalIso));
        RaisePropertyChanged(nameof(IsCatalogReady));
        RaisePropertyChanged(nameof(CanChooseCatalogLanguage));
        DownloadCommand?.RaiseCanExecuteChanged();
        RefreshIsoCommand?.RaiseCanExecuteChanged();
        RefreshCatalogCommand?.RaiseCanExecuteChanged();
        BuildCommand?.RaiseCanExecuteChanged();
        PrepareUsbCommand?.RaiseCanExecuteChanged();
        PrepareRecoveryCommand?.RaiseCanExecuteChanged();
        CheckRecoveryCompatibilityCommand?.RaiseCanExecuteChanged();
        InitializeRecoveryCommand?.RaiseCanExecuteChanged();
        FinalizeRecoveryCommand?.RaiseCanExecuteChanged();
        BootRecoveryCommand?.RaiseCanExecuteChanged();
        RufusOptionsCommand?.RaiseCanExecuteChanged();
        DeleteIsoCommand?.RaiseCanExecuteChanged();
    }
}
