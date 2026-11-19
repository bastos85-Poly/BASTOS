using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed partial class ReinstallViewModel
{
    private IReadOnlyList<WindowsDownloadChoice> catalog = Array.Empty<WindowsDownloadChoice>();
    private NamedChoice? catalogFamily, catalogVersion, catalogLanguage, catalogArchitecture;
    private string? preferredCatalogLanguage;
    private bool populatingCatalogLanguage;
    private WindowsDownloadChoice? catalogImage;
    private bool catalogRefreshing;
    private string catalogStatus = "Source officielle Microsoft · lien généré à chaque téléchargement";
    public ObservableCollection<NamedChoice> CatalogFamilies { get; } = new();
    public ObservableCollection<NamedChoice> CatalogVersions { get; } = new();
    public ObservableCollection<NamedChoice> CatalogLanguages { get; } = new();
    public ObservableCollection<NamedChoice> CatalogArchitectures { get; } = new();
    public ObservableCollection<WindowsDownloadChoice> CatalogImages { get; } = new();
    public bool HasCatalogVariants => CatalogImages.Count > 1;
    public AsyncRelayCommand RefreshCatalogCommand { get; private set; }
    public bool IsCatalogRefreshing
    {
        get => catalogRefreshing;
        private set { SetProperty(ref catalogRefreshing, value); RaisePropertyChanged(nameof(IsCatalogReady)); RaisePropertyChanged(nameof(CanChooseCatalogLanguage)); RefreshActionAvailability(); }
    }
    public bool IsCatalogReady => !IsCatalogRefreshing && !IsBusy;
    public bool CanChooseCatalogLanguage => IsCatalogReady;
    public bool HasCatalogLanguageFallback => catalog.Where(item => MatchesSelectedFamily(item) && item.Version == catalogVersion?.Value)
        .Select(item => item.Language).Distinct().Count() < CatalogLanguages.Count;
    public string CatalogLanguageHint => "Si cette version n’existe pas dans la langue choisie, Bastos sélectionne automatiquement Famille / Pro / Éducation dans cette langue.";
    public string CatalogStatus { get => catalogStatus; private set => SetProperty(ref catalogStatus, value); }
    public NamedChoice? SelectedCatalogFamily
    {
        get => catalogFamily;
        set { if (value != null && !ReferenceEquals(catalogFamily, value)) { catalogFamily = value; RaisePropertyChanged(nameof(SelectedCatalogFamily)); PopulateVersions(); } }
    }
    public NamedChoice? SelectedCatalogVersion
    {
        get => catalogVersion;
        set { if (value != null && !ReferenceEquals(catalogVersion, value)) { catalogVersion = value; RaisePropertyChanged(nameof(SelectedCatalogVersion)); PopulateLanguages(); } }
    }
    public NamedChoice? SelectedCatalogLanguage
    {
        get => catalogLanguage;
        set
        {
            if (value == null || ReferenceEquals(catalogLanguage, value)) return;
            if (!populatingCatalogLanguage && !catalog.Any(item => MatchesSelectedFamily(item) && item.Version == catalogVersion?.Value && item.Language == value.Value))
            {
                var fallback = catalog.Where(item => item.Language == value.Value && item.Version.Contains(" Consumer ", StringComparison.Ordinal))
                    .OrderBy(item => MatchesSelectedFamily(item) ? 0 : item.Family == "Windows 11" ? 1 : 2).FirstOrDefault();
                if (fallback == null)
                {
                    Status = "Aucune ISO Famille / Pro / Éducation disponible dans cette langue.";
                    RaisePropertyChanged(nameof(SelectedCatalogLanguage));
                    return;
                }
                preferredCatalogLanguage = value.Value;
                SelectedCatalogFamily = CatalogFamilies.First(item => item.Value == fallback.Family);
                SelectedCatalogVersion = CatalogVersions.First(item => item.Value == fallback.Version);
                Status = "Langue choisie : " + value.Display + ". Version adaptée automatiquement : " + CatalogVersionLabel(fallback.Version) + ".";
                return;
            }
            catalogLanguage = value;
            if (!populatingCatalogLanguage) preferredCatalogLanguage = value.Value;
            RaisePropertyChanged(nameof(SelectedCatalogLanguage));
            PopulateArchitectures();
        }
    }
    public NamedChoice? SelectedCatalogArchitecture
    {
        get => catalogArchitecture;
        set { if (value != null && !ReferenceEquals(catalogArchitecture, value)) { catalogArchitecture = value; RaisePropertyChanged(nameof(SelectedCatalogArchitecture)); PopulateImages(); } }
    }
    public WindowsDownloadChoice? SelectedCatalogIso
    {
        get => catalogImage;
        set { if (value != null) { catalogImage = value; NotifyCatalogSelection(); } }
    }
    public string CatalogFileName => SelectedCatalogIso==null?"Aucune ISO disponible pour ces choix.":"Le nom exact du fichier sera fourni par Microsoft au démarrage du téléchargement.";
    public string CatalogSelectionSummary => SelectedCatalogIso is { } item
        ? CatalogVersionLabel(item.Version) + " • " + CatalogLanguageLabel(item) + " • " + item.Architecture.ToUpperInvariant() + "\nMicrosoft · téléchargement dans BASTOS"
        : "Sélectionne une version, une langue et une architecture disponibles.";
    public string CatalogCompatibilityHint => SelectedCatalogIso is { } item && (item.Family.StartsWith("Windows 10") || item.Architecture != "x64")
        ? "Téléchargement disponible. La réinstallation interne actuelle de Bastos est prévue pour Windows 11 x64 ; les autres images peuvent être utilisées avec Rufus."
        : "Le catalogue choisit le fichier à télécharger. L’édition contenue dans l’ISO et les options de réinstallation se règlent ensuite dans le module Compte et partitions.";

    private void InitializeDownloadCatalog()
    {
        catalog = WindowsDownloadCatalog.ReadBundled();
        RefreshCatalogCommand = new AsyncRelayCommand(RefreshDownloadCatalog, () => CanChooseLocalIso, () => WaitingReason);
        PopulateFamilies();
    }
    private string CatalogLanguageLabel(WindowsDownloadChoice item) =>
        Languages.FirstOrDefault(language => language.Locale.Equals(item.Locale, StringComparison.OrdinalIgnoreCase))?.Display ?? item.LanguageDisplay;
    private static string CatalogVersionLabel(string version) => version.Contains(" Consumer ", StringComparison.Ordinal)
        ? version.Replace(" Consumer ", " ", StringComparison.Ordinal) + " — Famille / Pro / Éducation" : version;
    private static void Replace(ObservableCollection<NamedChoice> target, IEnumerable<NamedChoice> values)
    {
        var snapshot = values.ToArray();
        target.Clear();
        foreach (var value in snapshot) target.Add(value);
    }
    private void PopulateFamilies()
    {
        string? previous = catalogFamily?.Value;
        Replace(CatalogFamilies, catalog.Select(item => item.Family.StartsWith("Windows 11", StringComparison.Ordinal) ? "Windows 11"
            : item.Family.StartsWith("Windows 10", StringComparison.Ordinal) ? "Windows 10" : item.Family)
            .Distinct().OrderBy(value => value == "Windows 11" ? 0 : 1).Select(value => new NamedChoice(value, value)));
        var selected = CatalogFamilies.FirstOrDefault(item => item.Value == previous) ?? CatalogFamilies.FirstOrDefault();
        SelectedCatalogFamily = selected;
    }
    private void PopulateVersions()
    {
        string? previous = catalogVersion?.Value;
        Replace(CatalogVersions, catalog.Where(MatchesSelectedFamily).Select(item => item.Version).Distinct()
            .OrderBy(value => value)
            .Select(value => new NamedChoice(CatalogVersionLabel(value), value)));
        var selected = CatalogVersions.FirstOrDefault(item => item.Value == previous) ?? CatalogVersions.FirstOrDefault();
        SelectedCatalogVersion = selected;
    }
    private void PopulateLanguages()
    {
        string? previous = preferredCatalogLanguage ?? catalogLanguage?.Value;
        RaisePropertyChanged(nameof(CanChooseCatalogLanguage));
        var available = catalog.Where(item => MatchesSelectedFamily(item) && item.Version == catalogVersion?.Value).ToArray();
        Replace(CatalogLanguages, available
            .DistinctBy(item => item.Language).Select(item => new NamedChoice(CatalogLanguageLabel(item), item.Language)).OrderBy(item => item.Display));
        var supported = CatalogLanguages.Where(language => available.Any(item => item.Language == language.Value)).ToArray();
        var selected = supported.FirstOrDefault(item => item.Value == previous)
            ?? supported.FirstOrDefault(item => item.Value == "French") ?? supported.FirstOrDefault(item => item.Value == "English") ?? supported.FirstOrDefault();
        populatingCatalogLanguage = true;
        try { SelectedCatalogLanguage = selected; }
        finally { populatingCatalogLanguage = false; }
        RaisePropertyChanged(nameof(HasCatalogLanguageFallback));
        RaisePropertyChanged(nameof(CatalogLanguageHint));
    }
    private void PopulateArchitectures()
    {
        string? previous = catalogArchitecture?.Value;
        Replace(CatalogArchitectures, catalog.Where(item => MatchesSelectedFamily(item) && item.Version == catalogVersion?.Value && item.Language == catalogLanguage?.Value)
            .Select(item => item.Architecture).Distinct().OrderBy(value => value == "x64" ? 0 : 1)
            .Select(value => new NamedChoice(value == "x64" ? "64 bits — x64" : value == "x86" ? "32 bits — x86" : "ARM — ARM64", value)));
        SelectedCatalogArchitecture = CatalogArchitectures.FirstOrDefault(item => item.Value == previous) ?? CatalogArchitectures.FirstOrDefault();
    }
    private void PopulateImages()
    {
        string? previous = catalogImage?.FileName;
        var images = catalog.Where(item => MatchesSelectedFamily(item) && item.Version == catalogVersion?.Value &&
            item.Language == catalogLanguage?.Value && item.Architecture == catalogArchitecture?.Value).ToArray();
        CatalogImages.Clear();
        foreach (var image in images) CatalogImages.Add(image);
        catalogImage = images.FirstOrDefault(item => item.FileName == previous) ?? images.FirstOrDefault();
        RaisePropertyChanged(nameof(HasCatalogVariants));
        NotifyCatalogSelection();
    }
    private bool MatchesSelectedFamily(WindowsDownloadChoice item) => catalogFamily?.Value switch
    {
        "Windows 11" => item.Family.StartsWith("Windows 11", StringComparison.Ordinal),
        "Windows 10" => item.Family.StartsWith("Windows 10", StringComparison.Ordinal),
        _ => item.Family == catalogFamily?.Value
    };
    private void NotifyCatalogSelection()
    {
        RaisePropertyChanged(nameof(SelectedCatalogIso));
        RaisePropertyChanged(nameof(CatalogFileName));
        RaisePropertyChanged(nameof(CatalogSelectionSummary));
        RaisePropertyChanged(nameof(CatalogCompatibilityHint));
        DownloadCommand.RaiseCanExecuteChanged();
    }
    private async Task RefreshDownloadCatalog()
    {
        if(IsBusy || IsCatalogRefreshing)return;
        var cancellation=BeginCancellation();cancellation.AllowRead();
        IsCatalogRefreshing = true;
        CatalogStatus = "Lecture des rubriques Windows 11 et Windows 10…";
        try
        {
            var result = await WindowsDownloadCatalog.RefreshAsync(catalog,cancellation.Token);
            if (result.Items.Count > 0) { catalog = result.Items; PopulateFamilies(); }
            CatalogStatus = result.Message;
        }
        catch (OperationCanceledException) { CatalogStatus = "Actualisation annulée. Le catalogue précédent est conservé."; }
        catch (Exception error) { CatalogStatus = "Catalogue précédent conservé : " + error.Message; }
        finally { EndCancellation(cancellation);IsCatalogRefreshing = false; }
    }
    private async Task DownloadCatalogIso()
    {
        if(IsBusy || IsCatalogRefreshing)return;
        var item = SelectedCatalogIso;
        if (item == null) { Status = "Aucune ISO ne correspond à ces choix."; return; }
        await DownloadWindows(item);
    }
    public void RefreshDownloadedIsos()
    {
        if(!IsBusy)RefreshIsos(SelectedIso?.Path);
    }
}
