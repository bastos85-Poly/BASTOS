using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class CleanerOptionItem : ObservableObject
{
    public CleanerOption Option { get; }
    public string Id => Option.Id;
    public string Name => Option.Name;
    public string PathText => Option.Path;
    private bool selected = true;
    public bool Selected { get => selected; set => SetProperty(ref selected, value); }
    public CleanerOptionItem(CleanerOption option) { Option = option; }
}

public sealed class CleanerCategoryItem : ObservableObject
{
    public CleanerCategory Category { get; }
    public ObservableCollection<CleanerOptionItem> Options { get; }
    private bool selected;
    private string summary = "À analyser";
    public string Id => Category.Id;
    public string Name => Category.Name;
    public string Description => Category.Description;
    public string Group => Category.Id switch
    {
        "browsers" => "Navigateurs",
        "apps" => "Applications",
        "developer-cache" => "Applications",
        "ai-tools" => "Outils d’IA",
        "games" => "Jeux",
        "shortcuts" => "Raccourcis",
        "privacy-files" => "Traces de confidentialité",
        _ => "Système"
    };
    public bool Selected { get => selected; set => SetProperty(ref selected, value); }
    public string Summary { get => summary; set => SetProperty(ref summary, value); }
    public CleanerCategoryItem(CleanerCategory category, IEnumerable<CleanerOption> options) { Category = category; selected = category.DefaultSelected; Options = new(options.Select(o => new CleanerOptionItem(o))); }
}

public sealed class CleanerFileItem : ObservableObject
{
    public CleanerFile File { get; }
    private bool selected = true;
    public string Id => File.Id;
    public string Name => Path.GetFileName(File.FullPath);
    public string PathText => File.FullPath;
    public string CategoryName { get; }
    public string Size => CleanerViewModel.FormatBytes(File.Length);
    public string Modified => File.LastWriteUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm");
    public bool Selected { get => selected; set => SetProperty(ref selected, value); }
    public CleanerFileItem(CleanerFile file, string categoryName) { File = file; CategoryName = categoryName; }
}

public sealed class CleanerResultGroupItem : ObservableObject
{
    private readonly Action<IReadOnlyList<CleanerFileItem>, bool> applySelection;
    private bool updating;
    private bool expanded;
    private int visibleLimit = 50;
    private IReadOnlyList<CleanerFileItem> visibleItems = Array.Empty<CleanerFileItem>();
    private string search = "";
    private bool selectedOnly;
    public string CategoryId { get; }
    public string Section { get; }
    public string Name { get; }
    public IReadOnlyList<CleanerFileItem> Items { get; }
    public string CountText => $"{Items.Count:N0} éléments";
    public long TotalBytes => Items.Sum(i => i.File.Length);
    public string SizeText => CleanerViewModel.FormatBytes(TotalBytes);
    public int MoreCount => Math.Max(0, Matching().Count() - visibleLimit);
    public bool HasMore => MoreCount > 0;
    public IReadOnlyList<CleanerFileItem> VisibleItems { get => visibleItems; private set => SetProperty(ref visibleItems, value); }
    public bool IsExpanded { get => expanded; set { if (SetProperty(ref expanded, value)) Refresh(); } }
    public bool? Selected
    {
        get { int count = Items.Count(i => i.Selected); return count == 0 ? false : count == Items.Count ? true : null; }
        set { if (!value.HasValue) return; updating = true; try { applySelection(Items, value.Value); } finally { updating = false; } RaisePropertyChanged(nameof(Selected)); Refresh(); }
    }
    public RelayCommand ShowMoreCommand { get; }
    public CleanerResultGroupItem(string categoryId, string section, string name, IReadOnlyList<CleanerFileItem> items, Action<IReadOnlyList<CleanerFileItem>, bool> applySelection)
    {
        CategoryId = categoryId; Section = section; Name = name; Items = items; this.applySelection = applySelection;
        ShowMoreCommand = new(() => { visibleLimit += 50; Refresh(); });
        foreach (var item in items) item.PropertyChanged += (_, e) => { if (!updating && e.PropertyName == nameof(item.Selected)) { RaisePropertyChanged(nameof(Selected)); Refresh(); } };
    }
    private IEnumerable<CleanerFileItem> Matching() => Items.Where(i => (!selectedOnly || i.Selected) && (search.Length == 0 || i.PathText.Contains(search, StringComparison.OrdinalIgnoreCase) || Name.Contains(search, StringComparison.OrdinalIgnoreCase)));
    public void SetFilter(string query, bool onlySelected) { search = query; selectedOnly = onlySelected; if (query.Length > 0) { expanded = true; RaisePropertyChanged(nameof(IsExpanded)); } Refresh(); }
    public bool HasMatches => Matching().Any();
    private void Refresh()
    {
        VisibleItems = IsExpanded ? Matching().Take(visibleLimit).ToArray() : Array.Empty<CleanerFileItem>();
        RaisePropertyChanged(nameof(MoreCount)); RaisePropertyChanged(nameof(HasMore)); RaisePropertyChanged(nameof(CountText)); RaisePropertyChanged(nameof(SizeText));
    }
}

public sealed class CleanerSectionItem : ObservableObject
{
    private int count;
    public string Name { get; }
    public string Description { get; }
    public int Count { get => count; set { if (SetProperty(ref count, value)) RaisePropertyChanged(nameof(CountText)); } }
    public string CountText => Count == 0 ? "" : Count.ToString("N0");
    public CleanerSectionItem(string name, string description) { Name = name; Description = description; }
}

public sealed class CleanerMaintenanceItem : ObservableObject
{
    public MaintenanceAction Action { get; }
    public string Name => Action.Name;
    public string Description => Action.Description;
    private string status = "À analyser séparément";
    public string Status { get => status; set => SetProperty(ref status, value); }
    public MaintenancePreview? Preview { get; set; }
    public CleanerMaintenanceItem(MaintenanceAction action) { Action = action; }
}

public sealed class AdvancedCleanerItem : ObservableObject
{
    private bool selected;
    public string Id { get; }
    public string Name { get; }
    public string PathText { get; }
    public string Detail { get; }
    public string Size { get; }
    public string Section { get; }
    public AdvancedCleanerItem(string id, string name, string path, string detail, string size, string section = "")
    { Id = id; Name = name; PathText = path; Detail = detail; Size = size; Section = section; selected = section is "Environnement" or "Bases de données"; }
    public bool Selected { get => selected; set => SetProperty(ref selected, value); }
}

