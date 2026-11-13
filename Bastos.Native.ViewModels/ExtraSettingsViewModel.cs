using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.ViewModels;
using Bastos.Native.Models;

public sealed class ExtraItem
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string State { get; set; } = "";
    public bool Installed { get; set; }
    public bool Applied { get; set; }
    public bool CanRestore { get; set; }
    public int Current { get; set; }
    public int Ac { get; set; }
    public int Dc { get; set; }
    public string Plan { get; set; } = "";
    public string PlanName { get; set; } = "";
    public override string ToString() => Name;
}
public sealed class AppearanceOption : ObservableObject
{
    public string Key { get; init; } = "";
    public string Title { get; init; } = "";
    private bool selected;
    public bool Selected { get => selected; set { if(SetProperty(ref selected,value)) Changed?.Invoke(); } }
    private string state="État non vérifié";
    public string State { get => state; set => SetProperty(ref state,value); }
    private string detail="";
    public string Detail { get => detail; set => SetProperty(ref detail,value); }
    private bool? applied;
    public bool? Applied { get => applied; set => SetProperty(ref applied,value); }
    private bool canRestore;
    public bool CanRestore { get => canRestore; set => SetProperty(ref canRestore,value); }
    public Action? Changed { get; set; }
}
public sealed class ExtraSettingsViewModel : ObservableObject
{
    private readonly AppPaths paths;
    private readonly PowerShellWorkerService workers;
    private bool busy;
    private string status="Actualisez pour lire les réglages. La lecture ne modifie aucune préférence Windows.";
    private string appStatus="Choisissez une application détectée. Les autres préférences restent conservées.";
    private string mtuStatus="Choisissez une carte et une destination IPv4 avant le diagnostic.";
    private string usbStatus="Seuls les périphériques exposant une préférence de veille WDF compatible sont proposés.";
    private string powerStatus="Les valeurs concernent le plan actif, en pourcentage. Aucun nouveau plan n’est créé.";
    private string profileStatus="Choisissez un profil puis ajustez les cases. Les commandes et sauvegardes existantes de Bastos sont réutilisées.";
    private ExtraItem? selectedApp,selectedUsb,selectedAdapter,selectedPower;
    private int acValue,dcValue;
    private string destination="1.1.1.1",preset="Sobre";
    private string? measuredAdapter;
    private readonly List<AsyncRelayCommand> commands=new();
    public ObservableCollection<ExtraItem> Apps { get; }=new();
    public ObservableCollection<ExtraItem> UsbDevices { get; }=new();
    public ObservableCollection<ExtraItem> Adapters { get; }=new();
    public ObservableCollection<ExtraItem> PowerOptions { get; }=new();
    public ObservableCollection<AppearanceOption> AppearanceOptions { get; }=new();
    public SettingSwitchModel AppSwitch {get;}
    public SettingSwitchModel UsbSwitch {get;}
    public SettingSwitchModel MtuSwitch {get;}
    public SettingSwitchModel PowerSwitch {get;}
    public SettingSwitchModel ProfileSwitch {get;}
    public string[] Presets { get; }={"Sobre","Classique","Confort"};
    public bool Available => !busy;
    public string Status { get=>status; private set=>SetProperty(ref status,value); }
    public string AppStatus { get=>appStatus; private set=>SetProperty(ref appStatus,value); }
    public string MtuStatus { get=>mtuStatus; private set=>SetProperty(ref mtuStatus,value); }
    public string UsbStatus { get=>usbStatus; private set=>SetProperty(ref usbStatus,value); }
    public string PowerStatus { get=>powerStatus; private set=>SetProperty(ref powerStatus,value); }
    public string ProfileStatus { get=>profileStatus; private set=>SetProperty(ref profileStatus,value); }
    public string Destination { get=>destination; set { if(SetProperty(ref destination,value)){measuredAdapter=null;Update();} } }
    public ExtraItem? SelectedApp { get=>selectedApp; set { if(SetProperty(ref selectedApp,value)){RaisePropertyChanged(nameof(AppState));Update();} } }
    public string AppState => SelectedApp?.State??"Aucune application sélectionnée.";
    public ExtraItem? SelectedUsb { get=>selectedUsb; set { if(SetProperty(ref selectedUsb,value)){RaisePropertyChanged(nameof(UsbState));Update();} } }
    public string UsbState => SelectedUsb?.State??"Aucun périphérique compatible sélectionné.";
    public ExtraItem? SelectedAdapter { get=>selectedAdapter; set { if(SetProperty(ref selectedAdapter,value)){measuredAdapter=null;RaisePropertyChanged(nameof(MtuCurrent));Update();} } }
    public string MtuCurrent => SelectedAdapter==null?"Aucune carte IPv4 active détectée.":$"MTU IPv4 actuelle : {SelectedAdapter.Current} octets.";
    public ExtraItem? SelectedPower { get=>selectedPower; set { if(SetProperty(ref selectedPower,value)){AcValue=value?.Ac??0;DcValue=value?.Dc??0;RaisePropertyChanged(nameof(PlanText));Update();} } }
    public string PlanText => SelectedPower==null?"Aucune option compatible exposée.":"Plan actif : "+
        (Guid.TryParse(SelectedPower.Plan,out var planId)&&planId==PowerPlanService.ZoicAmdId
            ? "Zoic Ultimate Performance (AMD)" : SelectedPower.PlanName);
    public int AcValue { get=>acValue; set {if(SetProperty(ref acValue,value))Update();} }
    public int DcValue { get=>dcValue; set {if(SetProperty(ref dcValue,value))Update();} }
    public string Preset { get=>preset; set { if(SetProperty(ref preset,value))SelectPreset(); } }
    public string Preview => string.Join(" · ",AppearanceOptions.Where(o=>o.Selected).Select(o=>o.Title));
    public string PreviewBackground => AppearanceOptions.Any(o=>o.Key=="DarkMode"&&o.Selected)?"#111827":"#E6EAF1";
    public string PreviewForeground => AppearanceOptions.Any(o=>o.Key=="DarkMode"&&o.Selected)?"#F3F4F6":"#172033";
    public AsyncRelayCommand RefreshAppsCommand { get; }
    public AsyncRelayCommand ApplyAppCommand { get; }
    public AsyncRelayCommand RestoreAppCommand { get; }
    public AsyncRelayCommand RefreshUsbCommand { get; }
    public AsyncRelayCommand ApplyUsbCommand { get; }
    public AsyncRelayCommand RestoreUsbCommand { get; }
    public AsyncRelayCommand RefreshMtuCommand { get; }
    public AsyncRelayCommand MeasureMtuCommand { get; }
    public AsyncRelayCommand ApplyMtuCommand { get; }
    public AsyncRelayCommand RestoreMtuCommand { get; }
    public AsyncRelayCommand RefreshPowerCommand { get; }
    public AsyncRelayCommand ApplyPowerCommand { get; }
    public AsyncRelayCommand RestorePowerCommand { get; }
    public AsyncRelayCommand RefreshProfilesCommand { get; }
    public AsyncRelayCommand ApplyProfileCommand { get; }
    public AsyncRelayCommand RestoreProfileCommand { get; }
    public ExtraSettingsViewModel(AppPaths paths,PowerShellWorkerService workers)
    {
        this.paths=paths;this.workers=workers;
        AsyncRelayCommand Command(Func<Task> action,Func<bool>? can=null,Func<string>? reason=null){var c=new AsyncRelayCommand(()=>Guard(action),()=>!busy&&(can?.Invoke()??true),()=>busy ? "Une opération est en cours. Attends sa fin." : reason?.Invoke() ?? "");commands.Add(c);return c;}
        RefreshAppsCommand=Command(()=>Read("apps"));
        ApplyAppCommand=Command(()=>Change(SelectedApp!.Id,"Apply", ""),()=>SelectedApp?.Installed==true,()=>"Choisis une application détectée comme installée. Actualise la liste si nécessaire.");
        RestoreAppCommand=Command(()=>Change(SelectedApp!.Id,"Restore",""),()=>SelectedApp?.CanRestore==true,()=>SelectedApp==null ? "Choisis une application." : "Aucune sauvegarde à restaurer pour cette application.");
        RefreshUsbCommand=Command(()=>Read("usb"));
        ApplyUsbCommand=Command(()=>Change("usb","Apply",SelectedUsb!.Id),()=>SelectedUsb!=null,()=>"Détecte puis choisis un périphérique USB compatible.");
        RestoreUsbCommand=Command(()=>Change("usb","Restore",SelectedUsb!.Id),()=>SelectedUsb?.CanRestore==true,()=>SelectedUsb==null ? "Choisis un périphérique USB compatible." : "Aucune sauvegarde à restaurer pour ce périphérique.");
        RefreshMtuCommand=Command(()=>Read("mtu"));
        MeasureMtuCommand=Command(()=>Change("mtu","Measure",SelectedAdapter!.Id),()=>SelectedAdapter!=null&&!string.IsNullOrWhiteSpace(Destination),()=>SelectedAdapter==null ? "Détecte puis choisis une carte IPv4 active." : "Saisis une destination IPv4 ou un nom de serveur.");
        ApplyMtuCommand=Command(()=>Change("mtu","Apply",SelectedAdapter!.Id),()=>SelectedAdapter!=null&&measuredAdapter==SelectedAdapter.Id,()=>SelectedAdapter==null ? "Choisis une carte IPv4 active." : "Lance le diagnostic MTU pour cette carte et cette destination avant d’appliquer.");
        RestoreMtuCommand=Command(()=>Change("mtu","Restore",SelectedAdapter!.Id),()=>SelectedAdapter?.CanRestore==true,()=>SelectedAdapter==null ? "Choisis une carte IPv4 active." : "Aucune sauvegarde MTU à restaurer pour cette carte.");
        RefreshPowerCommand=Command(()=>Read("power"));
        ApplyPowerCommand=Command(()=>Change("power","Apply",SelectedPower!.Id),()=>SelectedPower!=null&&AcValue>=0&&AcValue<=100&&DcValue>=0&&DcValue<=100,()=>SelectedPower==null ? "Actualise le plan puis choisis une option compatible." : "Saisis des pourcentages compris entre 0 et 100.");
        RestorePowerCommand=Command(()=>Change("power","Restore",SelectedPower!.Id),()=>SelectedPower?.CanRestore==true,()=>SelectedPower==null ? "Choisis une option d’alimentation." : "Aucune sauvegarde à restaurer pour cette option du plan.");
        RefreshProfilesCommand=Command(()=>ReadProfiles());
        ApplyProfileCommand=Command(()=>ChangeProfile("Apply"),()=>AppearanceOptions.Any(o=>o.Selected),()=>"Coche au moins un réglage du profil pour continuer.");
        RestoreProfileCommand=Command(()=>ChangeProfile("Restore"),()=>AppearanceOptions.Any(o=>o.Selected&&o.CanRestore),()=>"Aucune sauvegarde disponible pour les choix cochés.");
        AppSwitch=new("Désactiver le rendu GPU",ApplyAppCommand,RestoreAppCommand,()=>SelectedApp?.Installed==true?SelectedApp.Applied:null);
        UsbSwitch=new("Désactiver cette veille USB",ApplyUsbCommand,RestoreUsbCommand,()=>SelectedUsb==null?null:SelectedUsb.Current==0);
        MtuSwitch=new("MTU mesurée",ApplyMtuCommand,RestoreMtuCommand,()=>SelectedAdapter==null?null:SelectedAdapter.CanRestore);
        PowerSwitch=new("Option du plan actif",ApplyPowerCommand,RestorePowerCommand,()=>SelectedPower==null?null:SelectedPower.CanRestore&&SelectedPower.Ac==AcValue&&SelectedPower.Dc==DcValue);
        ProfileSwitch=new("Choix d’apparence",ApplyProfileCommand,RestoreProfileCommand,()=>{
            var chosen=AppearanceOptions.Where(o=>o.Selected).ToArray();
            return chosen.Length==0||chosen.Any(o=>!o.Applied.HasValue)?null:chosen.All(o=>o.Applied==true);
        },()=>AppearanceOptions.Where(o=>o.Selected).Any(o=>o.Applied==true)&&AppearanceOptions.Where(o=>o.Selected).Any(o=>o.Applied==false)?"Partiellement appliqué":ProfileSwitch?.ToggleState==true?"Appliqué":ProfileSwitch?.ToggleState==false?"Non appliqué":"État à vérifier");
        foreach(var (key,title) in new[]{("DarkMode","Mode sombre"),("Transparency","Désactiver les transparences"),("MouseMenuDelay","Menus immédiats"),("ShowFileExtensions","Afficher les extensions"),("ShowHiddenFiles","Afficher les fichiers cachés"),("ClassicContextMenu","Menu clic droit classique"),("TaskbarLeft","Barre des tâches à gauche"),("EndTaskMenu","Terminer la tâche dans la barre des tâches")})
            AppearanceOptions.Add(new(){Key=key,Title=title,Changed=()=>{RaisePropertyChanged(nameof(Preview));RaisePropertyChanged(nameof(PreviewBackground));RaisePropertyChanged(nameof(PreviewForeground));Update();}});
        SelectPreset();
    }
    private void SelectPreset()
    {
        var keys=Preset switch{"Classique"=>new[]{"TaskbarLeft","ShowFileExtensions","ClassicContextMenu"},"Confort"=>new[]{"DarkMode","ShowFileExtensions","EndTaskMenu"},_=>new[]{"DarkMode","Transparency","ShowFileExtensions"}};
        foreach(var o in AppearanceOptions)o.Selected=keys.Contains(o.Key);
    }
    private void Update(){foreach(var c in commands)c.RaiseCanExecuteChanged();AppSwitch?.Refresh();UsbSwitch?.Refresh();MtuSwitch?.Refresh();PowerSwitch?.Refresh();ProfileSwitch?.Refresh();}
    private async Task Guard(Func<Task> action)
    {
        if(busy)return;busy=true;RaisePropertyChanged(nameof(Available));Update();
        try{await action();}catch(Exception ex){Status="Opération non confirmée : "+ex.Message;AppStatus=MtuStatus=UsbStatus=PowerStatus=ProfileStatus=Status;}
        finally{busy=false;RaisePropertyChanged(nameof(Available));Update();}
    }
    private async Task<JsonDocument> Run(string option,string action,string target="")
    {
        var file=Path.Combine(paths.LogRoot,"Extras-"+option+"-"+Guid.NewGuid().ToString("N")+".json");
        var args=new List<string>{"-Option",option,"-Action",action,"-ResultPath",file};
        if(target.Length>0){args.Add("-Target");args.Add(target);}
        if(option=="mtu"&&action=="Measure"){args.Add("-Destination");args.Add(Destination.Trim());}
        if(option=="power"&&action=="Apply"){args.AddRange(new[]{"-AcValue",AcValue.ToString(),"-DcValue",DcValue.ToString()});}
        var result=await workers.RunAsync("Manage-BASTOS-Extras.ps1",args.ToArray(),elevate:action is "Apply" or "Restore",timeoutMinutes:3);
        if(!File.Exists(file))throw new Exception(result.Error);
        var doc=JsonDocument.Parse(await File.ReadAllTextAsync(file));
        if(!doc.RootElement.GetProperty("Success").GetBoolean()){var message=doc.RootElement.GetProperty("Message").GetString();doc.Dispose();throw new Exception(message);}
        return doc;
    }
    private void SetItems(string option,JsonElement root)
    {
        var items=JsonSerializer.Deserialize<ExtraItem[]>(root.GetProperty("Items").GetRawText())??Array.Empty<ExtraItem>();
        var list=option=="usb"?UsbDevices:option=="mtu"?Adapters:option=="power"?PowerOptions:Apps;
        var old=option=="usb"?SelectedUsb:option=="mtu"?SelectedAdapter:option=="power"?SelectedPower:SelectedApp;
        list.Clear();foreach(var item in items)list.Add(item);
        var selected=list.FirstOrDefault(i=>i.Id==old?.Id)??list.FirstOrDefault();
        switch(option){case "usb":SelectedUsb=selected;break;case "mtu":SelectedAdapter=selected;break;case "power":SelectedPower=selected;break;default:SelectedApp=selected;break;}
    }
    private async Task Read(string option){using var doc=await Run(option,"Get");SetItems(option,doc.RootElement);Status="État relu. Aucun réglage modifié.";if(option=="apps")AppStatus=Status;}
    private async Task Change(string option,string action,string target)
    {
        Status=action=="Measure"?"Diagnostic en cours…":"Sauvegarde et vérification…";
        using var doc=await Run(option,action,target);
        var message=doc.RootElement.GetProperty("Message").GetString()??"Opération terminée.";
        if(option is "chrome" or "firefox" or "discord"){await Read("apps");}
        else SetItems(option,doc.RootElement);
        Status=message;
        if(option=="mtu"){MtuStatus=message;if(action=="Measure")measuredAdapter=target;else measuredAdapter=null;}
        if(option=="usb")UsbStatus=message;if(option=="power")PowerStatus=message;
    }
    private async Task<JsonDocument> RunFeature(string key,string action)
    {
        var file=Path.Combine(paths.LogRoot,"Profile-"+Guid.NewGuid().ToString("N")+".json");
        var result=await workers.RunAsync("Manage-BASTOS-WinScriptFeature.ps1",new[]{"-Option",key,"-Action",action,"-ResultPath",file},elevate:false,timeoutMinutes:2);
        if(!File.Exists(file))throw new Exception(result.Error);
        var doc=JsonDocument.Parse(await File.ReadAllTextAsync(file));
        if(!doc.RootElement.GetProperty("Success").GetBoolean()){var m=doc.RootElement.GetProperty("Error").GetString();doc.Dispose();throw new Exception(m);}
        return doc;
    }
    private void ResetProfileStates(){foreach(var o in AppearanceOptions){o.Applied=null;o.State="Non vérifié";o.Detail="Actualisation en cours ou lecture non aboutie.";o.CanRestore=false;}}
    internal Task RefreshAppearanceForTestAsync()=>ReadProfiles();
    private async Task ReadProfiles(){ResetProfileStates();using var doc=await RunFeature("Appearance","Status");UpdateProfiles(doc.RootElement);ProfileStatus="Réglages relus séparément. Survole un état pour consulter le détail. Aucun réglage modifié.";}
    private void UpdateProfiles(JsonElement root)
    {
        ResetProfileStates();
        foreach(var item in root.GetProperty("Items").EnumerateArray()){
            var key=item.GetProperty("Option").GetString();var o=AppearanceOptions.FirstOrDefault(o=>o.Key==key);if(o==null)continue;
            var active=item.GetProperty("Active").GetBoolean();
            bool unknown=item.TryGetProperty("DetectionState",out var detection) && detection.GetString()=="Unavailable";
            o.Applied=unknown?null:active;
            o.State=item.TryGetProperty("StateLabel",out var label)?label.GetString()??"Non vérifié":key=="ClassicContextMenu" ? (active?"Configuré — affichage à vérifier":"Menu récent ou configuration différente") : active?"Appliqué":"Non appliqué";
            o.Detail=item.TryGetProperty("Detail",out var detail)?detail.GetString()??"":"";
            o.CanRestore=key=="ClassicContextMenu" ? item.TryGetProperty("DefaultAvailable",out var available) && available.GetBoolean() : item.GetProperty("BackupAvailable").GetBoolean();
        }
    }
    private async Task ChangeProfile(string action)
    {
        var chosen=AppearanceOptions.Where(o=>o.Selected&&(action!="Restore"||o.CanRestore)).Select(o=>o.Key).ToArray();var completed=0;
        try{
            foreach(var key in chosen){using var doc=await RunFeature(key,action);UpdateProfiles(doc.RootElement);completed++;}
            if(chosen.Any(key=>key is "ClassicContextMenu" or "TaskbarLeft" or "ShowFileExtensions" or "ShowHiddenFiles"))
                using(var refresh=await RunFeature("All","RefreshShell")){}
            await ReadProfiles();
        }
        catch(Exception ex){ProfileStatus=$"Opération partielle : {completed}/{chosen.Length}. "+ex.Message;Status=ProfileStatus;return;}
        ProfileStatus=action=="Apply"
            ? (chosen.Contains("ClassicContextMenu") ? "Réglages appliqués. La clé du menu classique est enregistrée ; vérifie le clic droit après le redémarrage de l’Explorateur." : "Profil appliqué via les réglages existants de Bastos. Fermez puis rouvrez votre session si l’interface ne reflète pas encore les changements.")
            : (chosen.Contains("ClassicContextMenu") ? "Menu récent demandé ; les autres choix ont repris leurs valeurs sauvegardées. Vérifie le clic droit dans l’Explorateur." : "Valeurs sauvegardées restaurées via les réglages existants de Bastos.");
        Status=ProfileStatus;
    }
    internal async Task RefreshForTestAsync(){var until=DateTime.UtcNow.AddSeconds(45);while(busy){if(DateTime.UtcNow>until)throw new Exception("Actualisation occupée.");await Task.Delay(50);}await RefreshAsync();}
    public async Task RefreshAsync(){await Guard(async()=>{foreach(var section in new[]{"apps","usb","mtu","power"})await Read(section);await ReadProfiles();});}
}
