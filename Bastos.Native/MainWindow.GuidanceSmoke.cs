using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Models;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunGuidanceSmokeAsync()
    {
        string root=Path.Combine(Path.GetTempPath(),"Guidance-fixtures-"+Guid.NewGuid().ToString("N"));
        var history=new OperationHistoryService(root);Directory.CreateDirectory(history.DirectoryPath);
        var fixtures=new[]{
            new OperationResult {Name="Recovery — profil indisponible (simulation)",State=OperationState.Failed,ExecutionStarted=true,
                ErrorCode="RECOVERY_PROFILE_FAILED",Phase="Profil d’installation",Message="Détail original conservé",TechnicalDetail="fixture technique de test"},
            new OperationResult {Name="Installation encore à vérifier (simulation)",State=OperationState.Unconfirmed,ProcessStopped=false,
                ErrorCode="TIMEOUT_UNCONFIRMED",Phase="Installation",Message="Fin inconnue"},
            new OperationResult {Name="Nettoyage partiel (simulation)",State=OperationState.Partial,
                Message="3 fichiers supprimés ; 2 fichiers conservés car utilisés.",Phase="Vérification du résultat"}};
        foreach(var fixture in fixtures){string id=Guid.NewGuid().ToString("N");File.WriteAllText(Path.Combine(history.DirectoryPath,id+".operation.json"),
            JsonSerializer.Serialize(fixture with{OperationId=id,StartedUtc=DateTime.UtcNow}));}
        var vm=new JournalViewModel(new AppPaths(),history);await vm.RefreshAsync();
        var page=new JournalPage{DataContext=vm};
        var window=new Window{Title="BASTOS — Erreurs utiles (données simulées)",Content=page,Owner=this,Width=1100,Height=790,Background=new SolidColorBrush(Color.FromRgb(10,16,29))};
        window.Show();
        try
        {
            IEnumerable<T> Descendants<T>(DependencyObject item) where T:DependencyObject
            {
                if(item is T match)yield return match;
                for(int i=0;i<VisualTreeHelper.GetChildrenCount(item);i++)foreach(var child in Descendants<T>(VisualTreeHelper.GetChild(item,i)))yield return child;
            }
            void Capture(string name){window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);
                bitmap.Render(window);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Guidance-"+name+".png"));png.Save(output);}
            foreach(var fixture in fixtures)
            {
                vm.Selected=vm.Entries.Single(e=>e.Name==fixture.Name);window.UpdateLayout();
                var text=Descendants<TextBlock>(page).Where(t=>t.IsVisible).Select(t=>t.Text).ToArray();
                if(!text.Contains(vm.Selected.Effects)||!text.Contains(vm.Selected.NextStep)||Descendants<Expander>(page).Any(e=>e.IsExpanded))
                    throw new InvalidOperationException("Conseils du Journal absents ou détails ouverts par défaut.");
                Capture(fixture.ErrorCode.Length>0?fixture.ErrorCode:"Partial");
            }
            vm.Selected=vm.Entries.Single(e=>e.Result.ErrorCode=="RECOVERY_PROFILE_FAILED");window.UpdateLayout();
            Descendants<Expander>(page).Single().IsExpanded=true;Capture("Technical");
            File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Guidance-SmokeTest.txt"),
                "OK : vrais contrôles WPF Journal avec trois rapports simulés isolés ; effets et actions liés ; détails fermés par défaut et consultables. Aucun worker ni disque modifié.");
        }
        finally{window.Close();}
        // Exercise the same shared result control used by the actual module pages.
        var control=new OperationMessageView{Foreground=(Brush)FindResource("WarningBrush"),Margin=new Thickness(20),
            Text=(fixtures[1] with{OperationId=Guid.NewGuid().ToString("N")}).UserMessage+" Aucun redémarrage demandé.",
            Detail="Code : TIMEOUT_UNCONFIRMED\nChemin du rapport : D:\\Simulation\\resultat.json"};
        var messageWindow=new Window{Title="BASTOS — Résultat simplifié (simulation)",Content=control,Owner=this,
            Width=720,Height=350,Background=(Brush)FindResource("SurfaceBrush")};
        messageWindow.Show();
        try
        {
            messageWindow.UpdateLayout();
            var blocks=((StackPanel)control.Content).Children.OfType<TextBlock>().Where(t=>t.IsVisible).Select(t=>t.Text).ToArray();
            var disclosure=((StackPanel)control.Content).Children.OfType<Expander>().Single();
            if(!blocks.Any(t=>t.Contains("Ne lance pas"))||!blocks.Any(t=>t.Contains("encore travailler"))||
                !blocks.Any(t=>t.Contains("Aucun redémarrage demandé"))||disclosure.IsExpanded)
                throw new InvalidOperationException("Une consigne utile a été masquée dans les détails.");
            SaveSmokeVisual(messageWindow,"BASTOS-Messages-Compact.png");
            disclosure.IsExpanded=true;messageWindow.UpdateLayout();
            if(disclosure.Content is not TextBox diagnostic||!diagnostic.IsVisible||!diagnostic.IsReadOnly||!diagnostic.Text.Contains("D:\\Simulation\\resultat.json"))
                throw new InvalidOperationException("Diagnostic technique non consultable.");
            SaveSmokeVisual(messageWindow,"BASTOS-Messages-Details.png");
            File.AppendAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Guidance-SmokeTest.txt"),
                "\nOK : contrôle partagé réel ; avertissements visibles, références et diagnostic dépliables et copiables.");
        }
        finally{messageWindow.Close();}
    }
}
