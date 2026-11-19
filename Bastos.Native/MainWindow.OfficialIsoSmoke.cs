using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using Bastos.Native.ViewModels;

namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunOfficialIsoSmokeAsync()
    {
        string root=Environment.GetEnvironmentVariable("BASTOS_TEST_DATA")??"";
        if(!Environment.GetCommandLineArgs().Contains("--smoke-test") ||
            !Path.GetFullPath(root).StartsWith(Path.GetTempPath(),StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("An isolated smoke-test directory is required.");
        try
        {
            var main=(MainViewModel)DataContext;
            main.SelectedNavigation=main.Navigation.First(n=>n.PageKey=="reinstall");
            var vm=main.Reinstall;
            vm.SelectedCatalogFamily=vm.CatalogFamilies.First(i=>i.Value=="Windows 11");
            vm.SelectedCatalogLanguage=vm.CatalogLanguages.First(i=>i.Value=="French");
            vm.SelectedCatalogArchitecture=vm.CatalogArchitectures.First(i=>i.Value=="x64");
            await vm.DownloadCommand.ExecuteAsync();
            string? path=vm.SelectedIso?.Path;
            if(vm.IsBusy || path==null || !File.Exists(path) || new FileInfo(path).Length<1024*1024 || vm.DownloadProgressPercent<100)
                throw new InvalidOperationException("Official ISO was not downloaded and selected: "+vm.Status);
            File.WriteAllText(Path.Combine(root,"official-iso-result.json"),System.Text.Json.JsonSerializer.Serialize(new {Passed=true,Path=path,Bytes=new FileInfo(path).Length,vm.Status,vm.DownloadProgressPercent}));
            Application.Current.Shutdown(0);
        }
        catch(Exception error)
        {
            File.WriteAllText(Path.Combine(root,"official-iso-error.txt"),error.ToString());
            Application.Current.Shutdown(1);
        }
    }
}
