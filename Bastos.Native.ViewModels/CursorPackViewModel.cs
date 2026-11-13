using System;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;
namespace Bastos.Native.ViewModels;
using Bastos.Native.Models;
public sealed class CursorPackViewModel:ObservableObject
{
    private readonly CursorPackService service;private readonly Action<string> log;
    private string status="État non vérifié.";private bool available,canRestore;
    public string Status {get=>status;private set=>SetProperty(ref status,value);}
    public RelayCommand ApplyCommand {get;}
    public RelayCommand RestoreCommand {get;}
    public RelayCommand RefreshCommand {get;}
    private bool? applied;
    public SettingSwitchModel PackSwitch {get;}
    public CursorPackViewModel(AppPaths paths,Action<string> log)
    {
        service=new(paths);this.log=log;
        ApplyCommand=new(()=>Run(service.Apply),()=>available,()=>"Le pack de curseurs est indisponible. Actualise son état et consulte le message du module.");
        RestoreCommand=new(()=>Run(service.Restore),()=>canRestore,()=>"Aucun profil de curseurs sauvegardé à restaurer.");
        RefreshCommand=new(Refresh);
        PackSwitch=new("Curseurs sombres",ApplyCommand,RestoreCommand,()=>applied);
        Refresh();
    }
    public void Refresh(){var s=service.ReadStatus();available=s.Available;canRestore=s.CanRestore;applied=s.Available?s.Applied:null;Status=s.Message;ApplyCommand.RaiseCanExecuteChanged();RestoreCommand.RaiseCanExecuteChanged();PackSwitch?.Refresh();}
    private void Run(Func<string> action){try{var message=action();Refresh();Status=message;try{log(message);}catch{}}catch(Exception ex){Refresh();Status="Modification non confirmée : "+ex.Message;}}
}
