using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Bastos.Native;
using Bastos.Native.Models;
public static class QolPreview
{
    [STAThread] public static void Main(string[] args)
    {
        var app=new App(); app.InitializeComponent();
        var window=new RufusInstallWindow(new RufusInstallOptions(), "Windows-test.iso", "D: — BASTOS_RECOVERY", "Aperçu uniquement ; aucune partition modifiée.",
            ()=>Task.FromResult(new WindowsIsoEditionCatalog("Windows-test.iso",new string('A',64),new[]{new WindowsIsoEdition(1,"Windows 11 Pro","Professional"){Languages=new[]{"fr-FR"},DefaultUILanguage="fr-FR"}})),
            new[]{new LanguageChoice("Français","French","fr-FR")},new[]{new KeyboardChoice("AZERTY","040C:0000040C")});
        window.Show();
        window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        var options=(RufusInstallOptions)window.DataContext;
        var drivers=(CheckBox)window.FindName("PreserveDriversCheckBox");
        if(!drivers.IsEnabled || drivers.IsChecked!=true)throw new Exception("Conservation pilotes non disponible par defaut");
        drivers.IsChecked=false;if(options.PreserveDrivers)throw new Exception("Choix pilotes non lie au modele");drivers.IsChecked=true;
        var extras=(StackPanel)window.FindName("ExtraCleanupPanel");
        if(!options.UseExactRufusExperience || extras.IsEnabled)throw new Exception("Mode conforme non actif par defaut");
        options.UseExactRufusExperience=false;
        window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        if(!extras.IsEnabled)throw new Exception("Options supplementaires inaccessibles hors mode conforme");
        options.UseExactRufusExperience=true;
        window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        if(extras.IsEnabled)throw new Exception("Options supplementaires non bloquees en mode conforme");
        var clean=(CheckBox)window.FindName("CleanBastosCheckBox");
        if(clean.IsChecked==true)throw new Exception("Profil propre doit etre facultatif");
        clean.IsChecked=true;
        window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        if(!options.UseCleanBastosInstallation || options.UseExactRufusExperience || extras.IsEnabled)throw new Exception("Profils propre et Rufus non exclusifs");
        if(!options.DisableTelemetry || !options.DisableConsumerContent || !options.RemoveOneDrive || !options.DisableCopilot)throw new Exception("Reglages du profil propre non selectionnes");
        var scroll=Find<ScrollViewer>(window) ?? throw new Exception("Scroll absent");
        scroll.ScrollToVerticalOffset(590); window.UpdateLayout();
        window.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(window);
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using(var file=System.IO.File.Create(args[0]))encoder.Save(file);
        window.Close(); app.Shutdown();Console.WriteLine("PASS : aperçu QoL généré sans enregistrer de profil.");
    }
    static T? Find<T>(DependencyObject node) where T:DependencyObject
    {if(node is T match)return match;for(int i=0;i<VisualTreeHelper.GetChildrenCount(node);i++){var result=Find<T>(VisualTreeHelper.GetChild(node,i));if(result!=null)return result;}return null;}
}
