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
    private Task RunCurvesSmokeAsync()
    {
        var folder=Path.Combine(Path.GetTempPath(),"BASTOS-Curves-UI");Directory.CreateDirectory(folder);
        var checks=new System.Collections.Generic.List<string>();
        void Check(bool ok,string name){if(!ok)throw new Exception(name);checks.Add(name);}
        var before=MouseCurveProfiles.Read();var state=MouseProfileService.Read();
        var backupPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BASTOS","MouseProfile.json");
        try{
            Check(!File.Exists(backupPath),"Test starts without a pending mouse backup");
            Check(MouseCurveProfiles.Names.SequenceEqual(new[]{"Défaut","MarkC","CPL","CheeseM","Courbes nulles"}),"Five expected curve names");
            var vm=new MouseSettingsViewModel(new MouseAccelerationService());vm.Refresh();
            Check(vm.SelectedCurve==MouseCurveProfiles.CurrentName()&&MouseCurveProfiles.Read()==before,"Initial selection reflects Windows without writing curves");
            MouseProfileService.ApplyCurve("MarkC");vm.Refresh();
            Check(vm.SelectedCurve=="MarkC","Refresh identifies applied MarkC");
            var reopened=new MouseSettingsViewModel(new MouseAccelerationService());reopened.Refresh();
            Check(reopened.SelectedCurve=="MarkC","Reopened view reads persisted MarkC");
            reopened.SelectedCurve="CPL";reopened.Refresh();
            Check(reopened.SelectedCurve=="CPL","Background refresh preserves uncommitted selection");
            reopened.SynchronizeCurveSelection();
            Check(reopened.SelectedCurve=="MarkC","Page reentry restores actual Windows selection");
            MouseCurveProfiles.Write(MouseCurveProfiles.Profile("CheeseM"));reopened.Refresh();
            Check(reopened.SelectedCurve=="CheeseM","External curve changes update selection");
            MouseCurveProfiles.Write(new(new(false,""),new(false,"")));reopened.Refresh();
            Check(reopened.SelectedCurve=="Personnalisé"&&reopened.CurveNames.Contains("Personnalisé")&&!reopened.ApplyCurveCommand.CanExecute(null),"Custom curves are displayed honestly and cannot be applied as a preset");
            MouseProfileService.Restore();MouseCurveProfiles.Write(before);
            foreach(var name in MouseCurveProfiles.Names){
                var desired=MouseCurveProfiles.Profile(name);
                Check(Convert.FromBase64String(desired.X.Data).Length==40&&Convert.FromBase64String(desired.Y.Data).Length==40,name+": two 40-byte curves");
                MouseProfileService.ApplyCurve(name);
                Check(MouseCurveProfiles.Read()==desired&&MouseCurveProfiles.CurrentName()==name,name+": exact write and identification");
                Check(MouseProfileService.Read()==state,name+": speed and acceleration unchanged");
            }
            MouseProfileService.ApplyCurve("MarkC");MouseProfileService.Restore();
            Check(MouseCurveProfiles.Read()==before&&MouseProfileService.Read()==state,"Repeated switches restore the first original curves and pointer state");
            MouseProfileService.ApplyCurve("MarkC");MouseCurveProfiles.Write(MouseCurveProfiles.Profile("CPL"));MouseProfileService.Restore();
            Check(MouseCurveProfiles.CurrentName()=="CPL","Restore preserves externally modified curves");MouseCurveProfiles.Write(before);
            File.WriteAllText(backupPath,System.Text.Json.JsonSerializer.Serialize(new{Original=state,Applied=state}));
            MouseProfileService.ApplyCurve("CheeseM");MouseProfileService.Restore();
            Check(MouseCurveProfiles.Read()==before,"Legacy v39 backup migrates without losing original curves");
            MouseCurveProfiles.Write(new(new(false,""),new(false,"")));
            MouseProfileService.ApplyCurve("CPL");MouseProfileService.Restore();
            Check(MouseCurveProfiles.Read()==new MouseCurveProfiles.Pair(new(false,""),new(false,"")),"Missing original curve values are restored by removal");MouseCurveProfiles.Write(before);
            var page=new MouseSettingsPage();Content=new ScrollViewer{Content=page,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};UpdateLayout();
            var image=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);image.Render(this);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using(var f=File.Create(Path.Combine(folder,"souris.png")))png.Save(f);
            Check(MouseCurveProfiles.Read()==before,"Rendering the mouse page does not modify curves");
            File.WriteAllText(Path.Combine(folder,"Result.txt"),"PASS\n"+checks.Count+" checks\n"+string.Join("\n",checks));Application.Current.Shutdown(0);
        }catch(Exception ex){File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
        finally{MouseCurveProfiles.Write(before);}
        return Task.CompletedTask;
    }
}
