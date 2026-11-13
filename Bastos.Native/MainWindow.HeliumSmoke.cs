using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private void RunHeliumSmoke(MainViewModel model)
    {
        var properties = new[]{"IsChromeSelected","IsFirefoxSelected","IsLibreWolfSelected","IsBraveSelected","IsUngoogledSelected","IsThoriumSelected","IsOperaSelected","IsHeliumSelected"}
            .Select(name => typeof(MainViewModel).GetProperty(name)!).ToArray();
        int checks = 0;
        foreach(var first in properties) foreach(var second in properties)
        {
            first.SetValue(model, true); second.SetValue(model, true);
            if(model.SelectedBrowserCount != 1 || !(bool)second.GetValue(model)!) throw new Exception("Sélection exclusive : " + first.Name + " / " + second.Name);
            checks++;
        }
        model.ClearBrowserSelectionCommand.Execute(null);
        if(model.SelectedBrowserCount != 0) throw new Exception("Effacement de la sélection Helium");
        model.IsHeliumSelected = true;
        if(!model.InstallSelectedBrowsersCommand.CanExecute(null) || !model.UninstallSelectedBrowsersCommand.CanExecute(null)) throw new Exception("Commandes Helium indisponibles");
        var candidates = ((ValueTuple<string,string>[])typeof(MainViewModel).GetField("BrowserReplacementCandidates", BindingFlags.Static|BindingFlags.NonPublic)!.GetValue(null)!);
        if(candidates.Count(c => c.Item1 == "helium") != 1) throw new Exception("Helium absent du remplacement inverse");
        model.SelectedNavigation = model.Navigation.First(n => n.PageKey == "browsers");
        UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32); bitmap.Render(this);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
        using(var output=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Helium.png"))) png.Save(output);
        model.ClearBrowserSelectionCommand.Execute(null);
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Helium-SmokeTest.txt"), $"OK : {checks} transitions exclusives, effacement, commandes et remplacement inverse. Aucune installation ni désinstallation réelle.");
    }
}
