using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private Task RunCursorSmokeAsync()
    {
        var folder=Path.Combine(Path.GetTempPath(),"BASTOS-Cursor-UI");Directory.CreateDirectory(folder);var checks=new System.Collections.Generic.List<string>();
        void Check(bool ok,string text){if(!ok)throw new Exception(text);checks.Add(text);}
        var fixture=Path.Combine(folder,"Data-"+Guid.NewGuid().ToString("N"));var paths=new AppPaths(applicationRoot:null,dataRoot:fixture);var service=new CursorPackService(paths);
        string Values(){using var key=Registry.CurrentUser.OpenSubKey(@"Control Panel\Cursors");using var schemes=Registry.CurrentUser.OpenSubKey(@"Control Panel\Cursors\Schemes");return string.Join("\n",new[]{"","Arrow","Help","AppStarting","Wait","Crosshair","IBeam","NWPen","No","SizeNS","SizeWE","SizeNWSE","SizeNESW","SizeAll","UpArrow","Hand","Person","Pin","Scheme Source"}.Select(n=>n+":"+(key?.GetValueNames().Contains(n)==true?key.GetValueKind(n)+":"+key.GetValue(n,null,RegistryValueOptions.DoNotExpandEnvironmentNames):"absent")))+"\n"+(schemes?.GetValue(CursorPackService.SchemeName)??"absent");}
        var original=Values();
        try{
            Check(service.ReadStatus().Available,"Pack contains all cursors and license");Check(Values()==original&&!File.Exists(Path.Combine(fixture,"CursorPack.json")),"Reading availability does not write preferences or backup");
            var message=service.Apply();Check(service.ReadStatus().Applied,"All cursor roles and scheme registration applied and read back");
            var first=File.ReadAllText(Path.Combine(fixture,"CursorPack.json"));service.Apply();Check(File.ReadAllText(Path.Combine(fixture,"CursorPack.json"))==first,"Repeated activation preserves original backup");
            Check(Directory.GetFiles(Path.Combine(fixture,"Cursors"),"*.cur",SearchOption.AllDirectories).Length==15&&Directory.GetFiles(Path.Combine(fixture,"Cursors"),"*.ani",SearchOption.AllDirectories).Length==2,"15 static and two animated cursors persist in the user folder");
            service.Restore();Check(Values()==original,"Original cursor roles, types, scheme name and registration restored exactly");
            service.Apply();using(var key=Registry.CurrentUser.CreateSubKey(@"Control Panel\Cursors"))key.SetValue("Arrow","external-test.cur",RegistryValueKind.String);
            service.Restore();using(var key=Registry.CurrentUser.OpenSubKey(@"Control Panel\Cursors"))Check((string?)key.GetValue("Arrow")=="external-test.cur","Restoration preserves an externally changed cursor");
            // Return the single external fixture value to the initial snapshot.
            var backup=Directory.GetFiles(fixture,"CursorPack.json.restored-*").OrderByDescending(File.GetLastWriteTimeUtc).First();var b=System.Text.Json.JsonSerializer.Deserialize<CursorPackService.Backup>(File.ReadAllText(backup))!;var arrow=b.Original.Single(e=>e.Name=="Arrow");using(var key=Registry.CurrentUser.CreateSubKey(arrow.Path)){if(arrow.Exists)key.SetValue(arrow.Name,arrow.Data,Enum.Parse<RegistryValueKind>(arrow.Kind));else key.DeleteValue(arrow.Name,false);}
            Check(Values()==original,"External fixture cleaned up without changing the initial theme");
            var unavailable=new CursorPackService(new AppPaths(applicationRoot:Path.Combine(folder,"missing-pack"),dataRoot:Path.Combine(folder,"missing-data")));bool refused=false;try{unavailable.Apply();}catch(FileNotFoundException){refused=true;}Check(refused&&Values()==original,"Missing pack is refused before changing cursor preferences");
            var vm=new CursorPackViewModel(paths,_=>{});Content=new ScrollViewer{Content=new CursorPackPage{DataContext=vm}};UpdateLayout();var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using(var f=File.Create(Path.Combine(folder,"curseurs.png")))png.Save(f);
            Check(Values()==original,"Rendering the activation card does not apply the pack");File.WriteAllText(Path.Combine(folder,"Result.txt"),"PASS\n"+checks.Count+" checks\n"+string.Join("\n",checks));Application.Current.Shutdown(0);
        }catch(Exception ex){try{if(File.Exists(Path.Combine(fixture,"CursorPack.json")))service.Restore();}catch{}File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
        return Task.CompletedTask;
    }
}
