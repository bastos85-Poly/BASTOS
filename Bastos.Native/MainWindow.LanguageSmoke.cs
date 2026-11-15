using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Bastos.Native.ViewModels;

namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunLanguageSmokeAsync()
    {
        var root = Environment.GetEnvironmentVariable("BASTOS_LANGUAGE_TEST_DATA")!;
        try
        {
            var vm = (MainViewModel)DataContext;
            var keys = string.Join(",", vm.Navigation.Select(n => n.PageKey));
            if (vm.Navigation.Count != 12) throw new Exception("Navigation count changed");
            foreach (var code in new[] { "en", "fr", "en", "fr" })
            {
                InterfaceLanguageSelector.SelectedValue = code;
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                UpdateLayout();
                if (InterfaceLanguage.Instance.Language != code) throw new Exception("Selector binding failed");
                if (File.ReadAllText(InterfaceLanguage.PreferencePath) != code) throw new Exception("Persistence failed");
                if (string.Join(",", vm.Navigation.Select(n => n.PageKey)) != keys) throw new Exception("Action keys changed");
                var expected = code == "en" ? "Home" : "Accueil";
                if (!Descendants(this).OfType<TextBlock>().Any(t => t.Text == expected)) throw new Exception("Navigation translation failed");
                var bitmap = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(this);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var stream = File.Create(Path.Combine(root, code + ".png")); encoder.Save(stream);
            }
            File.WriteAllText(Path.Combine(root, "result.txt"), "PASS: 12 navigation keys preserved; live FR/EN/FR; preference saved; screenshots rendered.");
            Application.Current.Shutdown(0);
        }
        catch (Exception ex) { File.WriteAllText(Path.Combine(root, "result.txt"), ex.ToString()); Application.Current.Shutdown(1); }
    }
    private static System.Collections.Generic.IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i); yield return child;
            foreach (var nested in Descendants(child)) yield return nested;
        }
    }
}
