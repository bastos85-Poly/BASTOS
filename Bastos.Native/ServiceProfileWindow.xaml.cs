using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using Bastos.Native.Services;

namespace Bastos.Native;
public partial class ServiceProfileWindow : Window
{
    private readonly PowerShellWorkerService workers;
    private readonly AppPaths paths;
    private string snapshot = "";
    private bool busy;
    private string summarySource="";
    private void UpdateSummary()=>Summary.Text=string.Join("\n",summarySource.Split('\n').Select(InterfaceLanguage.Instance.Translate));
    private void LanguageChanged(object? sender,System.ComponentModel.PropertyChangedEventArgs e){if(summarySource.Length>0)UpdateSummary();}
    internal Task AnalysisTask { get; private set; } = Task.CompletedTask;
    internal bool AnalysisReady => !busy && snapshot.Length==64 && ServiceRows.Items.Count>0;
    public ServiceProfileWindow(PowerShellWorkerService workers, AppPaths paths)
    {
        this.workers=workers;this.paths=paths;InitializeComponent();LocalizedPresentation.Watch(this);
        InterfaceLanguage.Instance.PropertyChanged+=LanguageChanged;
        Closed+=(_,_)=>InterfaceLanguage.Instance.PropertyChanged-=LanguageChanged;
        Loaded+=async (_,_)=>await (AnalysisTask=RunAsync("Get"));
        Closing+=(_,e)=>{if(busy)e.Cancel=true;};
    }
    private async void AnalyzeClick(object sender,RoutedEventArgs e)=>await RunAsync("Get");
    private async void ApplyClick(object sender,RoutedEventArgs e)
    {
        if(LocalizedMessageBox.Show(
            "Ce profil inclut les services de sécurité, Windows Update, Bluetooth, impression, Xbox, sauvegardes et Bureau à distance. Les démarrages seront désactivés après sauvegarde. Aucun service ne sera supprimé. Un redémarrage sera nécessaire ; BASTOS ne redémarre pas le PC. Appliquer le profil complet ?",
            "Désactiver les services",MessageBoxButton.YesNo,MessageBoxImage.Warning,MessageBoxResult.No)==MessageBoxResult.Yes)await RunAsync("Apply");
    }
    private async void RestoreClick(object sender,RoutedEventArgs e)=>await RunAsync("Restore");
    private async Task RunAsync(string action)
    {
        if(busy)return;
        busy=true;AnalyzeButton.IsEnabled=ApplyButton.IsEnabled=RestoreButton.IsEnabled=false;
        Summary.Text=action=="Get"?"Analyse des services en cours…":"Sauvegarde et vérification des services en cours…";
        try
        {
            var file=Path.Combine(paths.LogRoot,"Services-"+Guid.NewGuid().ToString("N")+".json");
            var arguments=new System.Collections.Generic.List<string>{"-Action",action,"-ResultPath",file};
            if(action!="Get"){arguments.Add("-ExpectedSnapshotHash");arguments.Add(snapshot);}
            var result=await workers.RunAsync("Manage-BASTOS-Services.ps1",arguments,elevate:action!="Get",timeoutMinutes:5);
            if(!File.Exists(file))throw new IOException(result.Error);
            using var document=JsonDocument.Parse(await File.ReadAllTextAsync(file));var root=document.RootElement;
            snapshot=root.GetProperty("SnapshotHash").GetString()??"";
            ServiceRows.ItemsSource=root.GetProperty("Rows").EnumerateArray().Select(row=>new {
                Name=row.GetProperty("Name").GetString(),DisplayName=row.GetProperty("DisplayName").GetString(),
                Mode=row.GetProperty("StartMode").GetString() switch {"Auto"=>"Automatique","Manual"=>"Manuel","Disabled"=>"Désactivé",_=>"—"},
                Outcome=row.GetProperty("Outcome").GetString() switch {"Unavailable"=>"Absent ou pilote noyau (ignoré)","Detected"=>"Détecté","AlreadyDisabled"=>"Déjà désactivé","Disabled"=>"Désactivation vérifiée","Restored"=>"Restauration vérifiée","NoBackup"=>"Aucune modification à restaurer",_=>"Refus ou échec — voir le détail"},
                Error=row.GetProperty("Error").GetString()??""
            }).ToArray();
            summarySource=string.Format("{0} détectés · {1} désactivés · {2} absents ou pilotes ignorés · {3} refus ou échecs.",root.GetProperty("Present").GetInt32(),root.GetProperty("Disabled").GetInt32(),root.GetProperty("Unavailable").GetInt32(),root.GetProperty("Failed").GetInt32());
            var error=root.GetProperty("Error").GetString();if(!string.IsNullOrWhiteSpace(error))summarySource+="\n"+error;
            if(root.GetProperty("RestartRequired").GetBoolean())summarySource+="\nRedémarrez Windows pour prendre en compte les changements de démarrage.";
            UpdateSummary();
            ApplyButton.IsEnabled=RestoreButton.IsEnabled=!string.IsNullOrWhiteSpace(snapshot);
        }
        catch(Exception ex){snapshot="";Summary.Text=InterfaceLanguage.Instance.Translate("Opération non confirmée : ")+ex.Message;}
        finally{busy=false;AnalyzeButton.IsEnabled=true;}
    }
}
