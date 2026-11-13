using System.Windows.Controls;
namespace Bastos.Native;
public partial class CursorPackPage:UserControl{
 public CursorPackPage(){InitializeComponent();}
 private void OpenAuthor(object sender,System.Windows.Navigation.RequestNavigateEventArgs e){try{System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri.AbsoluteUri){UseShellExecute=true});}catch{}e.Handled=true;}
}
