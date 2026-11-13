using System;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;
namespace Bastos.Native.ViewModels;
public sealed partial class ReinstallViewModel
{
    public void ResumeFromJournal(Bastos.Native.Models.OperationResumeIntent intent)
    {
        if(IsBusy||IsCatalogRefreshing){Status="Une opération est déjà en cours. Attends sa fin avant de reprendre.";return;}
        RefreshIsos();
        if(!string.IsNullOrEmpty(intent.SourceIso))
        {
            var match=System.Linq.Enumerable.FirstOrDefault(Isos,item=>string.Equals(item.Path,intent.SourceIso,StringComparison.OrdinalIgnoreCase));
            SelectedIso=match;
            Status=match==null?"L’ISO de cette tentative n’est plus dans la bibliothèque. Retrouve-la ou choisis une ISO, puis refais le bilan.":
                "ISO de la tentative retrouvée. Vérifie les options puis rouvre le bilan. La préparation recontrôle et réutilise les éléments déjà valides ; aucun redémarrage n’a été demandé.";
        }
        else Status="Reprends la vérification de l’outil dans ce module. Ses fichiers déjà valides sont conservés ; aucune installation n’a été relancée.";
    }
    private OperationCancellation? activeCancellation;
    private RelayCommand? cancelOperationCommand;
    private bool canCancelOperation,isCancellationVisible;
    private string cancellationHint="";
    public bool CanCancelOperation {get=>canCancelOperation;private set{if(SetProperty(ref canCancelOperation,value))CancelOperationCommand.RaiseCanExecuteChanged();}}
    public bool IsCancellationVisible {get=>isCancellationVisible;private set=>SetProperty(ref isCancellationVisible,value);}
    public string CancellationHint {get=>cancellationHint;private set=>SetProperty(ref cancellationHint,value);}
    public RelayCommand CancelOperationCommand=>cancelOperationCommand??=new(()=>{activeCancellation?.Request();},()=>CanCancelOperation);
    private OperationCancellation BeginCancellation()
    {
        OperationCancellation control=null!;
        control=new(new Progress<CancellationStatus>(value=>{
            if(!ReferenceEquals(activeCancellation,control))return;
            CanCancelOperation=value.CanRequest;CancellationHint=value.Message;
        }));
        activeCancellation=control;IsCancellationVisible=true;
        control.Lock("Cette action doit se terminer ; aucun outil ne sera arrêté de force.");
        return control;
    }
    private void EndCancellation(OperationCancellation control)
    {
        control.Dispose();activeCancellation=null;CanCancelOperation=false;
        CancellationHint="Opération terminée. Le résultat affiché indique si l’annulation a été confirmée.";
    }
}
