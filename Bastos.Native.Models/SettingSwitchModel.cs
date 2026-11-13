using System;
using System.Threading.Tasks;
using System.Windows.Input;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

// Presentation adapter: preserve the existing apply/restore commands and their
// prerequisites. Read the verified state again after either command completes.
public sealed class SettingSwitchModel : ObservableObject
{
    private readonly ICommand apply, restore;
    private readonly Func<bool?> read;
    private readonly Func<string>? label;
    private readonly string restoreHelp;
    private bool busy;
    public string Title { get; }
    public bool? ToggleState { get { try { return read(); } catch { return null; } } }
    public string ToggleLabel => label?.Invoke() ?? (ToggleState == true ? "Appliqué" : ToggleState == false ? "Non appliqué" : "État à vérifier");
    private ICommand Next => ToggleState == true ? restore : apply;
    public string ToggleHelp => !ToggleState.HasValue ? "Actualisez l’état du réglage avant de le modifier."
        : !Next.CanExecute(null) ? (Next is AsyncRelayCommand asyncCommand ? asyncCommand.DisabledReason : Next is RelayCommand command ? command.DisabledReason : "Action indisponible.")
        : ToggleState == true ? restoreHelp : "Appliquer les choix affichés";
    public AsyncRelayCommand ToggleCommand { get; }
    public SettingSwitchModel(string title, ICommand apply, ICommand restore, Func<bool?> read, Func<string>? label = null, string restoreHelp = "Restaurer les valeurs précédentes")
    {
        Title=title;this.apply=apply;this.restore=restore;this.read=read;this.label=label;this.restoreHelp=restoreHelp;
        ToggleCommand=new AsyncRelayCommand(Execute,CanExecute,()=>ToggleHelp);
        apply.CanExecuteChanged+=(_,_)=>Refresh();restore.CanExecuteChanged+=(_,_)=>Refresh();
    }
    private bool CanExecute() => !busy && ToggleState.HasValue &&
        !(apply is AsyncRelayCommand a && a.IsRunning) && !(restore is AsyncRelayCommand r && r.IsRunning) && Next.CanExecute(null);
    private async Task Execute()
    {
        if(!CanExecute())return;
        var action=Next;busy=true;
        try { if(action is AsyncRelayCommand command)await command.ExecuteAsync();else action.Execute(null); }
        finally { busy=false;Refresh(); }
    }
    public void Refresh()
    {
        RaisePropertyChanged(nameof(ToggleState));RaisePropertyChanged(nameof(ToggleLabel));RaisePropertyChanged(nameof(ToggleHelp));ToggleCommand.RaiseCanExecuteChanged();
    }
}
