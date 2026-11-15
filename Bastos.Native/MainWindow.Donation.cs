using System;
using System.Diagnostics;
using System.Windows;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Bastos.Native;
public partial class MainWindow
{
    // Opens only the configured donation page; no payment is initiated by Bastos.
    private const string KoFiPage = "https://ko-fi.com/bastos85";
    private Action<Uri> launchDonationPage = page => Process.Start(new ProcessStartInfo(page.AbsoluteUri){UseShellExecute=true});

    private void OpenKoFiDonation(object sender, RoutedEventArgs e)
    {
        if(!Uri.TryCreate(KoFiPage,UriKind.Absolute,out var page) || page.Scheme!="https" ||
           (page.Host!="ko-fi.com" && page.Host!="www.ko-fi.com") || !page.IsDefaultPort ||
           page.UserInfo.Length>0 || page.AbsolutePath=="/")return;
        try{launchDonationPage(page);}
        catch(Exception){Bastos.Native.LocalizedMessageBox.Show(this,"La page Ko-fi ne peut pas être ouverte pour le moment.","Soutenir Bastos",MessageBoxButton.OK,MessageBoxImage.Information);}
    }

    private async Task RunDonationSmokeAsync()
    {
        string folder=Path.Combine(Path.GetTempPath(),"BASTOS-Donation");Directory.CreateDirectory(folder);
        int count=0;
        void Check(bool value,string text){if(!value)throw new Exception(text);count++;}
        try
        {
            await Task.Delay(200);
            Check(KoFiDonationButton.IsVisible && KoFiDonationButton.IsEnabled,"Cœur disponible");
            Check(KoFiDonationButton.Focusable && KoFiDonationButton.IsTabStop,"Accessible au clavier");
            FocusManager.SetFocusedElement(this,KoFiDonationButton);
            Check(FocusManager.GetFocusedElement(this)==KoFiDonationButton,"Focus logique sur le cœur");
            Check(AutomationProperties.GetName(KoFiDonationButton).Contains("don"),"Nom accessible explicite");
            Check(KoFiDonationButton.ToolTip.ToString()!.Contains("Ko-fi"),"Infobulle Ko-fi");
            Uri? launched=null;int launches=0;
            launchDonationPage=page=>{launched=page;launches++;};
            KoFiDonationButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(launches==1 && launched?.AbsoluteUri==KoFiPage,"Un clic ouvre la bonne page, une seule fois");
            Check(launched!.Scheme=="https" && launched.Host=="ko-fi.com","Destination HTTPS Ko-fi");
            UpdateLayout();
            var point=KoFiDonationButton.TranslatePoint(new Point(0,0),this);
            Check(point.X>ActualWidth-100 && point.Y<80,"Cœur dans le coin supérieur droit");
            var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(this);
            var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(folder,"Bastos-Kofi.png")))png.Save(stream);
            File.WriteAllText(Path.Combine(folder,"Result.txt"),$"PASS : {count} contrôles du cœur Ko-fi. Clic relié à {KoFiPage}, lancement du navigateur simulé ; aucun don ni réglage système exécuté.");
            Application.Current.Shutdown(0);
        }
        catch(Exception ex){File.WriteAllText(Path.Combine(folder,"Result.txt"),"FAIL\n"+ex);Application.Current.Shutdown(1);}
    }
}
