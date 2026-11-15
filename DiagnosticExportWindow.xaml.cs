using System;
using System.ComponentModel;
using System.Windows;
using Bastos.Native.ViewModels;
using Microsoft.Win32;
namespace Bastos.Native;
public partial class DiagnosticExportWindow : Window
{
    private readonly DiagnosticExportViewModel model;
    public DiagnosticExportWindow(DiagnosticExportViewModel model)
    {
        InitializeComponent(); LocalizedPresentation.Watch(this); DataContext = this.model = model;
        MaxHeight = SystemParameters.WorkArea.Height;
        MaxWidth = SystemParameters.WorkArea.Width;
        Loaded += async (_, _) => await model.PrepareAsync();
        Closing += (_, e) => { if (model.IsBusy) e.Cancel = true; };
    }
    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!model.CanExport) return;
        var dialog = new SaveFileDialog { Title = "Enregistrer le diagnostic Bastos", Filter = "Archive ZIP (*.zip)|*.zip", DefaultExt = ".zip", AddExtension = true,
            FileName = "Bastos-Diagnostic-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".zip", OverwritePrompt = false };
        if (dialog.ShowDialog(this) == true) await model.ExportAsync(dialog.FileName);
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
