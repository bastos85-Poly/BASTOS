using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Win32;
using Bastos.Native.Services;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunPersistenceSmokeAsync(bool verify)
    {
        var folder=Path.Combine(Path.GetTempPath(),"BASTOS-Persistence-UI");Directory.CreateDirectory(folder);
        var ids=new[]{"keyboard","accessibility-hotkeys","background-apps","service-hosts","mmcss-gaming","webdav-limit"};
        var checks=new System.Collections.Generic.List<string>();
        void Check(bool ok,string message){if(!ok)throw new Exception(message);checks.Add(message);}
        try{
            if(!verify){
                NativeWorkerService.SaveStateDocument(Path.Combine(folder,"original.json"),JsonSerializer.Serialize(ids.ToDictionary(id=>id,NativeWorkerService.CapturePerformanceValues)));
                foreach(var id in ids){var result=Path.Combine(folder,"action.json");Check(await NativeWorkerService.ExecuteAsync("performance-on:"+id,result)==0,id+": apply verified");Check(new WindowsTuningService(new OperationLogService(new AppPaths())).IsPerformanceOptimizationEnabled(id),id+": new reader sees persisted state");}
                using(var key=Registry.CurrentUser.CreateSubKey(@"Control Panel\Keyboard")){key.SetValue("KeyboardDelay","1",RegistryValueKind.String);}
                var partial=NativeWorkerService.ReadPerformanceState("keyboard");Check(!partial.Applied&&partial.Matched==1&&partial.Total==2,"Keyboard partial state identified");
                Check(await NativeWorkerService.ExecuteAsync("performance-on:keyboard",Path.Combine(folder,"action.json"))==0,"Keyboard reapplied and persisted (interactive API deferred in service session)");
                NativeWorkerService.SaveStateDocument(Path.Combine(folder,"Before.txt"),"PASS\n"+checks.Count+" checks\n"+string.Join("\n",checks));
            }else{
                var original=JsonSerializer.Deserialize<System.Collections.Generic.Dictionary<string,string>>(File.ReadAllText(Path.Combine(folder,"original.json")));
                foreach(var id in ids){Check(NativeWorkerService.ReadPerformanceState(id).Applied,id+": preserved after VM reboot");Check(await NativeWorkerService.ExecuteAsync("performance-restore:"+id,Path.Combine(folder,"action.json"))==0,id+": restore succeeds");Check(NativeWorkerService.CapturePerformanceValues(id)==original[id],id+": exact original values restored");}
                NativeWorkerService.SaveStateDocument(Path.Combine(folder,"After.txt"),"PASS\n"+checks.Count+" checks\n"+string.Join("\n",checks));
            }
            Application.Current.Shutdown(0);
        }catch(Exception ex){NativeWorkerService.SaveStateDocument(Path.Combine(folder,"Failure.txt"),ex.ToString());Application.Current.Shutdown(1);}
    }
}
