using System.Windows;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class InstallationVerificationWindow : Window
{
    public InstallationVerificationWindow(InstallationVerificationViewModel model) { InitializeComponent(); LocalizedPresentation.Watch(this); DataContext = model; }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
