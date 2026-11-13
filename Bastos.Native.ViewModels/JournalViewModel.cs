using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class JournalViewModel : ObservableObject
{
    private readonly OperationHistoryService history;
    private readonly AppPaths paths;
    private IReadOnlyList<OperationHistoryEntry> all = Array.Empty<OperationHistoryEntry>();
    private string search = "", filter = "Toutes", notice = "", summary = "Aucune opération chargée.";
    private OperationHistoryEntry? selected;
    private Task? refreshTask;
    private readonly OperationResumeService? resume;
    private readonly Action<Bastos.Native.Models.OperationResumeIntent>? continueInModule;
    private bool isResumeChecking;
    private string resumeStatus = "";
    private string ResumeDisabledReason => IsResumeChecking ? "Le contrôle de reprise est en cours. Attends son résultat." : Selected == null ? "Sélectionne une opération dans la liste." : "Ce rapport ne permet pas une reprise guidée. Retourne au module concerné.";
    public bool HasResumeSelection => resume != null && OperationResumeService.Supported(Selected?.Result.ResumeIntent);
    public string ResumeHint => HasResumeSelection ? "Contrôle des éléments existants, puis retour au module. Aucune action d’installation rejouée." :
        "Ce rapport n’a pas de contrôle de reprise enregistré. Retourne au module concerné et refais son bilan ; aucune ancienne commande ne sera rejouée.";
    public string ResumeStatus {get=>resumeStatus;private set=>SetProperty(ref resumeStatus,value);}
    public bool IsResumeChecking {get=>isResumeChecking;private set{SetProperty(ref isResumeChecking,value);CheckResumeCommand.RaiseCanExecuteChanged();ContinueInModuleCommand.RaiseCanExecuteChanged();}}
    public AsyncRelayCommand CheckResumeCommand {get;}
    public RelayCommand ContinueInModuleCommand {get;}
    private string recoveryNotice = "";
    public string RecoveryNotice { get => recoveryNotice; private set { if (SetProperty(ref recoveryNotice, value)) RaisePropertyChanged(nameof(HasRecoveryNotice)); } }
    public bool HasRecoveryNotice => !string.IsNullOrEmpty(RecoveryNotice);
    public ObservableCollection<OperationHistoryEntry> Entries { get; } = new();
    public string[] Filters { get; } = new[] { "Toutes", "À vérifier", "Réussies" };
    public string Search { get => search; set { if (SetProperty(ref search, value)) ApplyFilter(); } }
    public string Filter { get => filter; set { if (SetProperty(ref filter, value)) ApplyFilter(); } }
    public string Notice { get => notice; private set => SetProperty(ref notice, value); }
    public string Summary { get => summary; private set => SetProperty(ref summary, value); }
    public OperationHistoryEntry? Selected
    {
        get => selected;
        set { if (SetProperty(ref selected, value)) { ResumeStatus="";if(value!=null&&resume?.ReadLastReview(value) is {} previous)ResumeStatus=$"Dernier contrôle enregistré : {previous.CheckedUtc.ToLocalTime():dd/MM/yyyy HH:mm}. Revérifie si les fichiers ou le disque ont changé.\n{previous.Message}";RaisePropertyChanged(nameof(HasSelection));RaisePropertyChanged(nameof(HasResumeSelection));RaisePropertyChanged(nameof(ResumeHint));OpenReportCommand.RaiseCanExecuteChanged();CheckResumeCommand.RaiseCanExecuteChanged();ContinueInModuleCommand.RaiseCanExecuteChanged(); } }
    }
    public bool HasSelection => Selected != null;
    public AsyncRelayCommand RefreshCommand { get; }
    public RelayCommand OpenReportCommand { get; }
    public RelayCommand OpenFolderCommand { get; }
    public RelayCommand OpenLegacyCommand { get; }

    public JournalViewModel(AppPaths paths, OperationHistoryService? history = null, OperationResumeService? resume = null, Action<Bastos.Native.Models.OperationResumeIntent>? continueInModule = null)
    {
        this.paths = paths;
        this.history = history ?? new(paths.LogRoot);
        this.resume=resume;this.continueInModule=continueInModule;
        CheckResumeCommand=new(CheckResumeAsync,()=>HasResumeSelection&&!IsResumeChecking,()=>ResumeDisabledReason);
        ContinueInModuleCommand=new(()=>{if(Selected?.Result.ResumeIntent is {} intent)continueInModule?.Invoke(intent);},()=>HasResumeSelection&&!IsResumeChecking&&continueInModule!=null,()=>continueInModule==null ? "Le retour guidé au module est indisponible depuis cette vue." : ResumeDisabledReason);
        RefreshCommand = new(RefreshAsync);
        OpenReportCommand = new(() => Open(() => this.history.ResolveReport(Selected!)), () => HasSelection, () => "Sélectionne une opération pour ouvrir son rapport.");
        OpenFolderCommand = new(() => Open(() => { Directory.CreateDirectory(paths.LogRoot); return paths.LogRoot; }));
        OpenLegacyCommand = new(() => Open(() => File.Exists(paths.NativeLog) ? paths.NativeLog : paths.LogRoot));
    }
    private async Task CheckResumeAsync()
    {
        var entry=Selected;if(entry==null||resume==null)return;
        IsResumeChecking=true;ResumeStatus="Contrôle en cours : lecture des rapports et vérification des éléments existants…";
        try{var review=await Task.Run(()=>resume.ReviewAsync(entry));if(Selected?.Reference==entry.Reference)ResumeStatus=review.Message+"\n"+review.NextStep;}
        finally{IsResumeChecking=false;}
    }

    public Task RefreshAsync()
    {
        if (refreshTask is { IsCompleted: false }) return refreshTask;
        return refreshTask = RefreshCoreAsync();
    }

    private async Task RefreshCoreAsync()
    {
        Summary = "Lecture des opérations…";
        try
        {
            await OperationTrackingService.ReadBootAsync();
            var snapshot = await Task.Run(() => history.Read());
            all = snapshot.Entries;
            int interrupted = all.Count(e => e.Tracking.Interrupted);
            int pending = all.Count(e => e.Tracking.RestartPending);
            int rebooted = all.Count(e => e.Tracking.RestartObserved);
            int external = all.Count(e => e.Tracking.ExternalUnconfirmed);
            var reminders = new List<string>();
            if (interrupted > 0) reminders.Add($"{interrupted} suivi(s) interrompu(s)");
            if (pending > 0) reminders.Add($"{pending} redémarrage(s) à effectuer ou vérifier");
            if (rebooted > 0) reminders.Add($"{rebooted} résultat(s) à recontrôler après redémarrage");
            if (external > 0) reminders.Add($"{external} outil(s) dont la fin reste à vérifier");
            RecoveryNotice = reminders.Count == 0 ? "" : "À vérifier : " + string.Join(" • ", reminders);
            Notice = snapshot.Skipped == 0 ? "" : $"{snapshot.Skipped} rapport(s) illisible(s) ignoré(s). Les autres opérations restent consultables.";
            ApplyFilter();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        { Notice = "Impossible de lire le journal : " + ex.Message; Summary = "Lecture impossible. Vous pouvez réessayer avec Actualiser."; }
    }

    private void ApplyFilter()
    {
        string? previous = Selected?.Reference;
        var filtered = all.Where(e => (Filter != "À vérifier" || e.NeedsAttention) && (Filter != "Réussies" || !e.NeedsAttention))
            .Where(e => string.IsNullOrWhiteSpace(Search) || (e.Name + " " + e.Message + " " + e.Result.Message + " " + e.NextStep + " " + e.Reference + " " + e.Result.ErrorCode)
                .Contains(Search.Trim(), StringComparison.OrdinalIgnoreCase)).ToArray();
        Entries.Clear();
        foreach (var entry in filtered) Entries.Add(entry);
        Selected = filtered.FirstOrDefault(e => e.Reference == previous) ?? filtered.FirstOrDefault();
        Summary = all.Count == 0 ? "Aucune opération enregistrée. Les anciens messages restent disponibles dans le journal texte."
            : $"{filtered.Length} opération(s) affichée(s) sur {all.Count} chargée(s) • {all.Count(e => e.NeedsAttention)} à vérifier • 200 rapports récents au maximum";
    }

    private void Open(Func<string> resolve)
    {
        try { Process.Start(new ProcessStartInfo(resolve()) { UseShellExecute = true }); }
        catch (Exception ex) { Notice = "Ouverture impossible : " + ex.Message; }
    }
}
