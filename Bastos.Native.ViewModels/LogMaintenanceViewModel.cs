using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;
namespace Bastos.Native.ViewModels;

public sealed class MaintenanceRow(MaintenanceItem item) : ObservableObject
{
    private bool selected = item.Eligible;
    public MaintenanceItem Item { get; } = item;
    public bool Selected { get => selected; set { if (Item.Eligible) SetProperty(ref selected, value); } }
    public string Title => Item.Title;
    public string Size => Item.Size;
    public string State => Item.State;
    public string Reason => Item.Reason;
    public bool Eligible => Item.Eligible;
    public string Inventory => Item.Inventory;
}
public sealed class LogMaintenanceViewModel : ObservableObject
{
    private readonly LogMaintenanceService service;
    private MaintenancePlan? plan;
    private bool busy;
    private int revision;
    private int keepDays = 30;
    private string status = "Analyse les journaux avant de choisir les éléments à nettoyer.", summary = "", total = "—", cleanable = "—", preserved = "—";
    private MaintenanceRow? selected;
    public ObservableCollection<MaintenanceRow> Rows { get; } = new();
    public int[] RetentionChoices { get; } = { 30, 60, 90, 180, 365 };
    public int KeepDays { get => keepDays; set { if (SetProperty(ref keepDays, value)) { revision++; plan = null; Rows.Clear(); Selected = null; ResetSizes(); Summary = ""; Status = "La durée a changé. Relance l’analyse avant de nettoyer."; RaisePropertyChanged(nameof(CanClean)); RaisePropertyChanged(nameof(CleanDisabledReason)); RaisePropertyChanged(nameof(SelectionSummary)); } } }
    public bool IsBusy { get => busy; private set { SetProperty(ref busy, value); RaisePropertyChanged(nameof(CanEdit)); RaisePropertyChanged(nameof(CanClean)); RaisePropertyChanged(nameof(CleanDisabledReason)); AnalyzeCommand.RaiseCanExecuteChanged(); } }
    public bool CanEdit => !IsBusy;
    public string CleanDisabledReason => IsBusy ? "Une analyse ou un nettoyage est en cours. Attends sa fin." : plan == null ? "Lance l’analyse pour voir ce qui peut être nettoyé." : !plan.Complete ? "L’analyse est incomplète. Relance-la avant de nettoyer." : !Rows.Any(r => r.Eligible) ? "Aucun élément nettoyable avec ces règles. Les fichiers utiles sont conservés." : !Rows.Any(r => r.Eligible && r.Selected) ? "Coche au moins un élément marqué Nettoyable." : "";
    public bool CanClean => !IsBusy && plan?.Complete == true && Rows.Any(r => r.Eligible && r.Selected);
    public string Status { get => status; private set => SetProperty(ref status, value); }
    public string Summary { get => summary; private set => SetProperty(ref summary, value); }
    public string Total { get => total; private set => SetProperty(ref total, value); }
    public string Cleanable { get => cleanable; private set => SetProperty(ref cleanable, value); }
    public string Preserved { get => preserved; private set => SetProperty(ref preserved, value); }
    public MaintenanceRow? Selected { get => selected; set { SetProperty(ref selected, value); RaisePropertyChanged(nameof(SelectedInventory)); } }
    public string SelectedInventory => Selected?.Inventory ?? "Sélectionne un élément pour voir les fichiers concernés.";
    public string SelectionSummary => $"{Rows.Count(r => r.Eligible && r.Selected)} élément(s), {Rows.Where(r => r.Eligible && r.Selected).Sum(r => r.Item.Files.Count)} fichier(s), {LogMaintenanceService.FormatBytes(Rows.Where(r => r.Eligible && r.Selected).Sum(r => r.Item.Bytes))}";
    public AsyncRelayCommand AnalyzeCommand { get; }
    public LogMaintenanceViewModel(LogMaintenanceService service) { this.service = service; AnalyzeCommand = new(AnalyzeAsync, () => !IsBusy, () => "Une analyse ou un nettoyage est en cours. Attends sa fin."); }
    private void ResetSizes() { Total = Cleanable = Preserved = "—"; }
    public async Task AnalyzeAsync()
    {
        if (IsBusy) return;
        int expectedRevision = revision, days = KeepDays;
        IsBusy = true; Status = "Analyse locale et préparation de l’aperçu…"; Rows.Clear(); Selected = null; plan = null; ResetSizes();
        try
        {
            var prepared = await Task.Run(() => service.Scan(days));
            if (expectedRevision != revision) { Status = "La durée a changé pendant l’analyse. Relance l’aperçu."; return; }
            plan = prepared;
            foreach (var item in plan.Items)
            {
                var row = new MaintenanceRow(item);
                row.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(MaintenanceRow.Selected)) { RaisePropertyChanged(nameof(CanClean)); RaisePropertyChanged(nameof(CleanDisabledReason)); RaisePropertyChanged(nameof(SelectionSummary)); } };
                Rows.Add(row);
            }
            Total = LogMaintenanceService.FormatBytes(plan.TotalBytes); Cleanable = LogMaintenanceService.FormatBytes(plan.CleanableBytes); Preserved = LogMaintenanceService.FormatBytes(plan.ProtectedBytes);
            Summary = plan.Notice; Status = !plan.Complete ? "Analyse incomplète : aucun nettoyage autorisé." : Rows.Any(r => r.Eligible) ? "Aperçu prêt. Seuls les éléments cochés et marqués Nettoyable pourront être supprimés." : "Aucun élément nettoyable avec ces règles. Les fichiers utiles sont conservés.";
            Selected = Rows.FirstOrDefault(); RaisePropertyChanged(nameof(SelectionSummary));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or ArgumentException) { Status = "Analyse impossible : " + ex.Message; }
        finally { IsBusy = false; }
    }
    public async Task CleanAsync()
    {
        if (!CanClean || plan == null) return;
        var preview = plan; var ids = Rows.Where(r => r.Eligible && r.Selected).Select(r => r.Item.Id).ToArray();
        IsBusy = true; Status = "Nouvelle vérification des fichiers, puis nettoyage des éléments autorisés…";
        try
        {
            var result = await Task.Run(() => service.Clean(preview, ids));
            plan = null; Rows.Clear(); Selected = null; ResetSizes(); Summary = "Relance l’analyse pour voir l’espace restant.";
            Status = result.Summary + (result.Issues.Count > 0 ? "\n" + string.Join("\n", result.Issues.Take(5)) : "") + "\nBilan local : " + result.ReportPath;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or ArgumentException)
        { plan = null; Status = "Nettoyage non confirmé : " + ex.Message + " Relance l’analyse et consulte le bilan local s’il a été créé."; }
        finally { IsBusy = false; RaisePropertyChanged(nameof(SelectionSummary)); }
    }
}
