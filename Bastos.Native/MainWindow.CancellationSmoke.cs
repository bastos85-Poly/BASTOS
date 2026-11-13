using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunCancellationSmokeAsync(MainViewModel main)
    {
        main.SelectedNavigation=main.Navigation.First(n=>n.PageKey=="reinstall");
        var vm=main.Reinstall;
        var begin=typeof(ReinstallViewModel).GetMethod("BeginCancellation",BindingFlags.NonPublic|BindingFlags.Instance)!;
        var end=typeof(ReinstallViewModel).GetMethod("EndCancellation",BindingFlags.NonPublic|BindingFlags.Instance)!;
        var control=(OperationCancellation)begin.Invoke(vm,null)!;
        async Task Flush(){await Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);UpdateLayout();}
        void Capture(string state){var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);
            var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(Path.Combine(Path.GetTempPath(),"BASTOS-Cancellation-"+state+".png"));png.Save(file);}
        try
        {
            control.AllowRead();await Flush();
            Capture("Measured");
            if(CancellationHintText.ActualWidth<200||string.IsNullOrWhiteSpace(CancellationHintText.Text))throw new InvalidOperationException($"Explication annulation illisible : {CancellationHintText.ActualWidth}, texte={CancellationHintText.Text}, contexte={CancellationHintText.DataContext?.GetType().Name}.");
            if(!vm.CanCancelOperation||!vm.IsCancellationVisible||!vm.CancelOperationCommand.CanExecute(null))throw new InvalidOperationException("Bouton annulation absent de la phase reversible.");
            if(!CancellationRequestButton.IsEnabled||!ReferenceEquals(CancellationRequestButton.Command,vm.CancelOperationCommand))throw new InvalidOperationException("Bouton WPF non lie a la commande.");
            Capture("Allowed");vm.CancelOperationCommand.Execute(null);await Flush();
            if(!control.Requested||vm.CanCancelOperation||!vm.CancellationHint.Contains("Attends"))throw new InvalidOperationException("Demande non suivie ou bouton encore actif.");
            Capture("Requested");control.Lock("Écritures Recovery en cours : laisse cette phase se terminer.");await Flush();
            if(vm.CancelOperationCommand.CanExecute(null)||!vm.CancellationHint.Contains("Recovery"))throw new InvalidOperationException("Phase ecriture non verrouillee.");
            if(CancellationRequestButton.IsEnabled)throw new InvalidOperationException("Bouton WPF encore actif pendant les ecritures.");
            Capture("Locked");
        }
        finally{end.Invoke(vm,new object[]{control});}
        await Flush();
        File.WriteAllText(Path.Combine(Path.GetTempPath(),"BASTOS-Cancellation-SmokeTest.txt"),"OK : etats WPF reel autorise, demande envoyee, ecritures verrouillees et fin ; aucun worker ni aucune ecriture disque systeme executes.");
    }
}
