using System.Collections.Generic;
using System.Collections.ObjectModel;
using Bastos.Native.Models;

namespace Bastos.Native.ViewModels;

public sealed class PageViewModel
{
	public string Title { get; }

	public string Subtitle { get; }

	public ObservableCollection<StatusCard> Cards { get; }

	public bool ShowCompatibilityAction { get; }

	public bool IsReinstall { get; }

	public bool IsBrowsers { get; }

	public bool IsSoftware { get; }

	public bool IsTroubleshooting { get; }

	public bool IsTweaking { get; }

	public bool IsDashboard { get; }

	public bool IsOptimizations { get; }
	public bool IsHardware { get; }
	public StatusCard? HardwareAnalysisCard { get; set; }
	public StatusCard? GraphicsStandardCard { get; set; }
	public StatusCard? GraphicsLiteCard { get; set; }
	public ObservableCollection<StatusCard> HardwareResults { get; } = new();

	public bool IsJournal => Title == "Journal";
    public bool IsCleaner => Title == "Nettoyeur";

    public bool IsGame => Title == "Bastos Game";

 public bool IsStandardPage
	{
		get
		{
			if (!IsCleaner && !IsJournal && !IsGame && !IsReinstall && !IsBrowsers && !IsSoftware && !IsTroubleshooting && !IsTweaking && !IsDashboard && !IsHardware)
			{
				return !IsOptimizations;
			}
			return false;
		}
	}

	public PageViewModel(string title, string subtitle, IEnumerable<StatusCard> cards, bool compatibilityAction, bool isReinstall = false, bool isBrowsers = false, bool isSoftware = false, bool isTroubleshooting = false, bool isTweaking = false, bool isDashboard = false, bool isOptimizations = false, bool isHardware = false)
	{
		Title = title;
		Subtitle = subtitle;
		Cards = new ObservableCollection<StatusCard>(cards);
		ShowCompatibilityAction = compatibilityAction;
		IsReinstall = isReinstall;
		IsBrowsers = isBrowsers;
		IsSoftware = isSoftware;
		IsTroubleshooting = isTroubleshooting;
		IsTweaking = isTweaking;
		IsDashboard = isDashboard;
		IsOptimizations = isOptimizations;
		IsHardware = isHardware;
	}
}
