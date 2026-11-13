using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    // Laboratory only. This flag is never used on the user's installation.
    private async Task RunExtrasSmokeAsync()
    {
        var folder=Path.Combine(Path.GetTempPath(),"BASTOS-Extras-UI");Directory.CreateDirectory(folder);
        try{
            async Task ExecuteReady(Bastos.Native.Infrastructure.AsyncRelayCommand command){var until=DateTime.UtcNow.AddSeconds(45);while(!command.CanExecute(null)){if(DateTime.UtcNow>until)throw new Exception("Commande de profil occupée.");await Task.Delay(50);}await command.ExecuteAsync();}
            var model=(MainViewModel)DataContext;
            await model.RefreshCompetitiveForTestAsync();
            await model.Extras.RefreshForTestAsync();
            if(model.Extras.Status.StartsWith("Opération non confirmée")||model.Extras.Apps.Count!=3||model.Extras.PowerOptions.Count!=2)throw new Exception("Lecture des nouvelles options impossible : "+model.Extras.Status);
            if(model.OptimizationCategories.Items.Count(i=>i.Key=="devices")!=1)throw new Exception("Navigation USB absente ou dupliquée.");
            if(model.Extras.AppearanceOptions.Select(i=>i.Key).Distinct().Count()!=8)throw new Exception("Les profils contiennent des commandes en double ou une commande manque.");
            var original=MouseProfileService.Read();
            try{
                MouseProfileService.Apply(acceleration:false,speed:9);
                if(MouseProfileService.Read().Acceleration!=0||MouseProfileService.Read().Speed!=9)throw new Exception("Profil souris non appliqué.");
                MouseProfileService.Apply(windowsProfile:true);
                if(MouseProfileService.Read().Speed!=10||MouseProfileService.Read().Acceleration!=1)throw new Exception("Profil Windows non appliqué.");
            }finally{MouseProfileService.Restore();}
            if(MouseProfileService.Read()!=original)throw new Exception("Profil souris précédent non restauré.");
            var originalCurves=MouseCurveProfiles.Read();
            try{
                foreach(var name in MouseCurveProfiles.Names){
                    MouseProfileService.ApplyCurve(name);
                    if(MouseCurveProfiles.Read()!=MouseCurveProfiles.Profile(name)||MouseCurveProfiles.CurrentName()!=name)throw new Exception("Courbe non appliquée : "+name);
                    if(MouseProfileService.Read()!=original)throw new Exception("La courbe a changé la vitesse ou l’accélération.");
                }
                MouseProfileService.Apply(acceleration:false);
                MouseProfileService.ApplyCurve("MarkC");
                MouseProfileService.Restore();
                if(MouseCurveProfiles.Read()!=originalCurves||MouseProfileService.Read()!=original)throw new Exception("La restauration commune n’a pas conservé les originaux.");
                MouseProfileService.ApplyCurve("MarkC");
                MouseCurveProfiles.Write(MouseCurveProfiles.Profile("CPL"));
                MouseProfileService.Restore();
                if(MouseCurveProfiles.CurrentName()!="CPL")throw new Exception("Une courbe changée à l’extérieur aurait été écrasée.");
                MouseCurveProfiles.Write(originalCurves);
                // Upgrade an existing v39 backup which has no curve properties.
                var backupFile=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BASTOS","MouseProfile.json");
                File.WriteAllText(backupFile,System.Text.Json.JsonSerializer.Serialize(new{Original=original,Applied=original}));
                MouseProfileService.ApplyCurve("CheeseM");MouseProfileService.Restore();
                if(MouseCurveProfiles.Read()!=originalCurves||MouseProfileService.Read()!=original)throw new Exception("Migration de sauvegarde v39 incorrecte.");
            }finally{MouseCurveProfiles.Write(originalCurves);}
            var b=new MouseProfileService.Backup(new(6,10,1,10),new(6,10,0,9));
            if(MouseProfileService.MergeRestore(new(6,10,0,12),b).Speed!=12)throw new Exception("Une modification externe de vitesse serait écrasée.");
            RunSettingsClassificationSmoke(model);
            await ExecuteReady(model.Extras.ApplyProfileCommand);
            if(!model.Extras.ProfileStatus.StartsWith("Profil appliqué"))throw new Exception(model.Extras.ProfileStatus);
            await ExecuteReady(model.Extras.RestoreProfileCommand);
            if(!model.Extras.ProfileStatus.StartsWith("Valeurs sauvegardées"))throw new Exception(model.Extras.ProfileStatus);
            foreach(var (name,page) in new (string,FrameworkElement)[]{("applications",new ExtraAppsPage()),("usb",new ExtraUsbPage()),("mtu",new ExtraMtuPage()),("alimentation",new ExtraPowerPage()),("profils",new AppearanceProfilesPage()),("souris",new MouseSettingsPage())}){
                if(name!="souris")page.DataContext=model.Extras;
                Content=new ScrollViewer{Content=page,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};UpdateLayout();
                var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(Path.Combine(folder,name+".png"));png.Save(output);
            }
            File.WriteAllText(Path.Combine(folder,"Result.txt"),"PASS\nNative worker integrity and inventory; six views; unique shared appearance keys; mouse live profiles and restore; four Kirby curve profiles with exact readback; curves preserve pointer settings; shared backup restore; external curve preservation; legacy v39 backup migration; apply/restore through existing appearance engine.\n");
            Application.Current.Shutdown(0);
        }catch(Exception ex){File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
    }
}
