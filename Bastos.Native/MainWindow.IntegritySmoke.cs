using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
using Bastos.Native.Models;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunIntegritySmokeAsync()
    {
        var installed=new AppPaths();int checkedFiles;
        using(var lease=await Task.Run(()=>new WorkerIntegrityService(installed.Root).Acquire("Initialize-BASTOS-Recovery.ps1")))checkedFiles=lease.CheckedFiles;
        string root=Path.Combine(Path.GetTempPath(),"Integrity-fixture-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        using var stream=typeof(WorkerIntegrityService).Assembly.GetManifestResourceStream("Bastos.EngineIntegrity.json")!;
        using var catalog=JsonDocument.Parse(stream);
        foreach(var file in catalog.RootElement.GetProperty("Files").EnumerateArray()){
            string relative=file.GetProperty("Path").GetString()!,target=Path.Combine(root,relative);Directory.CreateDirectory(Path.GetDirectoryName(target)!);File.Copy(Path.Combine(installed.Root,relative),target);
        }
        File.AppendAllText(Path.Combine(root,"Bastos.Operation.psm1"),"\r\n# fixture modified module\r\n");
        var paths=new AppPaths(root,Path.Combine(root,"Data"));var log=new OperationLogService(paths);var workers=new PowerShellWorkerService(paths,new ProcessExecutionService(),log);
        var service=new VerifiedOperationService(paths.LogRoot,(script,args)=>workers.RunAsync(script,args),(_,_,_)=>{});
        var result=await service.RunAsync("Contrôle des fichiers (fixture isolée)","Initialize-BASTOS-Recovery.ps1",new[]{"-Action","Status"},_=>throw new InvalidOperationException("Le controle du resultat ne doit pas etre appele."));
        if(result.ErrorCode!="ENGINE_FILE_CHANGED"||result.ExecutionStarted!=false||!result.Message.Contains("Bastos.Operation.psm1")||File.Exists(result.WorkerReportPath)||
            File.Exists(Path.Combine(paths.LogRoot,"Operations",result.OperationId+".process.json")))throw new InvalidOperationException("Module modifie non bloque avant lancement.");
        var model=new JournalViewModel(paths);await model.RefreshAsync();
        if(model.Selected?.Result.ErrorCode!="ENGINE_FILE_CHANGED"||!model.Selected.NextStep.Contains("même version"))throw new InvalidOperationException("Erreur integrite absente du Journal.");
        var window=new Window{Owner=this,Title="Bastos — Intégrité (fixture isolée)",Content=new JournalPage{DataContext=model},Width=1100,Height=880,Background=new SolidColorBrush(Color.FromRgb(10,16,29))};window.Show();
        try{
            window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
            var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Integrity-Blocked.png"));png.Save(output);
        }finally{window.Close();}
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Integrity-SmokeTest.txt"),"OK : "+checkedFiles+" fichiers reels conformes ; module modifie d une copie isolee bloque avant PID, aucune commande Recovery executee, erreur precise et consigne visibles dans Journal.");
    }
}
