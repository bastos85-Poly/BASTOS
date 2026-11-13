using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class IsoRemovalChoice(string packageId, string display) : ObservableObject
{
	private bool isSelected = true;

	public string PackageId { get; } = packageId;
	public string Display { get; } = display;

	public bool IsSelected
	{
		get => isSelected;
		set => SetProperty(ref isSelected, value);
	}
}
