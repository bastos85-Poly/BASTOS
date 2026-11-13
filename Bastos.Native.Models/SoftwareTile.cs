using Bastos.Native.Infrastructure;
using Bastos.Native.Services;

namespace Bastos.Native.Models;

public sealed class SoftwareTile : ObservableObject
{
	private bool isSelected;

	private bool isInstalled;

	private bool isFavorite;

	public SoftwarePackage Package { get; }

	public string Category => Package.Category;

	public string Name => Package.Name;

	public string IconPath { get; }

	public string Description { get; }

	public bool IsSelected
	{
		get
		{
			return isSelected;
		}
		set
		{
			SetProperty(ref isSelected, value, "IsSelected");
		}
	}

	public bool IsInstalled
	{
		get
		{
			return isInstalled;
		}
		set
		{
			SetProperty(ref isInstalled, value, "IsInstalled");
		}
	}

	public bool IsFavorite
	{
		get => isFavorite;
		set
		{
			if (SetProperty(ref isFavorite, value, "IsFavorite"))
			{
				RaisePropertyChanged("FavoriteToolTip");
				RaisePropertyChanged("FavoriteAutomationName");
			}
		}
	}

	public string FavoriteToolTip => IsFavorite ? "Retirer des favoris" : "Ajouter aux favoris";

	public string FavoriteAutomationName => FavoriteToolTip + " : " + Name;

	public SoftwareTile(SoftwarePackage package, string iconPath, string description)
	{
		Package = package;
		IconPath = iconPath;
		Description = description;
	}
}
