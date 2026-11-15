using System.Windows;
using Bastos.Native.ViewModels;
namespace Bastos.Native;
public partial class LogMaintenanceWindow : Window
{
    private readonly LogMaintenanceViewModel model;
    public LogMaintenanceWindow(LogMaintenanceViewModel model)
    {
        InitializeComponent(); LocalizedPresentation.Watch(this); DataContext = this.model = model; MaxHeight = SystemParameters.WorkArea.Height; MaxWidth = SystemParameters.WorkArea.Width;
        Loaded += async (_, _) => await model.AnalyzeAsync();
        Closing += (_, e) => { if (model.IsBusy) e.Cancel = true; };
    }
    private async void Clean_Click(object sender, RoutedEventArgs e)
    {
        if (!model.CanClean) return;
        if (Bastos.Native.LocalizedMessageBox.Show(this, "Supprimer définitivement les éléments cochés ?\n\n" + model.SelectionSummary + "\n\nLes fichiers seront revérifiés ; ceux qui ont changé ou sont utilisés seront conservés.", "Confirmer le nettoyage local", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) == MessageBoxResult.Yes)
            await model.CleanAsync();
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
