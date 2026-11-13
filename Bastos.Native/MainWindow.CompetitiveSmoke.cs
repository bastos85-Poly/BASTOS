using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunCompetitiveSmokeAsync()
    {
        var folder=Path.Combine(Path.GetTempPath(),"BASTOS-Competitive-UI");Directory.CreateDirectory(folder);
        try
        {
            var model=(MainViewModel)DataContext;
            if(model.SoundOptimizationCards.Count!=2||model.CompetitiveNetworkCards.Count!=1||model.CompetitiveGameCards.Count!=4)
                throw new Exception("Les sept reglages ne sont pas repartis dans les categories attendues.");
            await model.RefreshCompetitiveForTestAsync();
            var all=model.SoundOptimizationCards.Concat(model.CompetitiveNetworkCards).Concat(model.CompetitiveGameCards).ToArray();
            if(all.Any(c=>c.State.StartsWith("État non vérifié")||c.State.Contains("ENGINE_")||c.State.Contains("fichiers de la même version")))
                throw new Exception("Le moteur des reglages n'a pas pu etre interroge via le controle d'integrite.");
            model.SelectedNavigation=model.Navigation.First(n=>n.PageKey=="optimizations");
            foreach(var key in new[]{"sound","network","windows"})
            {
                model.OptimizationCategories.Selected=model.OptimizationCategories.Items.Single(c=>c.Key==key);
                UpdateLayout();
                var image=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);image.Render(this);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using var output=File.Create(Path.Combine(folder,key+".png"));png.Save(output);
            }
            model.OptimizationCategories.Selected=model.OptimizationCategories.Items.Single(c=>c.Key=="sound");UpdateLayout();
            var text=model.SoundOptimizationCards.Select(c=>c.Title+" : "+c.State);
            File.WriteAllText(Path.Combine(folder,"Result.txt"),"PASS\nSeven options, category navigation, read-only workers and embedded integrity validated.\n"+string.Join("\n",text));
            Application.Current.Shutdown(0);
        }
        catch(Exception ex){File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
    }
}
