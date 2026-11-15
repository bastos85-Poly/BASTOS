using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using Bastos.Native.Models;

namespace Bastos.Native;

public partial class RecoveryEditionWindow : Window
{
    public WindowsIsoEdition? SelectedEdition => EditionCombo.SelectedItem as WindowsIsoEdition;

    public RecoveryEditionWindow(IReadOnlyList<WindowsIsoEdition> editions)
    {
        InitializeComponent(); LocalizedPresentation.Watch(this);
        EditionCombo.ItemsSource = editions;
    }

    private void Edition_SelectionChanged(object sender, SelectionChangedEventArgs e) =>
        ContinueButton.IsEnabled = SelectedEdition != null;

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedEdition != null) DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