public sealed class CleanerViewModel : ObservableObject, IDisposable
{
    private readonly SystemCleanerService service;
    private readonly CleanerMaintenanceService maintenance = new();
    private readonly EnvironmentCleanerService environmentCleaner;
    private readonly DatabaseCleanerService databaseCleaner;
    private readonly PrivacyRegistryCleanerService privacyRegistry;
    private readonly HashSet<string> advancedScannedGroups = new(StringComparer.Ordinal);
    private readonly bool integratedScan;
    private bool privacyRegistryScanned;
    private readonly AppPaths paths;
    private readonly Func<string, bool> confirm;
    private CleanerScan? scan;
    private CancellationTokenSource? cancellation;
    private bool busy, hasScan, cleaning, changingSelection, selectedOnly, searchAllCategories;
    private string sort = "Par défaut";
    private string status = "Choisis les catégories, puis lance une analyse.", detail = "", search = "", group = "Tout", exclusionInput = "";
    private int ageDays;
    private CleanerFileItem? selectedFile;
    private string lastRun = "Aucun nettoyage effectué.";
    public ObservableCollection<CleanerCategoryItem> Categories { get; }
    public ObservableCollection<CleanerFileItem> Files { get; } = new();
    public ObservableCollection<CleanerResultGroupItem> ResultGroups { get; } = new();
    public ObservableCollection<CleanerMaintenanceItem> MaintenanceActions { get; }
    public ObservableCollection<AdvancedCleanerItem> AdvancedItems { get; } = new();
    public ObservableCollection<AdvancedCleanerItem> PrivacyRegistryItems { get; } = new();
    public ObservableCollection<string> Exclusions { get; } = new();
    public IReadOnlyList<string> Groups { get; }
    public IReadOnlyList<CleanerSectionItem> Sections { get; }
    public ICollectionView CategoryView { get; }
    public ICollectionView FileView { get; }
    public ICollectionView ResultGroupView { get; }
    public ICollectionView MaintenanceView { get; }
    public ICollectionView AdvancedView { get; }
    public AsyncRelayCommand ScanCommand { get; }
    public AsyncRelayCommand CleanCommand { get; }
    public RelayCommand CancelCommand { get; }
    public RelayCommand RecommendedCommand { get; }
    public RelayCommand SelectVisibleCommand { get; }
    public RelayCommand DeselectVisibleCommand { get; }
    public RelayCommand AddExclusionCommand { get; }
    public RelayCommand ExcludeFileCommand { get; }
    public RelayCommand RemoveExclusionCommand { get; }
    public RelayCommand CopyPathCommand { get; }
    public RelayCommand OpenFolderCommand { get; }
    public AsyncRelayCommand PreviewMaintenanceCommand { get; }
    public AsyncRelayCommand RunMaintenanceCommand { get; }
    public AsyncRelayCommand ScanAdvancedCommand { get; }
    public AsyncRelayCommand CleanAdvancedCommand { get; }
    public AsyncRelayCommand ScanPrivacyRegistryCommand { get; }
    public AsyncRelayCommand CleanPrivacyRegistryCommand { get; }
    private CleanerMaintenanceItem? selectedMaintenance;
    public CleanerMaintenanceItem? SelectedMaintenance { get => selectedMaintenance; set { SetProperty(ref selectedMaintenance, value); PreviewMaintenanceCommand.RaiseCanExecuteChanged(); RunMaintenanceCommand.RaiseCanExecuteChanged(); } }
    public IReadOnlyList<string> SortChoices { get; } = new[] { "Par défaut", "Taille décroissante", "Taille croissante" };
    public string Sort { get => sort; set { if (SetProperty(ref sort, value)) { FileView.SortDescriptions.Clear(); ResultGroupView.SortDescriptions.Clear(); if (value != "Par défaut") { var direction = value == "Taille croissante" ? ListSortDirection.Ascending : ListSortDirection.Descending; FileView.SortDescriptions.Add(new SortDescription("File.Length", direction)); ResultGroupView.SortDescriptions.Add(new SortDescription(nameof(CleanerResultGroupItem.TotalBytes), direction)); } } } }
    public bool SelectedOnly { get => selectedOnly; set { if (SetProperty(ref selectedOnly, value)) { FileView.Refresh(); RefreshResultGroups(); } } }
    public bool SearchAllCategories { get => searchAllCategories; set { if (SetProperty(ref searchAllCategories, value)) { FileView.Refresh(); RefreshResultGroups(); } } }
    private string? selectedExclusion;
    public string? SelectedExclusion { get => selectedExclusion; set { SetProperty(ref selectedExclusion, value); RemoveExclusionCommand.RaiseCanExecuteChanged(); } }
    public CleanerFileItem? SelectedFile { get => selectedFile; set { SetProperty(ref selectedFile, value); ExcludeFileCommand.RaiseCanExecuteChanged(); CopyPathCommand.RaiseCanExecuteChanged(); OpenFolderCommand.RaiseCanExecuteChanged(); } }
    public bool IsBusy { get => busy; private set { SetProperty(ref busy, value); RaisePropertyChanged(nameof(IsIdle)); RaiseCommands(); } }
    public bool IsIdle => !IsBusy;
    public bool IsCleaning => cleaning;
    public bool HasScan { get => hasScan; private set { SetProperty(ref hasScan, value); RaisePropertyChanged(nameof(HasNoScan)); } }
    public bool HasNoScan => !HasScan;
    public string Status { get => status; private set => SetProperty(ref status, value); }
    public string Detail { get => detail; private set => SetProperty(ref detail, value); }
    public string LastRun { get => lastRun; private set => SetProperty(ref lastRun, value); }
    public string Group { get => group; set { if (SetProperty(ref group, value)) { search = ""; selectedOnly = false; searchAllCategories = false; RaisePropertyChanged(nameof(Search)); RaisePropertyChanged(nameof(SelectedOnly)); RaisePropertyChanged(nameof(SearchAllCategories)); CategoryView.Refresh(); FileView.Refresh(); RefreshResultGroups(); MaintenanceView.Refresh(); AdvancedView.Refresh(); SelectedMaintenance = MaintenanceView.Cast<CleanerMaintenanceItem>().FirstOrDefault(); RaisePropertyChanged(nameof(IsFileSection)); RaisePropertyChanged(nameof(IsSpecialSection)); RaisePropertyChanged(nameof(IsAdvancedSection)); RaisePropertyChanged(nameof(IsMaintenanceSection)); RaisePropertyChanged(nameof(IsCorbeille)); RaisePropertyChanged(nameof(IsSystem)); RaisePropertyChanged(nameof(IsEnvironment)); RaisePropertyChanged(nameof(IsDatabase)); RaisePropertyChanged(nameof(IsPrivacy)); RaisePropertyChanged(nameof(SectionIntro)); RaisePropertyChanged(nameof(AdvancedSelectionText)); RaisePropertyChanged(nameof(PrivacySelectionText)); RaiseCommands(); } } }
    public bool IsFileSection => Group is not ("Corbeille" or "Environnement" or "Bases de données");
    public bool IsSpecialSection => !IsFileSection;
    public bool IsAdvancedSection => Group is "Environnement" or "Bases de données";
    public bool IsMaintenanceSection => Group is "Système" or "Corbeille";
    public bool IsCorbeille => Group == "Corbeille";
    public bool IsSystem => Group == "Système";
    public bool IsEnvironment => Group == "Environnement";
    public bool IsDatabase => Group == "Bases de données";
    public bool IsPrivacy => Group == "Traces de confidentialité";
    public string SectionIntro => Group switch
    {
        "Système" => "Choisis les caches et rapports Windows à analyser. Les options sensibles sont décochées par défaut.",
        "Navigateurs" => "Caches des profils détectés. Mots de passe, cookies et historique sont conservés.",
        "Applications" => "Caches et journaux des applications détectées.",
        "Outils d’IA" => "Caches des assistants d’IA. Modèles et conversations restent en place.",
        "Jeux" => "Caches des lanceurs et journaux de jeu ; les sauvegardes sont conservées.",
        "Corbeille" => "Vider la corbeille exige une analyse et une confirmation séparées.",
        "Raccourcis" => "Seuls les raccourcis .lnk dont la cible locale est absente sont proposés.",
        "Environnement" => "Entrées PATH et variables d’environnement obsolètes.",
        "Bases de données" => "Optimisation des bases SQLite détectées.",
        _ => "Traces d’activité Windows. Cette suppression est facultative et décochée par défaut."
    };
    public string AdvancedSelectionText => $"{AdvancedItems.Count(i => i.Section == Group && i.Selected):N0} sélectionnés sur {AdvancedItems.Count(i => i.Section == Group):N0}";
    public string PrivacySelectionText => $"{PrivacyRegistryItems.Count(i => i.Selected):N0} listes sélectionnées sur {PrivacyRegistryItems.Count:N0}";
    public string Search { get => search; set { if (SetProperty(ref search, value)) { FileView.Refresh(); AdvancedView.Refresh(); RefreshResultGroups(); } } }
    public int AgeDays { get => ageDays; set { int days = Math.Clamp(value, 0, 365); if (SetProperty(ref ageDays, days)) InvalidateScan(); } }
    public string ExclusionInput { get => exclusionInput; set { SetProperty(ref exclusionInput, value); AddExclusionCommand.RaiseCanExecuteChanged(); } }
    public string TotalText => FormatBytes(Files.Sum(f => f.File.Length));
    public string SelectionText => $"{Files.Count(f => f.Selected):N0} fichiers · {FormatBytes(Files.Where(f => f.Selected).Sum(f => f.File.Length))}";
    public string CountText => $"{Files.Count:N0} fichiers détectés";
    public string CleanHint => IsBusy ? "Attends la fin de l’opération." : scan == null ? "Une nouvelle analyse est nécessaire avant de nettoyer." : !scan.Complete ? "Réduis les catégories puis relance l’analyse : la limite d’inventaire a été atteinte." : Files.Any(f => f.Selected) ? "La suppression définitive demandera une confirmation." : "Sélectionne au moins un fichier dans les résultats.";

