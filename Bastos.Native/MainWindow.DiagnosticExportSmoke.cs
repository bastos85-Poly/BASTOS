using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunDiagnosticExportSmokeAsync(MainViewModel main)
    {
        string root=Path.Combine(Path.GetTempPath(),"Diagnostic-fixture-"+Guid.NewGuid().ToString("N")),directory=Path.Combine(root,"Operations");Directory.CreateDirectory(directory);
        string id=Guid.NewGuid().ToString("N"),file=Path.Combine(directory,id+".operation.json");
        var result=new OperationResult{OperationId=id,Name="Préparation Recovery (simulation)",State=OperationState.Failed,ErrorCode="RECOVERY_PREPARATION_FAILED",StartedUtc=DateTime.UtcNow,
            Message="Fichier absent : C:\\Users\\FixtureUser\\Private.iso",TechnicalDetail="token=PRIVATE_FIXTURE_SECRET",ResumeIntent=new("RecoveryPreparation"),
            Checks=new[]{new OperationCheck("Image Windows",false,"Fichier de travail indisponible."),new OperationCheck("Nom du PC",false,"Demande : PRIVATE-PC")}};
        string original=JsonSerializer.Serialize(result);File.WriteAllText(file,original);
        var service=new DiagnosticExportService(root,"7.120.28","10.0.26200.1",new DiagnosticRedactor(new[]{"FixtureUser","PRIVATE-PC"}));
        var model=new DiagnosticExportViewModel(service,id);await model.PrepareAsync();
        var window=new DiagnosticExportWindow(model){Owner=this};window.Show();
        // Loaded may refresh the preview once. Wait for that bounded local read.
        await model.RefreshCommand.ExecuteAsync();
        for(int i=0;i<100&&model.IsBusy;i++)await Task.Delay(25);
        try{
            void Capture(string state){window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Diagnostic-"+state+".png"));png.Save(output);}
            Capture("Summary");
            if(!window.DiagnosticSaveButton.IsEnabled||window.DiagnosticDetails.IsChecked!=false||!ReferenceEquals(window.DiagnosticRefreshButton.Command,model.RefreshCommand)||
                !window.DiagnosticPreview.Text.Contains("RECOVERY_PREPARATION_FAILED")||model.Preview.Contains("FixtureUser"))throw new InvalidOperationException("Apercu WPF absent ou non protege par defaut.");
            if(!ReferenceEquals(OperationsJournalPage.OpenDiagnosticExportButton.Command,main.OpenDiagnosticExportCommand))throw new InvalidOperationException("Bouton Journal non lie a l export.");
            model.IncludeDetails=true;window.UpdateLayout();
            if(window.DiagnosticSaveButton.IsEnabled||window.DiagnosticPreview.Text.Length!=0)throw new InvalidOperationException("Ancien apercu encore exportable apres changement d option.");
            await model.RefreshCommand.ExecuteAsync();Capture("Details");
            if(!window.DiagnosticSaveButton.IsEnabled||model.Preview.Contains("PRIVATE_FIXTURE_SECRET")||model.Preview.Contains("PRIVATE-PC")||model.Preview.Contains("FixtureUser"))throw new InvalidOperationException("Details non masques.");
            string frozen=model.Preview,target=Path.Combine(root,"Export.zip");await model.ExportAsync(target);
            using(var zip=ZipFile.OpenRead(target)){
                if(zip.Entries.Count!=3)throw new InvalidOperationException("Inventaire ZIP incorrect.");
                foreach(var entry in zip.Entries){using var reader=new StreamReader(entry.Open());if(!frozen.Contains(reader.ReadToEnd()))throw new InvalidOperationException("ZIP different de l apercu.");}
            }
            if(File.ReadAllText(file)!=original||!model.Status.Contains("créée et vérifiée"))throw new InvalidOperationException("Historique modifie ou verification archive absente.");
            File.Delete(file);await model.RefreshCommand.ExecuteAsync();Capture("Missing");
            if(window.DiagnosticSaveButton.IsEnabled||model.Preview.Length!=0)throw new InvalidOperationException("Rapport disparu conserve dans l apercu.");
        }finally{window.Close();}
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Diagnostic-SmokeTest.txt"),"OK : WPF resume protege, details masques, changement options invalide l apercu, ZIP identique et verifie, rapport absent refuse, originaux intacts. Fixtures isolees, aucun envoi.");
    }
}
