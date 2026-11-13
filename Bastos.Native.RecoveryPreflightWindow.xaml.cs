using System;
using System.Windows;
using Bastos.Native.Models;

namespace Bastos.Native;

public partial class RecoveryPreflightWindow : Window
{
    public RecoveryPreflight Review { get; }
    public RecoveryPreflightWindow(RecoveryPreflight review)
    {
        Review = review;
        InitializeComponent();
        DataContext = review;
        UpdateLaunchAvailability();
        MaxHeight = Math.Max(550, SystemParameters.WorkArea.Height - 32);
        MaxWidth = Math.Max(650, SystemParameters.WorkArea.Width - 32);
    }
    private void Acknowledgement_Changed(object sender, RoutedEventArgs e)
    {
        UpdateLaunchAvailability();
    }
    private void UpdateLaunchAvailability()
    {
        if (LaunchButton == null || LaunchHint == null) return;
        LaunchButton.IsEnabled = Review.CanContinue && Acknowledgement.IsChecked == true;
        string reason = LaunchButton.IsEnabled ? "" : !Review.CanContinue
            ? "Corrige les points bloquants indiqués dans ce bilan avant de lancer."
            : "Relis le plan, puis coche la confirmation pour autoriser le lancement.";
        LaunchHint.Text = reason;
        LaunchButton.ToolTip = reason.Length == 0 ? null : reason;
        System.Windows.Automation.AutomationProperties.SetHelpText(LaunchButton, reason);
    }
    private void Launch_Click(object sender, RoutedEventArgs e)
    {
        if (Review.CanContinue && Acknowledgement.IsChecked == true) DialogResult = true;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
