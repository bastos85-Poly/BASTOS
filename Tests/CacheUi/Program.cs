using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Bastos.Native;
using Bastos.Native.Models;
using Bastos.Native.Services;
public static class CachePreview{
 [STAThread]public static void Main(string[] args){
  var app=new App();app.InitializeComponent();
  const long gb=1073741824L;string id=Guid.NewGuid().ToString(),part=Guid.NewGuid().ToString(),hash=new('A',64),iso=@"D:\Windows-test.iso";
  var options=new RufusInstallOptions{EditionIsoPath=iso,EditionIsoSha256=hash,WindowsImageIndex=6,WindowsEditionId="Professional",WindowsImageName="Windows 11 Pro",WindowsUILanguage="fr-FR",DiskSafetySnapshot="fixture",WindowsDiskIdentity=id,RecoveryPartitionGuid=part};
  var catalog=new WindowsIsoEditionCatalog(iso,hash,new[]{new WindowsIsoEdition(6,"Windows 11 Pro","Professional"){Languages=new[]{"fr-FR"}}});
  foreach(string mode in new[]{"Reuse","Boot","Full"}){
   var disk=new RecoveryDiskPreview(true,"Simulation","D: — BASTOS_RECOVERY",part,id,"fixture"){RecoverySizeBytes=40*gb,RecoveryFreeBytes=3*gb,DiskDescription="Disque simulé — aucun changement",Partitions=new[]{new RecoveryPartitionPreview(5,part,"D:",40*gb,"CONSERVER")},CacheMode=mode,CacheIsoSha256=hash,CacheRequiredFreeBytes=mode=="Reuse"?2*gb:3*gb};
   var review=RecoveryPreflightBuilder.Build(iso,9*gb,options,disk,catalog,"",false);
   var window=new RecoveryPreflightWindow(review);window.Show();window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
   var launch=(Button)window.FindName("LaunchButton");var ack=(CheckBox)window.FindName("Acknowledgement");
   if(launch.IsEnabled)throw new Exception("Launch enabled before confirmation");
   ack.IsChecked=true;if(launch.IsEnabled!=(mode!="Full"))throw new Exception("Confirmation gate incorrect");
   ((ScrollViewer)window.FindName("ReviewScroll")).ScrollToEnd();window.UpdateLayout();
   var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
   var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var output=System.IO.File.Create(System.IO.Path.Combine(args[0],"Cache-"+mode+".png")))encoder.Save(output);
   window.Close();
  }
  app.Shutdown();Console.WriteLine("PASS : 3 cache UI states and confirmation gates; no action launched.");
 }
}
