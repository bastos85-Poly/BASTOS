using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
using Bastos.Native.Models;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunLogMaintenanceSmokeAsync(MainViewModel main)
    {
        string root=Path.Combine(Path.GetTempPath(),"Maintenance-fixture-"+Guid.NewGuid().ToString("N")),ops=Path.Combine(root,"Operations");Directory.CreateDirectory(ops);
        DateTime now=DateTime.UtcNow;
        string Add(int days,OperationState state){string id=Guid.NewGuid().ToString("N"),path=Path.Combine(ops,id+".operation.json");
            var result=new OperationResult{OperationId=id,Name=days>30?"Ancienne opération (fixture isolée)":"Opération récente (fixture)",State=state,StartedUtc=now.AddDays(-days).AddMinutes(-1),EndedUtc=now.AddDays(-days)};
            File.WriteAllText(path,JsonSerializer.Serialize(result));File.SetLastWriteTimeUtc(path,now.AddDays(-days));return id;}
        for(int i=0;i<200;i++)Add(1,OperationState.Succeeded);
        string old=Add(61,OperationState.Succeeded),failed=Add(61,OperationState.Failed);
        foreach(string suffix in new[]{".progress.txt",".operation.json.tmp"}){string file=Path.Combine(ops,old+suffix);File.WriteAllText(file,"ancienne donnée de travail");File.SetLastWriteTimeUtc(file,now.AddDays(-61));}
        string archive=Path.Combine(root,"BASTOS-Native-Archive-"+now.AddDays(-61).ToString("yyyyMMdd'T'HHmmssfff")+"-"+Guid.NewGuid().ToString("N")+".log");File.WriteAllText(archive,"INFO archived fixture");File.SetLastWriteTimeUtc(archive,now.AddDays(-61));
        var model=new LogMaintenanceViewModel(new LogMaintenanceService(root,(_,_)=>false,()=>DateTime.UtcNow));await model.AnalyzeAsync();
        var window=new LogMaintenanceWindow(model){Owner=this};window.Show();
        for(int i=0;i<100&&model.IsBusy;i++)await Task.Delay(25);
        try{
            void Capture(string stage){window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Maintenance-"+stage+".png"));png.Save(output);}
            Capture("Preview");
            if(!ReferenceEquals(OperationsJournalPage.OpenLogMaintenanceButton.Command,main.OpenLogMaintenanceCommand)||!ReferenceEquals(window.MaintenanceAnalyzeButton.Command,model.AnalyzeCommand)||!window.MaintenanceCleanButton.IsEnabled||model.Rows.Count(r=>r.Eligible)!=2)
                throw new InvalidOperationException("Apercu maintenance ou boutons WPF non lies.");
            model.KeepDays=90;window.UpdateLayout();if(window.MaintenanceCleanButton.IsEnabled||model.Rows.Count!=0)throw new InvalidOperationException("Apercu non invalide apres changement de retention.");
            await model.AnalyzeAsync();if(model.CanClean)throw new InvalidOperationException("Retention 90 jours non appliquee.");
            model.KeepDays=30;await model.AnalyzeAsync();foreach(var row in model.Rows.Where(r=>r.Eligible))row.Selected=row.Item.Id==old;
            await model.CleanAsync();Capture("Result");
            if(File.Exists(Path.Combine(ops,old+".operation.json"))||!File.Exists(Path.Combine(ops,failed+".operation.json"))||!File.Exists(archive)||!model.Status.Contains("3 fichier(s) supprimé(s)")||model.CanClean)
                throw new InvalidOperationException("Nettoyage de fixture incorrect ou ancien apercu reutilisable.");
        }finally{window.Close();}
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Maintenance-SmokeTest.txt"),"OK : WPF apercu, tailles, protection erreurs/200 rapports, selection, changement retention, nettoyage de trois fichiers dans une fixture isolee et bilan local. Aucun journal utilisateur supprime.");
    }
}
