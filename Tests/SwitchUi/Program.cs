using System.Reflection;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bastos.Native;
using Bastos.Native.Models;
using Bastos.Native.ViewModels;

class SwitchUi {
 [STAThread] static void Main(string[] args) {
  string output=args[0];Directory.CreateDirectory(output);
  Environment.SetEnvironmentVariable("BASTOS_TEST_DATA",Path.Combine(Path.GetTempPath(),"Bastos-SwitchUI-"+Guid.NewGuid().ToString("N")));
  var app=new App();app.InitializeComponent();var window=new MainWindow();var vm=(MainViewModel)window.DataContext;
  int checks=0;
  void Check(bool valid,string description){if(!valid)throw new Exception(description);checks++;Console.WriteLine("OK: "+description);}
  IEnumerable<T> Find<T>(DependencyObject node) where T:DependencyObject {
   if(node is T found)yield return found;
   for(int i=0;i<VisualTreeHelper.GetChildrenCount(node);i++)foreach(var match in Find<T>(VisualTreeHelper.GetChild(node,i)))yield return match;
  }
  var ids=new[]{"audio-game","audio-power","udp-fastpath","mouse-queue","frame-timers","steam-gpu","sdl3"};
  var cards=vm.SoundOptimizationCards.Concat(vm.CompetitiveNetworkCards).Concat(vm.CompetitiveGameCards).ToArray();
  string fixture=Path.Combine(output,"states.json");
  void ReadStates(bool applied,int pending,bool success=true){
   File.WriteAllText(fixture,JsonSerializer.Serialize(new{Results=ids.Select(id=>new{Id=id,Success=success,Applied=applied,Pending=pending,Message="Données de test — aucun réglage modifié",Details=Array.Empty<string>()})}));
   ((Task)typeof(MainViewModel).GetMethod("ReadCompetitiveResultAsync",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(vm,new object[]{fixture,false})).GetAwaiter().GetResult();
  }
  ReadStates(false,0);Check(cards.All(c=>c.IsToggleCard&&c.ToggleState==false),"all seven competitive settings read as off without a backup");
  ReadStates(true,1);Check(cards.All(c=>c.ToggleState==true),"all seven competitive settings read as on");
  ReadStates(false,1);Check(cards.All(c=>c.ToggleState==true&&c.IsPartiallyApplied),"partly applied settings keep restore available");
  ReadStates(false,0,false);Check(cards.All(c=>c.ToggleState==null),"unreadable states do not retain stale switch positions");
  ReadStates(true,1);
  foreach(int width in new[]{680,1000}){
   var stack=new StackPanel{Margin=new Thickness(20)};
   stack.Children.Add(new TextBlock{Text="Optimisations · interrupteurs à droite",FontSize=22,Margin=new Thickness(0,0,0,16)});
   foreach(var card in cards){
    var view=(FrameworkElement)((DataTemplate)window.FindResource("CompetitiveCard")).LoadContent();view.DataContext=card;stack.Children.Add(view);
   }
   var canvas=new Border{Background=(Brush)app.FindResource("WindowBrush"),Child=stack};
   canvas.Measure(new Size(width,double.PositiveInfinity));canvas.Arrange(new Rect(0,0,width,stack.DesiredSize.Height+40));canvas.UpdateLayout();
   foreach(var view in stack.Children.OfType<Border>()){
    var control=Find<ConfirmedToggleButton>(view).Single();
    var right=control.TransformToAncestor(view).Transform(new Point(control.ActualWidth,0)).X;
    Check(Math.Abs(right-(view.ActualWidth-view.Padding.Right-view.BorderThickness.Right))<2,"switch aligned to card right edge at width "+width);
    var center=control.TransformToAncestor(view).Transform(new Point(0,control.ActualHeight/2)).Y;
    Check(Math.Abs(center-view.ActualHeight/2)<2,"switch vertically centered at width "+width);
    Check(view.ActualHeight<130,"compact single-line fixture card has no bottom action row");
    Check(!Find<Button>(view).Any(button=>button.IsVisible&&(ReferenceEquals(button.Command,((StatusCard)view.DataContext).PrimaryCommand)||ReferenceEquals(button.Command,((StatusCard)view.DataContext).SecondaryCommand))),"original paired buttons hidden");
   }
   var image=new RenderTargetBitmap(width,(int)Math.Ceiling(canvas.ActualHeight),96,96,PixelFormats.Pbgra32);image.Render(canvas);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using var file=File.Create(Path.Combine(output,"competitive-"+width+".png"));png.Save(file);
  }
  vm.Extras.SelectedApp=new ExtraItem{Installed=true,Applied=false,Name="Test",Id="chrome"};
  vm.Extras.SelectedUsb=new ExtraItem{Current=1,Id="usb"};vm.Extras.SelectedAdapter=new ExtraItem{Current=1500,Id="net"};vm.Extras.SelectedPower=new ExtraItem{Id="power",Ac=5,Dc=5};
  foreach(FrameworkElement page in new FrameworkElement[]{new ExtraAppsPage(),new ExtraUsbPage(),new ExtraMtuPage(),new ExtraPowerPage()}){
   page.DataContext=vm.Extras;page.Measure(new Size(900,double.PositiveInfinity));page.Arrange(new Rect(0,0,900,page.DesiredSize.Height));page.UpdateLayout();
   Check(Find<ConfirmedToggleButton>(page).Count()==1,page.GetType().Name+" has one shared switch");
   var toggle=Find<ConfirmedToggleButton>(page).Single();
   var border=Find<Border>(page).First(b=>b.Padding.Right==16);
   var right=toggle.TransformToAncestor(border).Transform(new Point(toggle.ActualWidth,0)).X;
   Check(Math.Abs(right-(border.ActualWidth-border.Padding.Right-border.BorderThickness.Right))<2,page.GetType().Name+" switch aligned to card right edge");
   var center=toggle.TransformToAncestor(border).Transform(new Point(0,toggle.ActualHeight/2)).Y;
   Check(Math.Abs(center-border.ActualHeight/2)<2,page.GetType().Name+" switch vertically centered");
   Check(!Find<Button>(page).Any(b=>(b.Content as string)?.StartsWith("Restaurer")==true),page.GetType().Name+" no remaining restore button");
  }
  var appearance=new AppearanceProfilesPage{DataContext=vm.Extras};
  appearance.Measure(new Size(900,double.PositiveInfinity));appearance.Arrange(new Rect(0,0,900,appearance.DesiredSize.Height));appearance.UpdateLayout();
  var choices=Find<CheckBox>(appearance).ToArray();
  Check(choices.Length==8,"appearance exposes eight independently selectable settings");
  Check(choices.All(c=>c.DataContext is AppearanceOption),"each appearance choice retains its own option and state");
  foreach(var command in new System.Windows.Input.ICommand[]{vm.Extras.ApplyProfileCommand,vm.Extras.RestoreProfileCommand,vm.Extras.RefreshProfilesCommand})
   Check(Find<Button>(appearance).Count(b=>ReferenceEquals(b.Command,command))==1,"appearance batch and refresh commands remain accessible");
  var first=choices[0];var option=(AppearanceOption)first.DataContext;var selected=option.Selected;first.IsChecked=!selected;
  Check(option.Selected==!selected,"appearance checkbox updates its selection without executing a system action");first.IsChecked=selected;
  var cursor=new CursorPackPage{DataContext=vm.CursorPack};
  cursor.Measure(new Size(900,double.PositiveInfinity));cursor.Arrange(new Rect(0,0,900,cursor.DesiredSize.Height));cursor.UpdateLayout();
  Check(Find<ConfirmedToggleButton>(cursor).Count()==1,"cursor pack uses the same switch");
  var cursorToggle=Find<ConfirmedToggleButton>(cursor).Single();var cursorBorder=Find<Border>(cursor).First(b=>b.Padding.Right==16);
  Check(Math.Abs(cursorToggle.TransformToAncestor(cursorBorder).Transform(new Point(0,cursorToggle.ActualHeight/2)).Y-cursorBorder.ActualHeight/2)<2,"cursor pack switch vertically centered");
  foreach(var input in vm.PersonalizationGroups.Concat(vm.AdvancedSettingsGroups).SelectMany(g=>g.Cards).Concat(cards))
   if(input.PrimaryText is "Activer" or "Appliquer" && input.SecondaryText.StartsWith("Restaurer"))Check(input.IsToggleCard,"reversible card covered: "+input.Title);
  vm.Dispose();Console.WriteLine($"PASS: {checks} WPF switch and layout checks, no system modification.");
 }
}
