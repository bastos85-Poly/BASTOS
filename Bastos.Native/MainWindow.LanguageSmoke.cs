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
using Bastos.Native.Models;
using Bastos.Native.Services;

namespace Bastos.Native;
public partial class MainWindow
{
    private async Task RunLanguageSmokeAsync()
    {
        var root = Environment.GetEnvironmentVariable("BASTOS_LANGUAGE_TEST_DATA")!;
        try
        {
            var vm = (MainViewModel)DataContext;
            if (Environment.GetCommandLineArgs().Contains("--expect-english") && InterfaceLanguage.Instance.Language != "en") throw new Exception("Saved language was not restored on startup");
            var keys = string.Join(",", vm.Navigation.Select(n => n.PageKey));
            var sourceTitles = string.Join("|",vm.Navigation.Select(n=>n.Title));
            if (vm.Navigation.Count != 12) throw new Exception("Navigation count changed");
            foreach (var code in new[] { "en", "fr", "en", "fr" })
            {
                InterfaceLanguageSelector.SelectedValue = code;
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                UpdateLayout();
                if (InterfaceLanguage.Instance.Language != code) throw new Exception("Selector binding failed");
                if (File.ReadAllText(InterfaceLanguage.PreferencePath) != code) throw new Exception("Persistence failed");
                if (string.Join(",", vm.Navigation.Select(n => n.PageKey)) != keys) throw new Exception("Action keys changed");
                if (string.Join("|",vm.Navigation.Select(n=>n.Title)) != sourceTitles) throw new Exception("Model strings were rewritten");
                var expected = code == "en" ? "Home" : "Accueil";
                if (!Descendants(this).OfType<TextBlock>().Any(t => t.Text == expected)) throw new Exception("Navigation translation failed: " + code + " / " + string.Join(" | ", Descendants(this).OfType<TextBlock>().Select(t => t.Text).Take(35)));
                var bitmap = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(this);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var stream = File.Create(Path.Combine(root, code + ".png")); encoder.Save(stream);
            }
            InterfaceLanguageSelector.SelectedValue = "en";
            var dynamicCases = new (string French,string English)[] {
                ("Modèle désactivé — prochaine session", "Template disabled — next session"),
                ("Refus de Windows — voir le détail", "Denied by Windows — see details"),
                ("Détectés : 112 · Démarrages désactivés : 102 · Indisponibles : 40 · Refus Windows : 8 · Conflits : 1 · Erreurs : 0.", "Detected: 112 · Startup settings disabled: 102 · Unavailable: 40 · Windows refusals: 8 · Conflicts: 1 · Errors: 0."),
                ("34 % — Etape 4/9 - Carte graphique\nLecture de tous les GPU et de leurs pilotes...", "34 % — Step 4/9 - Graphics cards\nReading all GPUs and their drivers..."),
                ("Analyse matérielle terminée: rapport et inventaire vérifiés.", "Hardware analysis completed: report and inventory verified."),
                ("Voir les téléchargements officiels", "View official downloads"),
                ("197 périphériques détectés · 7 liens officiels proposés · 0 problème(s).", "197 devices detected · 7 official links suggested · 0 issue(s)."),
                ("Realtek - derniers pilotes officiels", "Realtek - latest official drivers"),
                ("MSI Board - support officiel", "MSI Board - official support"),
                ("AMD B840 - pilote chipset officiel", "AMD B840 - official chipset driver"),
                ("Version installée : Information indisponible", "Installed version: Information unavailable"),
                ("Cette action est en cours. Attends sa fin.", "This action is running. Wait for it to finish."),
                ("Étape 2/4 — installation de Firefox en cours", "Step 2/4 — installing Firefox"),
                ("Bases de données — 3 optimisées, 4 Mo récupérés, 2 ignorées.", "Databases — 3 optimized, 4 MB recovered, 2 skipped."),
                ("Traces du Registre — 2 listes effacées, 1 ignorées.", "Registry traces — 2 lists cleared, 1 skipped."),
                (@"C:\Données\Réparation.txt", @"C:\Données\Réparation.txt")
            };
            foreach(var test in dynamicCases)
                if(InterfaceLanguage.Instance.Translate(test.French)!=test.English)throw new Exception("Dynamic translation regression: "+test.French+" => "+InterfaceLanguage.Instance.Translate(test.French));
            InterfaceLanguageSelector.SelectedValue="fr";
            foreach(var test in dynamicCases)if(InterfaceLanguage.Instance.Translate(test.French)!=test.French)throw new Exception("French source altered");
            InterfaceLanguageSelector.SelectedValue="en";
            if (!InterfaceLanguageSelector.IsEnabled || !InterfaceLanguageSelector.IsTabStop || !InterfaceLanguageSelector.Focus()) throw new Exception("Language selector is not keyboard accessible");
            var field = new TextBox { Text="Réparation" };
            var diagnostic = new TextBox { Text="Réparation", IsReadOnly=true };
            var live = new TextBlock(); live.SetBinding(TextBlock.TextProperty,new System.Windows.Data.Binding("Text"){Source=field});
            var sample = new Window { Content=new StackPanel {Children={field,diagnostic,live}},Width=300,Height=150,Owner=this };
            LocalizedPresentation.Watch(sample);sample.Show();sample.UpdateLayout();
            InterfaceLanguageSelector.SelectedValue="fr";InterfaceLanguageSelector.SelectedValue="en";
            if(field.Text!="Réparation"||diagnostic.Text!="Réparation")throw new Exception("User input or diagnostic was translated");
            if(live.Text!="Repair")throw new Exception("Bound display translation failed");
            field.Text="Journal";await Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
            if(live.Text!="Activity log"||field.Text!="Journal")throw new Exception("Live binding or source preservation failed");
            InterfaceLanguageSelector.SelectedValue="fr";
            if(live.Text!="Journal")throw new Exception("French restoration lost live binding value");
            InterfaceLanguageSelector.SelectedValue="en";
            sample.Close();
            CollectModelText(vm, new System.Collections.Generic.HashSet<object>(System.Collections.Generic.ReferenceEqualityComparer.Instance), 0);
            foreach(var nav in vm.Navigation)
            {
                vm.SelectedNavigation = nav;
                if(nav.PageKey=="hardware" && Environment.GetCommandLineArgs().Contains("--language-audit-hardware"))
                {
                    var method=typeof(MainViewModel).GetMethod("AnalyzeHardware",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!;
                    await (Task)method.Invoke(vm,new object[]{vm.CurrentPage,vm.CurrentPage.HardwareAnalysisCard!})!;
                    if(vm.CurrentPage.HardwareResults.Count<3)throw new Exception("Real hardware analysis did not produce driver results");
                    foreach(var card in vm.CurrentPage.HardwareResults)
                        foreach(var text in new[]{card.Title,card.State,card.HardwareRole,card.HardwareSource,card.HardwareDetails}) InterfaceLanguage.Instance.Translate(text);
                }
                if(nav.PageKey=="optimizations" && Environment.GetCommandLineArgs().Contains("--language-audit-hardware"))
                    await vm.NetworkOptimization.RefreshAsync();
                CollectModelText(vm.CurrentPage, new System.Collections.Generic.HashSet<object>(System.Collections.Generic.ReferenceEqualityComparer.Instance), 0);
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                for(int pass=0;pass<3;pass++)
                {
                    foreach(var expander in Descendants(this).OfType<Expander>().Where(e=>e.IsVisible).ToArray()) expander.IsExpanded=true;
                    await Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
                }
                UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(this);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var stream = File.Create(Path.Combine(root, "page-" + nav.PageKey + ".png")); encoder.Save(stream);
            }
            var iso = new WindowsIsoEditionCatalog("Windows.iso", new string('a',64), new[] { new WindowsIsoEdition(6,"Windows 11 Pro","Professional") { Languages = new[]{"en-US","fr-FR"} } });
            var options = new RufusInstallOptions();
            var review = new RecoveryPreflight("Windows.iso", "Windows 11 Pro", "BASTOS", "", new RecoveryDiskPreview(true,"","D:","","","") { RecoverySizeBytes=50L*1073741824, RecoveryFreeBytes=30L*1073741824 }, 6L*1073741824, Array.Empty<string>(), true);
            var logs = Path.Combine(root,"empty-logs"); Directory.CreateDirectory(logs);
            var windows = new Window[] {
                new IsoCustomizationWindow(vm.Reinstall), new RecoveryEditionWindow(iso.Images),
                new RecoveryPreflightWindow(review),
                new RufusInstallWindow(options,"Windows.iso","D: — BASTOS_RECOVERY","",()=>Task.FromResult(iso),vm.Reinstall.Languages,vm.Reinstall.Keyboards),
                new InstallationVerificationWindow(vm.Installation),
                new LogMaintenanceWindow(new LogMaintenanceViewModel(new LogMaintenanceService(logs))),
                new DiagnosticExportWindow(new DiagnosticExportViewModel(new DiagnosticExportService(logs,"test","Windows"),null)),
                new GameListWindow(new BastosGameService(new AppPaths(),new OperationLogService(new AppPaths())), false),
                new DisplayCalibrationWindow(0) { WindowState=WindowState.Normal, Width=1000, Height=700, Topmost=false },
                vm.CreateServiceProfileForTest()
            };
            foreach(var window in windows)
            {
                window.Owner=this; LocalizedPresentation.Watch(window); window.Show();
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                if(window is ServiceProfileWindow services){await services.AnalysisTask;if(!services.AnalysisReady)throw new Exception("Read-only service analysis failed");}
                foreach(var code in new[]{"en","fr","en"})
                {
                    InterfaceLanguageSelector.SelectedValue=code;
                    await Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
                    window.UpdateLayout();
                    var bitmap = new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(window);
                    var encoder = new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var stream=File.Create(Path.Combine(root,window.GetType().Name+"-"+code+".png"));encoder.Save(stream);
                }
                window.Close();
            }
            File.WriteAllLines(Path.Combine(root, "untranslated.txt"), InterfaceLanguage.Untranslated.OrderBy(x=>x));
            InterfaceLanguageSelector.SelectedValue = "fr";
            File.WriteAllText(Path.Combine(root, "result.txt"), "PASS: 12 pages and 10 secondary windows rendered; read-only service analysis; 12 navigation keys preserved; live FR/EN/FR; preference saved.");
            Application.Current.Shutdown(0);
        }
        catch (Exception ex) { File.WriteAllText(Path.Combine(root, "result.txt"), ex.ToString()); Application.Current.Shutdown(1); }
    }
    private static void CollectModelText(object? model, System.Collections.Generic.HashSet<object> seen, int depth)
    {
        if (model == null || depth > 5 || !seen.Add(model)) return;
        if (model is string text) { InterfaceLanguage.Instance.Translate(text); return; }
        if (model is System.Collections.IEnumerable items) { foreach (var item in items) CollectModelText(item, seen, depth + 1); return; }
        if (model.GetType().Namespace is not string ns || (!ns.Contains("ViewModels") && !ns.Contains("Models"))) return;
        foreach (var prop in model.GetType().GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance))
        {
            if (prop.GetIndexParameters().Length != 0 || prop.Name.EndsWith("Command")) continue;
            try { CollectModelText(prop.GetValue(model), seen, depth + 1); } catch { }
        }
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
