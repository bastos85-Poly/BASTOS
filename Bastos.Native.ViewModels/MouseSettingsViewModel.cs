using System;
using System.Linq;
using System.Windows;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;
using Bastos.Native.Models;

public sealed class MouseSettingsViewModel : ObservableObject
{
    private readonly IMouseAccelerationService service;
    private readonly Action<string> log;
    private bool enabled;
    private bool available;
    private string status = "Lecture du réglage Windows…";

    public MouseSettingsViewModel(IMouseAccelerationService service, Action<string> log = null)
    {
        this.service = service;
        this.log = log;
        ToggleCommand = new RelayCommand(Toggle, () => IsAvailable, () => "Le réglage de souris n’a pas pu être lu. Actualise son état avant de le modifier.");
        RefreshCommand = new RelayCommand(Refresh);
        WindowsProfileCommand=new RelayCommand(()=>Profile(()=>MouseProfileService.Apply(windowsProfile:true)));
        DirectProfileCommand=new RelayCommand(()=>Profile(()=>MouseProfileService.Apply(acceleration:false)));
        ApplyCurveCommand=new RelayCommand(()=>{
            if(SelectedCurve=="Courbes nulles" && MessageBox.Show("Ce mode remplace les deux courbes Windows par des valeurs entièrement nulles. Son effet sur le pointeur peut être imprévisible. Bastos sauvegardera les courbes précédentes pour permettre leur restauration. Continuer ?", "Courbes nulles", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No)!=MessageBoxResult.Yes)return;
            try{MouseProfileService.ApplyCurve(SelectedCurve);Refresh();Status="Courbe "+SelectedCurve+" enregistrée et relue. Fermez puis rouvrez la session Windows avant de comparer les mouvements. Vitesse et accélération restent indépendantes.";log?.Invoke(Status);}catch(Exception ex){Status="Courbe non confirmée : "+ex.Message;}
        },()=>MouseCurveProfiles.Names.Contains(SelectedCurve),()=>"Choisis une courbe prédéfinie pour l’appliquer. Le profil personnalisé peut être conservé tel quel.");
        ApplySpeedCommand=new RelayCommand(()=>Profile(()=>MouseProfileService.Apply(speed:Speed)));
        RestoreProfileCommand=new RelayCommand(()=>{try{var message=MouseProfileService.Restore();Refresh();Status=message;}catch(Exception ex){Status="Restauration non confirmée : "+ex.Message;}});
        CurveSwitch=new("Courbe du pointeur",ApplyCurveCommand,RestoreProfileCommand,()=>IsAvailable?MouseProfileService.HasSavedProfile&&CurrentCurve==SelectedCurve:null,
            ()=>!IsAvailable?"État à vérifier":CurrentCurve==SelectedCurve?"Enregistré — reconnexion nécessaire après modification":"Non enregistré");
    }

