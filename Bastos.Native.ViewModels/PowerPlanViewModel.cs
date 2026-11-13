using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;

public sealed class PowerPlanViewModel : ObservableObject
{
    private readonly Func<IReadOnlyList<PowerPlan>> list;
    private readonly Func<Guid> active;
    private readonly Func<string, Task<NativeActionResult>> apply;
    private PowerPlan? selected;
    private Guid? activeId;
    private string activeText = "Lecture du plan actif…", message = "";
    private bool busy;
    public ObservableCollection<PowerPlan> Plans { get; } = new();
    public PowerPlan? Selected
    {
        get => selected;
        set { if (SetProperty(ref selected, value)) { RaisePropertyChanged(nameof(Description)); ApplyCommand.RaiseCanExecuteChanged(); } }
    }
    public string Description => Selected?.Description ?? "Aucun plan disponible.";
    public string ActiveText { get => activeText; private set => SetProperty(ref activeText, value); }
    public string Message { get => message; private set => SetProperty(ref message, value); }
    public bool IsAvailable => !busy;
    public AsyncRelayCommand ApplyCommand { get; }
    public RelayCommand RefreshCommand { get; }
    public PowerPlanViewModel(NativeActionService actions)
        : this(PowerPlanService.List, PowerPlanService.ActiveId, id => actions.RunElevatedAsync("power-select:" + id)) { }
    public PowerPlanViewModel(Func<IReadOnlyList<PowerPlan>> list, Func<Guid> active, Func<string, Task<NativeActionResult>> apply)
    {
        this.list = list; this.active = active; this.apply = apply;
        ApplyCommand = new AsyncRelayCommand(ApplyAsync, () => !busy && Selected != null && Selected.Id != activeId, () => busy ? "Le plan est en cours de modification. Attends sa fin." : Selected == null ? "Choisis un plan d’alimentation." : "Ce plan est déjà actif. Choisis-en un autre pour le modifier.");
        RefreshCommand = new RelayCommand(() => Refresh(), () => !busy, () => "Le plan est en cours de modification. Attends sa fin.");
        Refresh();
    }
    public void Refresh(bool preserveSelection = false)
    {
        try
        {
            var previous = preserveSelection ? Selected?.Id : null;
            var items = list(); activeId = active();
            Plans.Clear(); foreach (var plan in items) Plans.Add(plan);
            Selected = Plans.FirstOrDefault(p => p.Id == (previous ?? activeId)) ?? Plans.FirstOrDefault();
            ActiveText = "Plan actif : " + (Plans.FirstOrDefault(p => p.Id == activeId)?.Name ?? activeId.ToString());
            Message = "Choisissez un plan puis cliquez sur Appliquer. Bastos Power Plan (AMD) est téléchargé depuis sa source lors de sa première activation.";
        }
        catch (Exception ex) { activeId = null; Plans.Clear(); Selected = null; ActiveText = "Plan actif indisponible"; Message = "Lecture impossible : " + ex.Message; }
        ApplyCommand.RaiseCanExecuteChanged();
    }
    private async Task ApplyAsync()
    {
        if (Selected == null) return;
        var id = Selected.Id;
        busy = true; RaisePropertyChanged(nameof(IsAvailable)); RefreshCommand.RaiseCanExecuteChanged();
        Message = "Activation du plan sélectionné…";
        try
        {
            var result = await apply(id.ToString("D"));
            Refresh();
            Message = result.Success && activeId == id ? "Le plan sélectionné est maintenant actif." : "Activation non confirmée : " + result.Message;
        }
        catch (Exception ex) { Refresh(); Message = "Activation impossible : " + ex.Message; }
        finally { busy = false; RaisePropertyChanged(nameof(IsAvailable)); RefreshCommand.RaiseCanExecuteChanged(); ApplyCommand.RaiseCanExecuteChanged(); }
    }
}
