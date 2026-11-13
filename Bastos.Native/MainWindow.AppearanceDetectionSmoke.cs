using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.ViewModels;

namespace Bastos.Native;
public partial class MainWindow
{
    // Read-only smoke test: never applies a profile or any Windows setting.
    private async Task RunAppearanceDetectionSmokeAsync()
    {
        string folder=Path.Combine(Path.GetTempPath(),"BASTOS-AppearanceDetection");
        Directory.CreateDirectory(folder);
        int count=0;
        void Check(bool value,string message){if(!value)throw new Exception(message);count++;}
        try
        {
            var model=((MainViewModel)DataContext).Extras;
            var update=typeof(ExtraSettingsViewModel).GetMethod("UpdateProfiles",BindingFlags.NonPublic|BindingFlags.Instance)!;
            void Inject(string state,bool active,string label,bool omit=false)
            {
                var items=model.AppearanceOptions.Where(o=>!omit||o.Key!="DarkMode").Select(o=>new{Option=o.Key,Active=active,DetectionState=state,StateLabel=label,Detail="Détail du contrôle",BackupAvailable=false,DefaultAvailable=false}).ToArray();
                using var json=JsonDocument.Parse(JsonSerializer.Serialize(new{Items=items}));
                update.Invoke(model,new object[]{json.RootElement});
            }
            foreach(var state in new[]{"Applied","Partial","NotApplied","Unavailable"})
            {
                Inject(state,state=="Applied",state);
                Check(model.AppearanceOptions.All(o=>o.State==state&&o.Detail.Length>0),"État et détail de chaque ligne");
                Check(model.AppearanceOptions.All(o=>state=="Unavailable"?o.Applied==null:o.Applied==(state=="Applied")),"État inconnu distinct du désactivé");
            }
            Inject("Applied",true,"Appliqué");Inject("Applied",true,"Appliqué",omit:true);
            Check(model.AppearanceOptions.Single(o=>o.Key=="DarkMode").Applied==null,"Rapport incomplet : aucun ancien succès conservé");
            await model.RefreshAppearanceForTestAsync();
            Check(model.AppearanceOptions.Count==8,"Huit réglages chargés");
            Check(model.AppearanceOptions.All(o=>o.State!="État non vérifié"&&o.Detail.Length>0),"Rapport réel relié à chaque ligne");
            var page=new AppearanceProfilesPage{DataContext=model};
            Content=new ScrollViewer{Content=page,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
            UpdateLayout();
            var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);
            var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(folder,"Apparence.png")))png.Save(stream);
            File.WriteAllText(Path.Combine(folder,"Result.txt"),$"PASS : {count} contrôles WPF ; huit lignes, quatre états, rapport incomplet et lecture réelle. Aucune écriture de réglage Windows.");
            Application.Current.Shutdown(0);
        }
        catch(Exception ex){File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
    }
}