    public CleanerViewModel(AppPaths paths, SystemCleanerService? service = null, Func<string, bool>? confirm = null,
        EnvironmentCleanerService? environmentCleaner = null, DatabaseCleanerService? databaseCleaner = null,
        PrivacyRegistryCleanerService? privacyRegistry = null, bool? integratedScan = null)
    {
        this.paths = paths; this.integratedScan = integratedScan ?? (service == null); this.service = service ?? new SystemCleanerService();
        this.environmentCleaner = environmentCleaner ?? new(); this.databaseCleaner = databaseCleaner ?? new(); this.privacyRegistry = privacyRegistry ?? new();
        this.confirm = confirm ?? (text => MessageBox.Show(Application.Current.MainWindow, text, "Nettoyeur — confirmer la suppression", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes);
        Categories = new(this.service.Catalog.Select(c => new CleanerCategoryItem(c, this.service.Options.Where(o => o.CategoryId == c.Id))));
        MaintenanceActions = new(maintenance.Catalog.Select(a => new CleanerMaintenanceItem(a)));
        Groups = new[] { "Système", "Navigateurs", "Applications", "Outils d’IA", "Jeux", "Corbeille", "Raccourcis", "Environnement", "Bases de données", "Traces de confidentialité" };
        Sections = new[] {
            new CleanerSectionItem("Système", "Temporaires, journaux, caches, mises à jour"),
            new CleanerSectionItem("Navigateurs", "Caches des profils uniquement"),
            new CleanerSectionItem("Applications", "Caches et outils de développement"),
            new CleanerSectionItem("Outils d’IA", "Caches et journaux des assistants"),
            new CleanerSectionItem("Jeux", "Lanceurs et caches de jeux"),
            new CleanerSectionItem("Corbeille", "Fichiers supprimés"),
            new CleanerSectionItem("Raccourcis", "Liens cassés"),
            new CleanerSectionItem("Environnement", "Entrées PATH obsolètes"),
            new CleanerSectionItem("Bases de données", "Bases SQLite à optimiser"),
            new CleanerSectionItem("Traces de confidentialité", "Activité récente facultative")
        };
        group = "Système";
        CategoryView = CollectionViewSource.GetDefaultView(Categories);
        CategoryView.Filter = item => Group == "Tout" || ((CleanerCategoryItem)item).Group == Group;
        FileView = CollectionViewSource.GetDefaultView(Files);
        FileView.Filter = item => { var f = (CleanerFileItem)item; return (!SelectedOnly || f.Selected) && (SearchAllCategories || Group == "Tout" || Categories.Any(c => c.Id == f.File.CategoryId && c.Group == Group)) && (Search.Length == 0 || f.PathText.Contains(Search, StringComparison.OrdinalIgnoreCase) || f.CategoryName.Contains(Search, StringComparison.OrdinalIgnoreCase)); };
        ResultGroupView = CollectionViewSource.GetDefaultView(ResultGroups);
        ResultGroupView.Filter = item => { var g = (CleanerResultGroupItem)item; return (SearchAllCategories || Group == "Tout" || g.Section == Group) && g.HasMatches; };
        MaintenanceView = CollectionViewSource.GetDefaultView(MaintenanceActions);
        MaintenanceView.Filter = item => Group == "Corbeille" ? ((CleanerMaintenanceItem)item).Action.Id == "recycle-bin" : Group == "Système" && ((CleanerMaintenanceItem)item).Action.Id != "recycle-bin";
        AdvancedView = CollectionViewSource.GetDefaultView(AdvancedItems);
        AdvancedView.Filter = item => { var advanced = (AdvancedCleanerItem)item; return advanced.Section == Group && (Search.Length == 0 || advanced.PathText.Contains(Search, StringComparison.OrdinalIgnoreCase) || advanced.Name.Contains(Search, StringComparison.OrdinalIgnoreCase)); };
        ScanCommand = new(ScanAllAsync, () => IsIdle && Categories.Any(c => c.Selected), () => "Choisis au moins une catégorie.");
        CleanCommand = new(CleanAsync, () => IsIdle && scan is { Complete: true } && Files.Any(f => f.Selected), () => CleanHint);
        CancelCommand = new(() => { cancellation?.Cancel(); Status = "Arrêt demandé, attente de la fin du fichier en cours…"; }, () => IsBusy);
        RecommendedCommand = new(() => { changingSelection = true; foreach (var c in Categories) { c.Selected = c.Category.DefaultSelected; foreach (var option in c.Options) option.Selected = true; } ageDays = 0; RaisePropertyChanged(nameof(AgeDays)); changingSelection = false; InvalidateScan(); }, () => IsIdle);
        SelectVisibleCommand = new(() => SelectVisible(true), () => IsIdle && HasScan);
        DeselectVisibleCommand = new(() => SelectVisible(false), () => IsIdle && HasScan);
        AddExclusionCommand = new(AddExclusion, () => IsIdle && !string.IsNullOrWhiteSpace(ExclusionInput));
        ExcludeFileCommand = new(() => { if (SelectedFile != null) { ExclusionInput = SelectedFile.PathText; AddExclusion(); } }, () => IsIdle && SelectedFile != null);
        RemoveExclusionCommand = new(() => { if (SelectedExclusion != null) { Exclusions.Remove(SelectedExclusion); InvalidateScan(); SavePreferences(); } }, () => IsIdle && SelectedExclusion != null);
        CopyPathCommand = new(() => { try { if (SelectedFile != null) Clipboard.SetText(SelectedFile.PathText); } catch (Exception e) { Status = "Copie impossible : " + e.Message; } }, () => IsIdle && SelectedFile != null);
        OpenFolderCommand = new(() => { try { if (SelectedFile != null) { var start = new ProcessStartInfo("explorer.exe") { UseShellExecute = false }; start.ArgumentList.Add("/select," + SelectedFile.PathText); Process.Start(start); } } catch (Exception e) { Status = "Ouverture impossible : " + e.Message; } }, () => IsIdle && SelectedFile != null);
        PreviewMaintenanceCommand = new(PreviewMaintenanceAsync, () => IsIdle && SelectedMaintenance != null);
        RunMaintenanceCommand = new(RunMaintenanceAsync, () => IsIdle && SelectedMaintenance?.Preview?.CanExecute == true);
        ScanAdvancedCommand = new(ScanAdvancedAsync, () => IsIdle && (IsEnvironment || IsDatabase));
        CleanAdvancedCommand = new(CleanAdvancedAsync, () => IsIdle && advancedScannedGroups.Contains(Group) && AdvancedItems.Any(i => i.Section == Group && i.Selected));
        ScanPrivacyRegistryCommand = new(ScanPrivacyRegistryAsync, () => IsIdle && IsPrivacy);
        CleanPrivacyRegistryCommand = new(CleanPrivacyRegistryAsync, () => IsIdle && IsPrivacy && privacyRegistryScanned && PrivacyRegistryItems.Any(i => i.Selected));
        SelectedMaintenance = MaintenanceView.Cast<CleanerMaintenanceItem>().FirstOrDefault();
        LoadPreferences();
        foreach (var c in Categories) c.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(c.Selected) && !changingSelection) InvalidateScan(); };
        foreach (var option in Categories.SelectMany(c => c.Options)) option.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(option.Selected) && !changingSelection) InvalidateScan(); };
    }

    public static string FormatBytes(long bytes) { string[] units = { "o", "Ko", "Mo", "Go", "To" }; double value = bytes; int unit = 0; while (value >= 1024 && unit < units.Length - 1) { value /= 1024; unit++; } return $"{value:0.##} {units[unit]}"; }
    private void RaiseCommands()
    {
        ScanCommand.RaiseCanExecuteChanged(); CleanCommand.RaiseCanExecuteChanged(); CancelCommand.RaiseCanExecuteChanged(); RecommendedCommand.RaiseCanExecuteChanged();
        SelectVisibleCommand.RaiseCanExecuteChanged(); DeselectVisibleCommand.RaiseCanExecuteChanged(); AddExclusionCommand.RaiseCanExecuteChanged(); ExcludeFileCommand.RaiseCanExecuteChanged(); RemoveExclusionCommand.RaiseCanExecuteChanged();
        CopyPathCommand.RaiseCanExecuteChanged(); OpenFolderCommand.RaiseCanExecuteChanged();
        PreviewMaintenanceCommand.RaiseCanExecuteChanged(); RunMaintenanceCommand.RaiseCanExecuteChanged();
        ScanAdvancedCommand.RaiseCanExecuteChanged(); CleanAdvancedCommand.RaiseCanExecuteChanged();
        ScanPrivacyRegistryCommand.RaiseCanExecuteChanged(); CleanPrivacyRegistryCommand.RaiseCanExecuteChanged();
        RaisePropertyChanged(nameof(CleanHint));
    }
    private void UpdateSelection() { RaisePropertyChanged(nameof(TotalText)); RaisePropertyChanged(nameof(SelectionText)); RaisePropertyChanged(nameof(CountText)); if (SelectedOnly) RefreshResultGroups(); RaiseCommands(); }
    private void RefreshResultGroups() { foreach (var g in ResultGroups) g.SetFilter(Search, SelectedOnly); ResultGroupView?.Refresh(); }
    private void UpdateSectionCounts() { foreach (var section in Sections) section.Count = Files.Count(f => Categories.Any(c => c.Id == f.File.CategoryId && c.Group == section.Name)) + AdvancedItems.Count(i => i.Section == section.Name) + (section.Name == "Traces de confidentialité" ? PrivacyRegistryItems.Count : 0); }
    private void SelectVisible(bool value) { changingSelection = true; foreach (var file in FileView.Cast<CleanerFileItem>().ToArray()) file.Selected = value; changingSelection = false; if (SelectedOnly) FileView.Refresh(); UpdateSelection(); }
    private void SetGroupSelection(IReadOnlyList<CleanerFileItem> items, bool value) { changingSelection = true; try { foreach (var item in items) item.Selected = value; } finally { changingSelection = false; } if (SelectedOnly) FileView.Refresh(); UpdateSelection(); }
    private void InvalidateScan()
    {
        scan = null; HasScan = false; Files.Clear(); ResultGroups.Clear(); SelectedFile = null; UpdateSectionCounts();
        foreach (var c in Categories) c.Summary = "À analyser";
        Status = "Options modifiées. Relance l’analyse pour actualiser la sélection."; Detail = ""; UpdateSelection(); SavePreferences();
        foreach (var item in MaintenanceActions) { item.Preview = null; item.Status = "À analyser séparément"; }
        AdvancedItems.Clear(); advancedScannedGroups.Clear(); RaisePropertyChanged(nameof(AdvancedSelectionText));
        PrivacyRegistryItems.Clear(); privacyRegistryScanned = false; RaisePropertyChanged(nameof(PrivacySelectionText));
        RunMaintenanceCommand.RaiseCanExecuteChanged();
    }
    private async Task PreviewMaintenanceAsync()
    {
        var item = SelectedMaintenance; if (item == null || IsBusy) return;
        item.Preview = null; IsBusy = true; cancellation = new();
        Status = "Analyse de maintenance Windows…";
        try { var preview = await maintenance.PreviewAsync(item.Action.Id, Exclusions.ToArray(), cancellation.Token); item.Preview = preview; item.Status = preview.Status; Detail = string.Join(Environment.NewLine, preview.Details); Status = item.Name + " — " + preview.Status; }
        catch (OperationCanceledException) { item.Status = "Analyse annulée."; Status = item.Status; }
        catch (Exception e) { item.Status = "Analyse impossible : " + e.Message; Status = item.Status; }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; RunMaintenanceCommand.RaiseCanExecuteChanged(); }
    }
    private async Task RunMaintenanceAsync()
    {
        var item = SelectedMaintenance; var preview = item?.Preview;
        if (item == null || preview?.CanExecute != true || IsBusy) return;
        string measured = preview.ItemCount.HasValue ? $"{preview.ItemCount:N0} éléments, {FormatBytes(preview.EstimatedBytes ?? 0)} observés" : "volume récupérable inconnu";
        if (!confirm($"Lancer « {item.Name} » ?\n\n{item.Description}\n\nAnalyse : {measured}.\n\nCette action Windows peut être irréversible. Le résultat sera vérifié après exécution.")) return;
        IsBusy = true; cancellation = new(); item.Preview = null; RunMaintenanceCommand.RaiseCanExecuteChanged();
        Status = "Maintenance Windows en cours…";
        OperationResult? report = null;
        try
        {
            report = await BeginJournalAsync("Nettoyeur — " + item.Name);
            var result = await maintenance.ExecuteAsync(preview, cancellation.Token);
            item.Status = result.Message; Status = item.Name + " — " + result.Message;
            Detail = string.Join(Environment.NewLine, result.Details);
            LastRun = $"{DateTime.Now:dd/MM/yyyy HH:mm} · {Status}";
            await EndJournalAsync(report, result.Status switch { MaintenanceStatus.Verified => OperationState.Succeeded, MaintenanceStatus.Partial => OperationState.Partial, MaintenanceStatus.Cancelled => OperationState.Cancelled, MaintenanceStatus.Failed => OperationState.Failed, _ => OperationState.Unconfirmed }, Status, Detail);
            SavePreferences();
        }
        catch (Exception e) { item.Status = "Résultat non confirmé : " + e.Message; Status = item.Status; if (report != null) try { await EndJournalAsync(report, OperationState.Unconfirmed, Status, e.Message); } catch { } }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; }
    }
    private bool IsExcludedAdvanced(string path)
    {
        try
        {
            if (!Path.IsPathFullyQualified(path)) return false;
            string full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
            return Exclusions.Any(ex => full.Equals(ex.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase) || full.StartsWith(ex.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase));
        }
        catch { return true; }
    }
    private async Task ScanAdvancedAsync()
    {
        string section = Group; if (IsBusy || section is not ("Environnement" or "Bases de données")) return;
        IsBusy = true; cancellation = new();
        Status = "Analyse de « " + section + " »…";
        try
        {
            await PopulateAdvancedAsync(section, cancellation.Token);
            Status = $"Analyse terminée — {AdvancedItems.Count(i => i.Section == section):N0} éléments proposés dans {section}.";
            if (section == "Bases de données") Detail = "Le volume affiché est une estimation. Les bases actives et les fichiers WAL sont ignorés. Une copie SQLite est conservée avant l’optimisation.";
            else Detail = "Les valeurs sont lues dans le Registre. Chaque valeur est revérifiée et sauvegardée avant toute modification.";
        }
        catch (OperationCanceledException) { Status = "Analyse annulée. Aucune modification."; }
        catch (Exception e) { Status = "Analyse impossible : " + e.Message; Detail = e.ToString(); }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; RaisePropertyChanged(nameof(AdvancedSelectionText)); }
    }
    private async Task PopulateAdvancedAsync(string section, CancellationToken token)
    {
        foreach (var old in AdvancedItems.Where(i => i.Section == section).ToArray()) AdvancedItems.Remove(old);
        advancedScannedGroups.Remove(section);
        if (section == "Environnement")
        {
            var entries = await environmentCleaner.ScanAsync(token);
            foreach (var entry in entries.Where(e => !IsExcludedAdvanced(e.Value)))
                AddAdvancedItem(new(entry.Id, entry.IsPathEntry ? "Entrée PATH obsolète" : entry.Name + " obsolète", entry.Value, entry.Scope + " · " + entry.Name, "—", section));
        }
        else if (section == "Bases de données")
        {
            var entries = await databaseCleaner.ScanAsync(token);
            foreach (var entry in entries.Where(e => !IsExcludedAdvanced(e.Path)))
                AddAdvancedItem(new(entry.Id, entry.Application, entry.Path, "Base SQLite · " + FormatBytes(entry.Size), "≈ " + FormatBytes(entry.EstimatedWaste), section));
        }
        else throw new ArgumentException("Rubrique spécialisée inconnue.", nameof(section));
        advancedScannedGroups.Add(section); AdvancedView.Refresh(); UpdateSectionCounts(); RaisePropertyChanged(nameof(AdvancedSelectionText)); RaiseCommands();
    }
    private void AddAdvancedItem(AdvancedCleanerItem item)
    {
        item.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(item.Selected)) { RaisePropertyChanged(nameof(AdvancedSelectionText)); CleanAdvancedCommand.RaiseCanExecuteChanged(); } };
        AdvancedItems.Add(item);
    }
    private async Task CleanAdvancedAsync()
    {
        string section = Group; if (IsBusy || !advancedScannedGroups.Contains(section)) return;
        string[] ids = AdvancedItems.Where(i => i.Section == section && i.Selected).Select(i => i.Id).ToArray(); if (ids.Length == 0) return;
        string action = section == "Environnement" ? "retirer du Registre" : "optimiser par SQLite VACUUM";
        if (!confirm($"{action} {ids.Length:N0} éléments de « {section} » ?\n\nUne sauvegarde sera créée avant l’action. Les entrées modifiées ou utilisées depuis l’analyse seront conservées. Vérifie la sélection avant de poursuivre.")) return;
        advancedScannedGroups.Remove(section); IsBusy = true; cancellation = new(); Status = "Opération en cours…";
        OperationResult? report = null;
        try
        {
            report = await BeginJournalAsync("Nettoyeur — " + section);
            string backups = Path.Combine(paths.StateRoot, "CleanerBackups");
            if (section == "Environnement")
            {
                var result = await environmentCleaner.CleanAsync(ids, backups, cancellation.Token);
                Status = $"Environnement — {result.Removed:N0} entrées retirées, {result.Skipped:N0} ignorées.";
                Detail = "Sauvegarde : " + result.BackupPath + Environment.NewLine + string.Join(Environment.NewLine, result.Errors);
                await EndJournalAsync(report, result.Skipped > 0 ? OperationState.Partial : OperationState.Succeeded, Status, Detail);
            }
            else
            {
                var result = await databaseCleaner.CleanAsync(ids, backups, cancellation.Token);
                Status = $"Bases de données — {result.Optimized:N0} optimisées, {FormatBytes(result.BytesRecovered)} récupérés, {result.Skipped:N0} ignorées.";
                Detail = "Sauvegardes : " + string.Join(", ", result.Backups) + Environment.NewLine + string.Join(Environment.NewLine, result.Errors);
                await EndJournalAsync(report, result.Skipped > 0 ? OperationState.Partial : OperationState.Succeeded, Status, Detail);
            }
            LastRun = $"{DateTime.Now:dd/MM/yyyy HH:mm} · {Status}"; SavePreferences(); foreach (var item in AdvancedItems.Where(i => i.Section == section).ToArray()) AdvancedItems.Remove(item); UpdateSectionCounts();
        }
        catch (Exception e) { Status = "Résultat non confirmé : " + e.Message; Detail = e.ToString(); if (report != null) try { await EndJournalAsync(report, OperationState.Unconfirmed, Status, e.Message); } catch { } }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; RaisePropertyChanged(nameof(AdvancedSelectionText)); }
    }
    private async Task ScanPrivacyRegistryAsync()
    {
        if (!IsPrivacy || IsBusy) return;
        IsBusy = true; cancellation = new(); Status = "Analyse des listes d’activité Windows…";
        try
        {
            await PopulatePrivacyRegistryAsync(cancellation.Token);
            Status = $"{PrivacyRegistryItems.Count:N0} listes de confidentialité détectées. Aucune n’est présélectionnée.";
            Detail = "Historique Exécuter, adresses, recherches et listes récentes de l’Explorateur. Une sauvegarde des valeurs est créée avant suppression.";
        }
        catch (OperationCanceledException) { Status = "Analyse annulée. Aucune modification."; }
        catch (Exception e) { Status = "Analyse du Registre impossible : " + e.Message; Detail = e.ToString(); }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; RaisePropertyChanged(nameof(PrivacySelectionText)); }
    }
    private async Task PopulatePrivacyRegistryAsync(CancellationToken token)
    {
        PrivacyRegistryItems.Clear(); privacyRegistryScanned = false;
        var entries = await privacyRegistry.ScanAsync(token);
        foreach (var entry in entries)
        {
            var item = new AdvancedCleanerItem(entry.Id, entry.Name, entry.RegistryPath, $"{entry.Count:N0} entrées", "Registre", "Traces de confidentialité");
            item.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(item.Selected)) { RaisePropertyChanged(nameof(PrivacySelectionText)); CleanPrivacyRegistryCommand.RaiseCanExecuteChanged(); } };
            PrivacyRegistryItems.Add(item);
        }
        privacyRegistryScanned = true; UpdateSectionCounts(); RaisePropertyChanged(nameof(PrivacySelectionText)); RaiseCommands();
    }
    private async Task CleanPrivacyRegistryAsync()
    {
        if (!IsPrivacy || !privacyRegistryScanned || IsBusy) return;
        string[] ids = PrivacyRegistryItems.Where(i => i.Selected).Select(i => i.Id).ToArray(); if (ids.Length == 0) return;
        if (!confirm($"Effacer {ids.Length:N0} listes d’activité Windows sélectionnées ?\n\nLes valeurs actuelles seront sauvegardées avant suppression. Cette opération ne touche pas aux mots de passe ni à l’historique des navigateurs.")) return;
        privacyRegistryScanned = false; IsBusy = true; cancellation = new(); Status = "Effacement des listes sélectionnées…";
        OperationResult? report = null;
        try
        {
            report = await BeginJournalAsync("Nettoyeur — Traces du Registre");
            var result = await privacyRegistry.CleanAsync(ids, Path.Combine(paths.StateRoot, "CleanerBackups"), cancellation.Token);
            Status = $"Traces du Registre — {result.ClearedGroups:N0} listes effacées, {result.SkippedGroups:N0} ignorées.";
            Detail = "Sauvegardes : " + string.Join(", ", result.Backups) + Environment.NewLine + string.Join(Environment.NewLine, result.Errors);
            await EndJournalAsync(report, result.SkippedGroups > 0 ? OperationState.Partial : OperationState.Succeeded, Status, Detail);
            LastRun = $"{DateTime.Now:dd/MM/yyyy HH:mm} · {Status}"; SavePreferences(); PrivacyRegistryItems.Clear(); UpdateSectionCounts();
        }
        catch (Exception e) { Status = "Résultat non confirmé : " + e.Message; Detail = e.ToString(); if (report != null) try { await EndJournalAsync(report, OperationState.Unconfirmed, Status, e.Message); } catch { } }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; RaisePropertyChanged(nameof(PrivacySelectionText)); }
    }
    private void AddExclusion()
    {
        try { var path = ExclusionInput.Trim().Trim('"'); if (!Path.IsPathFullyQualified(path)) throw new ArgumentException("Indique un chemin complet de fichier ou de dossier."); path = Path.GetFullPath(path); if (!Exclusions.Contains(path, StringComparer.OrdinalIgnoreCase)) Exclusions.Add(path); ExclusionInput = ""; InvalidateScan(); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or IOException) { Status = e.Message; }
    }
    public async Task ScanAsync()
    {
        if (IsBusy) return;
        scan = null; HasScan = false; Files.Clear(); ResultGroups.Clear(); SelectedFile = null; UpdateSectionCounts(); Detail = ""; IsBusy = true;
        cancellation = new(); Status = "Analyse des fichiers supprimables…"; UpdateSelection();
        try
        {
            var result = await service.ScanAsync(Categories.Where(c => c.Selected).Select(c => c.Id).ToArray(), Exclusions.ToArray(), AgeDays, new Progress<string>(message => Status = message), cancellation.Token, Categories.Where(c => c.Selected).SelectMany(c => c.Options.Where(o => o.Selected).Select(o => o.Id)).ToArray());
            scan = result;
            foreach (var file in result.Files) { var item = new CleanerFileItem(file, Categories.First(c => c.Id == file.CategoryId).Name) { Selected = file.CategoryId is not ("privacy-files" or "shader-cache" or "prefetch") }; item.PropertyChanged += (_, _) => { if (!changingSelection) UpdateSelection(); }; Files.Add(item); }
            foreach (var group in Files.GroupBy(f => (f.File.CategoryId, f.File.Root)))
            {
                var first = group.First();
                string name = service.Options.FirstOrDefault(o => o.CategoryId == group.Key.CategoryId && o.Path.Equals(group.Key.Root, StringComparison.OrdinalIgnoreCase))?.Name ?? Path.GetFileName(group.Key.Root);
                ResultGroups.Add(new CleanerResultGroupItem(group.Key.CategoryId, Categories.First(c => c.Id == group.Key.CategoryId).Group, name, group.ToArray(), SetGroupSelection));
            }
            RefreshResultGroups();
            UpdateSectionCounts();
            foreach (var c in Categories) { var matches = result.Files.Where(f => f.CategoryId == c.Id).ToArray(); c.Summary = c.Selected ? $"{matches.Length:N0} fichiers · {FormatBytes(matches.Sum(f => f.Length))}" : "Non analysé"; }
            HasScan = true; Detail = string.Join(Environment.NewLine, result.Warnings);
            Status = (!result.Complete ? "Analyse partielle" : result.Warnings.Count > 0 ? "Analyse terminée avec éléments ignorés" : "Analyse terminée") + $" — {CountText}, {TotalText}.";
            if (Files.Count == 0) Status += " Aucun fichier supprimable dans les catégories choisies.";
        }
        catch (OperationCanceledException) { Status = "Analyse arrêtée. Aucun fichier supprimé."; }
        catch (Exception e) { Status = "L’analyse a échoué. Aucun nettoyage lancé."; Detail = e.Message; }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; UpdateSelection(); }
    }
    public async Task ScanAllAsync()
    {
        await ScanAsync();
        // Fixture callers use ScanAsync directly. The real page's Analyser command also
        // inventories environment, SQLite and private registry lists, as Kudu does.
        if (!integratedScan || !HasScan || IsBusy) return;
        IsBusy = true; cancellation = new();
        var issues = new List<string>();
        try
        {
            foreach (string section in new[] { "Environnement", "Bases de données" })
            {
                cancellation.Token.ThrowIfCancellationRequested(); Status = "Analyse : " + section;
                try { await PopulateAdvancedAsync(section, cancellation.Token); }
                catch (OperationCanceledException) { throw; }
                catch (Exception e) { issues.Add(section + " : " + e.Message); }
            }
            cancellation.Token.ThrowIfCancellationRequested(); Status = "Analyse : traces de confidentialité";
            try { await PopulatePrivacyRegistryAsync(cancellation.Token); }
            catch (OperationCanceledException) { throw; }
            catch (Exception e) { issues.Add("Traces de confidentialité : " + e.Message); }
            Status = $"Analyse terminée — {CountText}, {TotalText}. {AdvancedItems.Count + PrivacyRegistryItems.Count:N0} éléments spécialisés détectés.";
            if (issues.Count > 0) Detail = (Detail.Length == 0 ? "" : Detail + Environment.NewLine) + string.Join(Environment.NewLine, issues);
        }
        catch (OperationCanceledException) { Status = "Analyse spécialisée arrêtée. Aucun élément spécialisé supprimé."; }
        finally { cancellation.Dispose(); cancellation = null; IsBusy = false; UpdateSectionCounts(); RaiseCommands(); }
    }
    public async Task CleanAsync()
    {
        var snapshot = scan; if (IsBusy || snapshot == null) return;
        var selected = Files.Where(f => f.Selected).ToArray(); if (selected.Length == 0) return;
        var summary = string.Join("\n", selected.GroupBy(f => f.CategoryName).Select(g => $"• {g.Key} : {g.Count():N0} fichiers, {FormatBytes(g.Sum(f => f.File.Length))}"));
        int hidden = selected.Count(f => !FileView.Contains(f));
        string hiddenNotice = hidden > 0 ? $"\n\nAttention : {hidden:N0} fichiers sélectionnés sont masqués par les filtres et sont inclus dans cette suppression." : "";
        if (!confirm($"Supprimer définitivement {selected.Length:N0} fichiers ({FormatBytes(selected.Sum(f => f.File.Length))}) ?\n\n{summary}{hiddenNotice}\n\nLes fichiers ne seront pas envoyés à la corbeille. Les caches seront recréés au besoin. Ferme les applications concernées.\nLes fichiers modifiés ou utilisés seront ignorés.")) return;
        IsBusy = true; cleaning = true; RaisePropertyChanged(nameof(IsCleaning)); cancellation = new();
        var id = Guid.NewGuid().ToString("N");
        var report = new OperationResult { OperationId = id, Name = "Nettoyeur système", ExecutionKind = "Native", State = OperationState.Running, StartedUtc = DateTime.UtcNow, OwnerProcessId = Environment.ProcessId, OwnerProcessStartedUtc = OperationTrackingService.ProcessStartedUtc(), ExecutionStarted = false, Phase = "Nettoyage", Message = "Nettoyage en cours.", JournalPath = Path.Combine(paths.LogRoot, "Operations", id + ".operation.json") };
        bool journalReady = false;
        try
        {
            await SaveReport(report); journalReady = true;
            report = report with { ExecutionStarted = true }; await SaveReport(report);
            var result = await service.CleanAsync(snapshot, selected.Select(f => f.Id).ToArray(), new Progress<string>(message => Status = message), cancellation.Token);
            string outcome = result.Cancelled ? "Nettoyage arrêté" : result.Skipped > 0 || result.Errors.Count > 0 ? "Nettoyage partiel" : "Nettoyage terminé";
            Status = $"{outcome} — {result.DeletedCount:N0} fichiers supprimés, {FormatBytes(result.BytesRemoved)} supprimés (taille logique). {result.Skipped:N0} fichiers ignorés.";
            LastRun = $"{DateTime.Now:dd/MM/yyyy HH:mm} · {Status}";
            Detail = string.Join(Environment.NewLine, result.Errors);
            var removed = result.RemovedFileIds.ToHashSet(StringComparer.Ordinal);
            foreach (var file in Files.Where(f => removed.Contains(f.Id)).ToArray()) Files.Remove(file);
            foreach (var group in ResultGroups.Where(g => g.Items.Any(i => removed.Contains(i.Id))).ToArray()) ResultGroups.Remove(group);
            foreach (var group in Files.GroupBy(f => (f.File.CategoryId, f.File.Root)).Where(g => !ResultGroups.Any(r => r.CategoryId == g.Key.CategoryId && r.Items.FirstOrDefault()?.File.Root == g.Key.Root)))
                ResultGroups.Add(new CleanerResultGroupItem(group.Key.CategoryId, Categories.First(c => c.Id == group.Key.CategoryId).Group, service.Options.FirstOrDefault(o => o.CategoryId == group.Key.CategoryId && o.Path.Equals(group.Key.Root, StringComparison.OrdinalIgnoreCase))?.Name ?? Path.GetFileName(group.Key.Root), group.ToArray(), SetGroupSelection));
            RefreshResultGroups();
            UpdateSectionCounts();
            foreach (var c in Categories) { var remaining = Files.Where(f => f.File.CategoryId == c.Id).ToArray(); c.Summary = c.Selected ? $"{remaining.Length:N0} restants · {FormatBytes(remaining.Sum(f => f.File.Length))}" : "Non analysé"; }
            report = report with { State = result.Cancelled ? OperationState.Cancelled : result.Errors.Count > 0 || result.Skipped > 0 ? OperationState.Partial : OperationState.Succeeded, EndedUtc = DateTime.UtcNow, Phase = "Terminé", Message = Status, TechnicalDetail = Detail, Checks = new[] { new OperationCheck("Suppressions vérifiées", true, $"{result.DeletedCount} fichiers ; {result.BytesRemoved} octets logiques."), new OperationCheck("Sélection entièrement traitée", !result.Cancelled && result.Skipped == 0 && result.Errors.Count == 0, $"{result.Skipped} ignorés ; {result.Errors.Count} erreurs.") } };
            await SaveReport(report); SavePreferences();
        }
        catch (Exception e)
        {
            Status = journalReady ? "Nettoyage interrompu ou résultat non enregistré. Vérifie le détail puis relance une analyse." : "Impossible de créer le journal : aucun nettoyage lancé.";
            Detail = e.ToString();
            if (journalReady) { try { await SaveReport(report with { State = OperationState.Unconfirmed, EndedUtc = DateTime.UtcNow, Message = Status, TechnicalDetail = e.Message }); } catch { } }
        }
        finally { scan = null; cancellation.Dispose(); cancellation = null; cleaning = false; RaisePropertyChanged(nameof(IsCleaning)); IsBusy = false; UpdateSelection(); }
    }
    private static async Task SaveReport(OperationResult report)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(report.JournalPath)!);
        string temp = report.JournalPath + ".tmp";
        await File.WriteAllTextAsync(temp, JsonSerializer.Serialize(report));
        // Antivirus and concurrent readers can briefly retain the old file on Windows.
        // Keep the previous valid report until the replacement succeeds.
        for (int attempt = 0; ; attempt++)
        {
            try { File.Move(temp, report.JournalPath, true); break; }
            catch (Exception e) when (attempt < 5 && e is IOException or UnauthorizedAccessException) { await Task.Delay(40 * (attempt + 1)); }
        }
    }
    private async Task<OperationResult> BeginJournalAsync(string name)
    {
        string id = Guid.NewGuid().ToString("N");
        var report = new OperationResult { OperationId = id, Name = name, ExecutionKind = "Native", State = OperationState.Running, StartedUtc = DateTime.UtcNow, OwnerProcessId = Environment.ProcessId, OwnerProcessStartedUtc = OperationTrackingService.ProcessStartedUtc(), ExecutionStarted = false, Phase = "Préparation", Message = "Confirmation reçue ; préparation de l’action.", JournalPath = Path.Combine(paths.LogRoot, "Operations", id + ".operation.json") };
        await SaveReport(report);
        report = report with { ExecutionStarted = true, Phase = "Exécution", Message = "Action en cours." };
        await SaveReport(report);
        return report;
    }
    private static Task EndJournalAsync(OperationResult report, OperationState state, string message, string detail) =>
        SaveReport(report with { State = state, EndedUtc = DateTime.UtcNow, Phase = "Terminé", Message = message, TechnicalDetail = detail,
            Checks = new[] { new OperationCheck("Résultat communiqué", state == OperationState.Succeeded, message) } });
    private sealed record Preferences(string[] Categories, string[] Exclusions, int AgeDays, string LastRun, string[]? Options = null, string[]? KnownOptions = null, int SchemaVersion = 0);
    private string SettingsPath => Path.Combine(paths.StateRoot, "Cleaner.json");
    private void LoadPreferences()
    {
        try { if (!File.Exists(SettingsPath)) return; var p = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(SettingsPath)); if (p == null) return; foreach (var c in Categories) { c.Selected = p.Categories.Contains(c.Id) || (p.SchemaVersion < 3 && c.Id == "prefetch"); if (p.Options != null && p.KnownOptions != null) foreach (var option in c.Options.Where(o => p.KnownOptions.Contains(o.Id))) option.Selected = p.Options.Contains(option.Id); } foreach (var path in p.Exclusions.Where(Path.IsPathFullyQualified)) Exclusions.Add(Path.GetFullPath(path)); ageDays = p.SchemaVersion == 0 && p.AgeDays == 1 ? 0 : Math.Clamp(p.AgeDays, 0, 365); lastRun = p.LastRun; }
        catch (Exception e) { Detail = "Préférences non chargées : " + e.Message; }
    }
    private void SavePreferences()
    {
        try { Directory.CreateDirectory(paths.StateRoot); var p = new Preferences(Categories.Where(c => c.Selected).Select(c => c.Id).ToArray(), Exclusions.ToArray(), AgeDays, LastRun, Categories.SelectMany(c => c.Options.Where(o => o.Selected).Select(o => o.Id)).ToArray(), Categories.SelectMany(c => c.Options.Select(o => o.Id)).ToArray(), 3); File.WriteAllText(SettingsPath + ".tmp", JsonSerializer.Serialize(p)); File.Move(SettingsPath + ".tmp", SettingsPath, true); }
        catch (Exception e) { Detail = "Préférences non enregistrées : " + e.Message; }
    }
    public void Dispose() { cancellation?.Cancel(); }
}



