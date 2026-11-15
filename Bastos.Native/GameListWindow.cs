using System.Windows;
using System.Windows.Markup;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class GameListWindow : Window, IComponentConnector
{
	private readonly BastosGameService service;

	private readonly bool blocked;

	public GameListWindow(BastosGameService service, bool blocked)
	{
		InitializeComponent(); LocalizedPresentation.Watch(this);
		this.service = service;
		this.blocked = blocked;
		Heading.Text = (blocked ? "Applications bloquées" : "Jeux autorisés");
		Reload();
	}

	private void Reload()
	{
		BastosGameConfig bastosGameConfig = service.Load();
		Entries.ItemsSource = (blocked ? bastosGameConfig.BlockedApps : bastosGameConfig.Games).ToArray();
	}

	private void RemoveClicked(object sender, RoutedEventArgs e)
	{
		if (Entries.SelectedItem is GameEntry entry)
		{
			service.Remove(entry, blocked);
			Reload();
		}
	}

	private void CloseClicked(object sender, RoutedEventArgs e)
	{
		Close();
	}
}
