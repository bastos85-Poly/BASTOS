using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunResumeSmokeAsync()
    {
        string root=Path.Combine(Path.GetTempPath(),"Resume-fixture-"+Guid.NewGuid().ToString("N"));
        var history=new OperationHistoryService(root);Directory.CreateDirectory(history.DirectoryPath);
        string id=Guid.NewGuid().ToString("N"),file=Path.Combine(history.DirectoryPath,id+".operation.json");
        var original=new OperationResult{OperationId=id,Name="Préparation interrompue (simulation)",StartedUtc=DateTime.UtcNow,State=OperationState.Running,
            OwnerProcessId=999999,OwnerProcessStartedUtc=DateTime.UtcNow,ExecutionStarted=true,ResumeIntent=new("RecoveryPreparation")};
        string originalText=JsonSerializer.Serialize(original);File.WriteAllText(file,originalText);
        File.WriteAllText(Path.Combine(history.DirectoryPath,id+".process.json"),JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,ProcessId=888888,StartedUtc=DateTime.UtcNow}));
        File.WriteAllText(Path.Combine(history.DirectoryPath,id+".worker.json"),JsonSerializer.Serialize(new{SchemaVersion=1,OperationId=id,Success=true}));
        int probes=0,routes=0;bool unchanged=true;
        var resume=new OperationResumeService(root,(_,_)=>{probes++;return Task.FromResult(new OperationVerification(unchanged,unchanged?"Les fichiers existants ont été relus et vérifiés (simulation).":"Les fichiers ont changé : nouvelle préparation à vérifier (simulation).",Array.Empty<OperationCheck>()));},(_,_)=>false,_=>false);
        var vm=new JournalViewModel(new AppPaths(),history,resume,_=>routes++);await vm.RefreshAsync();
        if(probes!=0||routes!=0)throw new InvalidOperationException("Une reprise a demarre sans clic.");
        var page=new JournalPage{DataContext=vm};
        var window=new Window{Title="BASTOS — Reprise (données simulées)",Owner=this,Content=page,Width=1100,Height=900,Background=new SolidColorBrush(Color.FromRgb(10,16,29))};window.Show();
        try
        {
            window.UpdateLayout();
            if(!page.CheckResumeButton.IsEnabled||!ReferenceEquals(page.CheckResumeButton.Command,vm.CheckResumeCommand))throw new InvalidOperationException("Controle de reprise WPF non lie.");
            void Capture(string state){window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Resume-"+state+".png"));png.Save(output);}
            await vm.CheckResumeCommand.ExecuteAsync();if(probes!=1||!vm.ResumeStatus.Contains("vérifiés"))throw new InvalidOperationException("Resultat de reprise WPF absent.");Capture("Verified");
            var reopened=new JournalViewModel(new AppPaths(),history,resume,_=>routes++);await reopened.RefreshAsync();
            if(probes!=1||!reopened.ResumeStatus.Contains("Dernier contrôle")||!reopened.ResumeStatus.Contains("Revérifie"))throw new InvalidOperationException("Dernier controle perdu a la reouverture ou action rejouee.");
            vm.ContinueInModuleCommand.Execute(null);if(routes!=1)throw new InvalidOperationException("Retour au module absent.");
            unchanged=false;await vm.CheckResumeCommand.ExecuteAsync();if(!vm.ResumeStatus.Contains("changé")||File.ReadAllText(file)!=originalText)throw new InvalidOperationException("Resultat modifie non refuse ou historique ecrase.");Capture("Changed");
        }
        finally{window.Close();}
        // Real production launcher receipt, using the read-only storage status worker.
        var paths=new AppPaths();var runner=new ProcessExecutionService();var log=new OperationLogService(paths);var workers=new PowerShellWorkerService(paths,runner,log);
        string receiptId=Guid.NewGuid().ToString("N"),resultPath=Path.Combine(paths.LogRoot,"Operations",receiptId+".worker.json");
        var status=await workers.RunAsync("Initialize-BASTOS-Recovery.ps1",new[]{"-Action","Status","-OperationId",receiptId,"-ResultPath",resultPath,"-RecoveryMode","Novice","-PostInstallMode","WindowsOnly"},timeoutMinutes:2);
        using var receipt=JsonDocument.Parse(File.ReadAllText(Path.Combine(paths.LogRoot,"Operations",receiptId+".process.json")));
        if(!status.Success||receipt.RootElement.GetProperty("OperationId").GetString()!=receiptId||receipt.RootElement.GetProperty("ProcessId").GetInt32()<=0||receipt.RootElement.GetProperty("StartedUtc").GetDateTime()==default)
            throw new InvalidOperationException("Identite du vrai worker non enregistree.");
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Resume-SmokeTest.txt"),"OK : reprise WPF avec rapports simules isoles, aucun lancement automatique, fichiers modifies refuses, retour au module et historique intact ; recu PID/date du vrai worker Status de stockage en lecture seule verifie. Aucune preparation ni installation lancee.");
    }
}
