using System;
using System.Windows;
using System.Windows.Controls;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class MemorySettingsPage : UserControl
{
    private readonly NativeActionService actions;
    private bool busy;
    public MemorySettingsPage()
    {
        InitializeComponent();
        actions = new NativeActionService(new ProcessExecutionService(), new OperationLogService(new AppPaths()));
    }
    private async void ClearStandby(object sender, RoutedEventArgs args)
    {
        if (busy) return;
        busy = true;
        ClearButton.IsEnabled = false;
        BusyIndicator.Visibility = Visibility.Visible;
        ResultText.Text = "Autorisation Windows puis nettoyage en cours…";
        try
        {
            var result = await actions.RunElevatedAsync("memory-standby-clear");
            ResultText.Text = (result.Success ? "✓ " : "") + result.Message;
        }
        catch (Exception ex) { ResultText.Text = "Nettoyage interrompu : " + ex.Message; }
        finally
        {
            busy = false;
            ClearButton.IsEnabled = true;
            BusyIndicator.Visibility = Visibility.Collapsed;
        }
    }
}
