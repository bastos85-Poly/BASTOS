using System.Windows;
using Bastos.Native.ViewModels;

namespace Bastos.Native;

public partial class IsoCustomizationWindow : Window
{
	private readonly ReinstallViewModel viewModel;

	public IsoCustomizationWindow(ReinstallViewModel viewModel)
	{
		this.viewModel = viewModel;
		InitializeComponent();
		DataContext = viewModel;
	}

	private void SelectAll_Click(object sender, RoutedEventArgs e)
	{
		foreach (var option in viewModel.AppxRemovalOptions) option.IsSelected = true;
	}

	private void ClearAll_Click(object sender, RoutedEventArgs e)
	{
		foreach (var option in viewModel.AppxRemovalOptions) option.IsSelected = false;
	}

	private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;

	private void Create_Click(object sender, RoutedEventArgs e) => DialogResult = true;
}