    private string selectedCurve="Défaut",currentCurve="État non vérifié";
    public string[] CurveNames=>CurrentCurve=="Personnalisé"?MouseCurveProfiles.Names.Concat(new[]{"Personnalisé"}).ToArray():MouseCurveProfiles.Names;
    public string SelectedCurve {get=>selectedCurve;set{if(SetProperty(ref selectedCurve,value)){RaisePropertyChanged(nameof(CurveDescription));ApplyCurveCommand?.RaiseCanExecuteChanged();CurveSwitch?.Refresh();}}}
    public string CurrentCurve {get=>currentCurve;private set=>SetProperty(ref currentCurve,value);}
    public string CurveDescription=>SelectedCurve switch{
        "Personnalisé"=>"Votre courbe actuelle, différente des profils proposés. Elle est conservée tant que vous n’appliquez pas un autre mode.",
        "MarkC"=>"Correction visant un déplacement linéaire, sans accélération supplémentaire. La version fournie est prévue pour une échelle Windows de 100 % et une sensibilité centrale.",
        "CPL"=>"Ancienne correction de l’accélération utilisée dans le jeu compétitif. La distance parcourue peut différer de celle obtenue avec MarkC.",
        "CheeseM"=>"Correction historique de l’accélération, conçue à l’origine pour Windows XP et Vista. Son comportement sur les Windows récents peut différer de MarkC.",
        "Courbes nulles"=>"Reprend les deux courbes entièrement à zéro du fichier fourni. L’effet sur le pointeur est incertain et ce mode ne garantit pas un mouvement 1:1. Les courbes précédentes sont sauvegardées pour restauration.",
        _=>"Courbe standard de Windows. Lorsque l’accélération est activée, un mouvement rapide de la souris fait parcourir davantage de distance au pointeur."
    };
    public RelayCommand ApplyCurveCommand {get;}
    public SettingSwitchModel CurveSwitch {get;}
    private int speed=10;
    public int Speed { get=>speed; set=>SetProperty(ref speed,value); }
    public string Curves { get; private set; }="";
    public RelayCommand WindowsProfileCommand { get; }
    public RelayCommand DirectProfileCommand { get; }
    public RelayCommand RestoreProfileCommand { get; }
    public RelayCommand ApplySpeedCommand { get; }
    public RelayCommand ToggleCommand { get; }
    public RelayCommand RefreshCommand { get; }
    public bool IsEnabled { get => enabled; private set { enabled = value; RaisePropertyChanged(); RaisePropertyChanged(nameof(StateText)); } }
    public bool IsAvailable { get => available; private set { SetProperty(ref available, value); ToggleCommand.RaiseCanExecuteChanged(); RaisePropertyChanged(nameof(StateText)); CurveSwitch?.Refresh(); } }
    public string StateText => !IsAvailable ? "Indisponible" : IsEnabled ? "Activée" : "Désactivée";
    public string Status { get => status; private set { SetProperty(ref status, value); RaisePropertyChanged(nameof(HasActionError)); RaisePropertyChanged(nameof(ActionError)); } }
    public bool HasActionError => status.StartsWith("Lecture impossible",StringComparison.Ordinal) || status.Contains("non confirmé",StringComparison.OrdinalIgnoreCase);
    public string ActionError => HasActionError ? status : "";

    public void SynchronizeCurveSelection(){Refresh();if(IsAvailable)SelectedCurve=CurrentCurve;}

    public void Refresh()
    {
        try
        {
            IsEnabled = service.Read();
            if(service is MouseAccelerationService){Speed=MouseProfileService.Read().Speed;var actual=MouseCurveProfiles.CurrentName();var changed=CurrentCurve!=actual;CurrentCurve=actual;RaisePropertyChanged(nameof(CurveNames));if(changed)SelectedCurve=actual;Curves=MouseProfileService.Curves();RaisePropertyChanged(nameof(Curves));}
            IsAvailable = true;
            Status = "Vitesse et accélération : application immédiate. Après modification des courbes : nouvelle session Windows nécessaire.";
            CurveSwitch?.Refresh();
        }
        catch (Exception ex)
        {
            IsAvailable = false;
            Status = "Lecture impossible : " + ex.Message;
        }
    }

    private void Profile(Action apply)
    {
        try{apply();Refresh();Status="Profil appliqué et relu. Les courbes personnalisées restent conservées. Les jeux Raw Input peuvent ignorer ces réglages Windows.";log?.Invoke(Status);}
        catch(Exception ex){Status="Profil non confirmé : "+ex.Message;}
    }
    private void Toggle()
    {
        try
        {
            // Read again so an external Windows change cannot invert a stale state.
            IsEnabled = service.SetEnabled(!service.Read());
            IsAvailable = true;
            Status = IsEnabled ? "Accélération activée dans Windows." : "Accélération désactivée dans Windows.";
            try { log?.Invoke(Status); } catch { /* Logging must not misreport a successful Windows change. */ }
        }
        catch (Exception ex)
        {
            string error = ex.Message;
            Refresh();
            Status = "Changement non confirmé : " + error;
        }
    }
}
