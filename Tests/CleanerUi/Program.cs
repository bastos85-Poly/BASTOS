using System.ComponentModel;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Windows.Markup;
using System.Xml.Linq;
using Microsoft.Win32;
using Bastos.Native;
using Bastos.Native.Services;
using Bastos.Native.ViewModels;

class CleanerUi
{
 [STAThread] static void Main(string[] args)
 {
  string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);
  string fixture=Path.Combine(Path.GetTempPath(),"Bastos-CleanerUI-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(fixture);
  Environment.SetEnvironmentVariable("BASTOS_TEST_DATA",Path.Combine(fixture,"Data"));
  SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());
  var app=new Application();
  var styles=XDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Styles.xml")).Replace("clr-namespace:Bastos.Native","clr-namespace:Bastos.Native;assembly=BASTOS-Native"));
  XNamespace presentation="http://schemas.microsoft.com/winfx/2006/xaml/presentation";
  var dictionary=styles.Descendants(presentation+"ResourceDictionary").First();
  dictionary.SetAttributeValue(XNamespace.Xmlns+"x","http://schemas.microsoft.com/winfx/2006/xaml");
  dictionary.SetAttributeValue(XNamespace.Xmlns+"native","clr-namespace:Bastos.Native;assembly=BASTOS-Native");
  app.Resources=(ResourceDictionary)XamlReader.Parse(dictionary.ToString());
  var window=new MainWindow();app.MainWindow=window;
  window.Loaded -= (RoutedEventHandler)Delegate.CreateDelegate(typeof(RoutedEventHandler),window,typeof(MainWindow).GetMethod("OnLoaded",BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.DeclaredOnly)!);
  var main=(MainViewModel)window.DataContext;int checks=0;
  void Check(bool valid,string label){if(!valid)throw new Exception(label);Console.WriteLine("PASS: "+label);checks++;}
  void Await(Task task){var clock=Stopwatch.StartNew();while(!task.IsCompleted){if(clock.Elapsed>TimeSpan.FromSeconds(45))throw new TimeoutException();Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.Background);Thread.Sleep(5);}task.GetAwaiter().GetResult();}
  void Pump(){Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.Background);}
  Check(main.Navigation.Count==12,"Douze destinations conservées");
  Check(!main.Navigation.Any(n=>n.PageKey=="remote"||n.Title.Contains("Assistance")),"Assistance distante retirée");
  main.SelectedNavigation=main.Navigation.Single(n=>n.PageKey=="cleaner");
  Check(main.CurrentPage.IsCleaner&&!main.CurrentPage.IsStandardPage,"Navigation Nettoyeur dédiée");
  Check(!main.Cleaner.CleanCommand.CanExecute(null),"Nettoyage bloqué avant analyse");
  var ruleType=typeof(SystemCleanerService).GetNestedType("Rule",BindingFlags.NonPublic)!;
  string cache=Path.Combine(fixture,"cache");Directory.CreateDirectory(cache);
  string file=Path.Combine(cache,"cache-demo.tmp"), keep=Path.Combine(cache,"a-conserver.tmp");
  File.WriteAllText(file,"fixture-cache");File.WriteAllText(keep,"fixture-important");
  File.SetLastWriteTimeUtc(file,DateTime.UtcNow.AddDays(-5));File.SetLastWriteTimeUtc(keep,DateTime.UtcNow.AddDays(-5));
  var rules=Array.CreateInstance(ruleType,1);rules.SetValue(Activator.CreateInstance(ruleType,"temp",cache,"*",true,0),0);
  var service=(SystemCleanerService)Activator.CreateInstance(typeof(SystemCleanerService),BindingFlags.Instance|BindingFlags.NonPublic,null,new object?[]{rules,null,100000},null)!;
  var paths=(AppPaths)Activator.CreateInstance(typeof(AppPaths),BindingFlags.Instance|BindingFlags.NonPublic,null,new object?[]{"D:\\Application",Path.Combine(fixture,"Data")},null)!;
  bool approve=false;int confirmations=0;
  var vm=new CleanerViewModel(paths,service,text=>{confirmations++;return approve;});
  Check(vm.AgeDays==0,"Protection Kudu d’une heure appliquée par défaut");
  Await(vm.ScanAsync());
  Check(vm.HasScan&&vm.Files.Count==2&&File.Exists(file),"Analyse UI en lecture seule avec résultats");
  Check(vm.ResultGroups.Count==1&&vm.ResultGroups[0].CountText.Contains("2"),"Résultats regroupés avec compte et taille");
  vm.ResultGroups[0].Selected=false;Check(!vm.CleanCommand.CanExecute(null),"Décocher un groupe retire tous ses fichiers de la sélection");
  vm.ResultGroups[0].Selected=true;
  Check(vm.CleanCommand.CanExecute(null),"Nettoyage disponible après analyse");
  Await(vm.CleanAsync());Check(confirmations==1&&File.Exists(file)&&vm.Files.Count==2,"Refus du bilan préserve les fichiers");
  vm.Files.Single(f=>f.PathText==keep).Selected=false;
  Check(vm.SelectionText.StartsWith("1 fichiers"),"Sélection individuelle actualise le total");
  approve=true;Await(vm.CleanAsync());
  Console.WriteLine("Fixture cleanup: "+vm.Status+" "+vm.Detail);
  Check(!File.Exists(file)&&File.Exists(keep)&&vm.Files.Count==1,"Suppression de la sélection uniquement depuis UI");
  Check(!vm.CleanCommand.CanExecute(null),"Nouvelle analyse exigée après nettoyage");
  var reports=new OperationHistoryService(paths.LogRoot).Read();
  Check(reports.Entries.Count==1&&reports.Entries[0].RecordedStatus=="Réussie","Résultat enregistré et lisible dans Journal");
  vm.ExclusionInput=keep;vm.AddExclusionCommand.Execute(null);
  Await(vm.ScanAsync());Check(vm.Files.Count==0&&File.Exists(keep),"Exclusion appliquée à une nouvelle analyse");
  var reloaded=new CleanerViewModel(paths,service,_=>false);Check(reloaded.Exclusions.Contains(keep),"Exclusions conservées à la réouverture");
  string settingsPath=Path.Combine(paths.StateRoot,"Cleaner.json");
  string settings=File.ReadAllText(settingsPath);
  File.WriteAllText(settingsPath,settings.Replace("\"AgeDays\":0","\"AgeDays\":1").Replace("\"SchemaVersion\":3","\"SchemaVersion\":0"));
  var migrated=new CleanerViewModel(paths,service,_=>false);
  Check(migrated.AgeDays==0&&migrated.Exclusions.Contains(keep),"Ancien défaut de 24 heures migré sans perdre les exclusions");
  migrated.AgeDays=2;
  var customAge=new CleanerViewModel(paths,service,_=>false);
  Check(customAge.AgeDays==2,"Âge personnalisé conservé après migration");
  vm.ExclusionInput="chemin-relatif";vm.AddExclusionCommand.Execute(null);Check(!vm.Exclusions.Contains("chemin-relatif"),"Chemin relatif rejeté");
  var page=new CleanerPage{DataContext=main.Cleaner};
  void Render(string name,int width,int height){var surface=new Border{Background=(Brush)app.FindResource("WindowBrush"),Padding=new Thickness(20),Child=page};surface.Measure(new Size(width,height));surface.Arrange(new Rect(0,0,width,height));surface.UpdateLayout();Pump();var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);bitmap.Render(surface);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(Path.Combine(output,name+".png")))png.Save(stream);surface.Child=null;}
  Render("nettoyeur-initial",1100,720);
  string previewFile=Path.Combine(cache,"preview.tmp");File.WriteAllText(previewFile,"cache-preview");File.SetLastWriteTimeUtc(previewFile,DateTime.UtcNow.AddDays(-5));
  var previewVm=new CleanerViewModel(paths,service,_=>false);Await(previewVm.ScanAsync());page.DataContext=previewVm;Render("nettoyeur-resultats-reels",1100,720);page.DataContext=main.Cleaner;previewVm.Dispose();
  Expander? FindExpander(DependencyObject root,string header){if(root is Expander e&&Equals(e.Header,header))return e;for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++){var found=FindExpander(VisualTreeHelper.GetChild(root,i),header);if(found!=null)return found;}return null;}
  var perimeter=FindExpander(page,"Périmètre de l’analyse");Check(perimeter!=null,"Options d’analyse accessibles dans un panneau dédié");perimeter!.IsExpanded=true;Render("nettoyeur-options",1100,1400);Pump();
  Expander? FindSuboption(DependencyObject root){if(root is Expander e&&Equals(e.Header,"Sous-options"))return e;for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++){var found=FindSuboption(VisualTreeHelper.GetChild(root,i));if(found!=null)return found;}return null;}
  var firstSuboption=FindSuboption(page);Check(firstSuboption!=null,"Panneau de sous-options système visible");firstSuboption!.IsExpanded=true;Render("nettoyeur-systeme-options",1100,720);
  foreach(var category in main.Cleaner.Categories)category.Summary="24 fichiers · 12,4 Mo";
  for(int i=0;i<20;i++)main.Cleaner.Files.Add(new CleanerFileItem(new CleanerFile("demo-"+i,"temp",Path.Combine(cache,"fichier-demonstration-"+i+".tmp"),cache,123456,DateTime.UtcNow.AddDays(-5)),"Fichiers temporaires"));
  typeof(CleanerViewModel).GetProperty("HasScan")!.SetValue(main.Cleaner,true);
  Render("nettoyeur-resultats",1100,720);Render("nettoyeur-compact",850,650);
  Check(main.Cleaner.Groups.SequenceEqual(new[]{"Système","Navigateurs","Applications","Outils d’IA","Jeux","Corbeille","Raccourcis","Environnement","Bases de données","Traces de confidentialité"}),"Dix rubriques Kudu présentes");
  foreach(string section in main.Cleaner.Groups){main.Cleaner.Group=section;Check(main.Cleaner.Group==section,"Rubrique "+section+" accessible");}
  main.Cleaner.Group="Corbeille";Check(main.Cleaner.SelectedMaintenance?.Action.Id=="recycle-bin","Corbeille reliée à la maintenance Windows");Render("nettoyeur-corbeille",1100,720);
  main.Cleaner.Group="Environnement";Check(main.Cleaner.IsAdvancedSection&&main.Cleaner.ScanAdvancedCommand.CanExecute(null),"Analyse Environnement disponible");Render("nettoyeur-environnement",1100,720);
  main.Cleaner.Group="Bases de données";Check(main.Cleaner.IsAdvancedSection&&main.Cleaner.ScanAdvancedCommand.CanExecute(null),"Analyse Bases de données disponible");Render("nettoyeur-bases",1100,720);
  main.Cleaner.Group="Traces de confidentialité";Check(main.Cleaner.IsPrivacy&&main.Cleaner.ScanPrivacyRegistryCommand.CanExecute(null)&&!main.Cleaner.CleanPrivacyRegistryCommand.CanExecute(null),"Listes privées disponibles sans effacement automatique");Render("nettoyeur-confidentialite",1100,720);
  main.Cleaner.Group="Système";
  var systemOptions=main.Cleaner.Categories.Single(c=>c.Id=="temp").Options;
  Check(systemOptions.Count>=3,"Sous-options système détaillées et sélectionnables");
  Console.WriteLine("Sous-options système: "+main.Cleaner.Categories.Where(c=>c.Group=="Système").Sum(c=>c.Options.Count));
  systemOptions[0].Selected=!systemOptions[0].Selected;
  Check(!main.Cleaner.HasScan,"Changer une sous-option invalide l’ancien aperçu");
  string privacyRoot=Path.Combine(fixture,"privacy");Directory.CreateDirectory(privacyRoot);string trace=Path.Combine(privacyRoot,"recent.lnk");File.WriteAllText(trace,"fixture-trace");File.SetLastWriteTimeUtc(trace,DateTime.UtcNow.AddDays(-3));
  var privacyRules=Array.CreateInstance(ruleType,1);privacyRules.SetValue(Activator.CreateInstance(ruleType,"privacy-files",privacyRoot,"*.lnk",false,0),0);
  var privacyService=(SystemCleanerService)Activator.CreateInstance(typeof(SystemCleanerService),BindingFlags.Instance|BindingFlags.NonPublic,null,new object?[]{privacyRules,null,100000},null)!;
  var privacyVm=new CleanerViewModel(paths,privacyService,_=>false);privacyVm.Categories.Single(c=>c.Id=="privacy-files").Selected=true;
  Await(privacyVm.ScanAsync());Check(privacyVm.Files.Count==1&&!privacyVm.Files[0].Selected&&File.Exists(trace),"Traces privées détectées sans présélection");privacyVm.Dispose();
  Check(page.FindName("ScanButton") is Button scanButton&&scanButton.IsTabStop,"Action analyse accessible au clavier");
  Check(page.FindName("CleanButton") is Button cleanButton&&!cleanButton.IsEnabled,"État désactivé rendu sans aperçu valide");
  string integratedRegistry=@"Software\BastosCleanerFixture\"+Guid.NewGuid().ToString("N");
  string privacyRegistryPath=@"Software\BastosCleanerFixture\"+Guid.NewGuid().ToString("N");
  try
  {
   using(var key=Registry.CurrentUser.CreateSubKey(integratedRegistry)!){key.SetValue("JAVA_HOME",Path.Combine(fixture,"missing-sdk"));}
   using(var key=Registry.CurrentUser.CreateSubKey(privacyRegistryPath)!){key.SetValue("a","fixture-run");key.SetValue("MRUList","a");}
   string integratedDatabase=Path.Combine(fixture,"integrated-db");Directory.CreateDirectory(integratedDatabase);
   byte[] sqlite=new byte[65536];System.Text.Encoding.ASCII.GetBytes("SQLite format 3\0").CopyTo(sqlite,0);
   string sqlitePath=Path.Combine(integratedDatabase,"sample.db");File.WriteAllBytes(sqlitePath,sqlite);File.SetLastWriteTimeUtc(sqlitePath,DateTime.UtcNow.AddHours(-2));
   T FixtureService<T>(string value) where T:class => (T)Activator.CreateInstance(typeof(T),BindingFlags.Instance|BindingFlags.NonPublic,null,new object[]{value},null)!;
   var integratedPaths=(AppPaths)Activator.CreateInstance(typeof(AppPaths),BindingFlags.Instance|BindingFlags.NonPublic,null,new object?[]{"D:\\Application",Path.Combine(fixture,"IntegratedData")},null)!;
   var integratedVm=new CleanerViewModel(integratedPaths,service,_=>false,FixtureService<EnvironmentCleanerService>(integratedRegistry),FixtureService<DatabaseCleanerService>(integratedDatabase),FixtureService<PrivacyRegistryCleanerService>(privacyRegistryPath),true);
   Await(integratedVm.ScanAllAsync());
   Check(integratedVm.HasScan&&integratedVm.AdvancedItems.Any(i=>i.Section=="Environnement")&&integratedVm.AdvancedItems.Any(i=>i.Section=="Bases de données")&&integratedVm.PrivacyRegistryItems.Count==1,"Analyser couvre fichiers, environnement, SQLite et traces du Registre");
   integratedVm.Group="Environnement";Check(integratedVm.AdvancedView.Cast<AdvancedCleanerItem>().All(i=>i.Section=="Environnement"),"Rubrique Environnement conserve ses résultats après analyse globale");
   integratedVm.Group="Bases de données";Check(integratedVm.AdvancedView.Cast<AdvancedCleanerItem>().All(i=>i.Section=="Bases de données"),"Rubrique Bases de données conserve ses résultats après navigation");
   integratedVm.Group="Traces de confidentialité";Check(integratedVm.PrivacyRegistryItems.Count==1&&!integratedVm.PrivacyRegistryItems[0].Selected,"Traces privées visibles mais non présélectionnées");
   integratedVm.Dispose();
  }
  finally {Registry.CurrentUser.DeleteSubKeyTree(integratedRegistry,false);Registry.CurrentUser.DeleteSubKeyTree(privacyRegistryPath,false);}
  foreach(var item in main.Navigation){main.SelectedNavigation=item;Check(main.CurrentPage!=null,"Navigation "+item.Title);}
  main.Dispose();vm.Dispose();reloaded.Dispose();
  Console.WriteLine($"PASS {checks} contrôles UI et intégration, suppression exclusivement dans fixture: {fixture}");
 }
}


