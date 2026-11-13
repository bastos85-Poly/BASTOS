using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

using System.Threading.Tasks;

public sealed class StatusCard : ObservableObject
{
	private bool progressVisible;
	private double? progressPercent;
	public bool ProgressVisible { get => progressVisible; set => SetProperty(ref progressVisible, value); }
	public double? ProgressPercent { get => progressPercent; set { if (SetProperty(ref progressPercent, value)) RaisePropertyChanged(nameof(ProgressIndeterminate)); } }
	public bool ProgressIndeterminate => !ProgressPercent.HasValue;
	private string state;
	private string stateDetail = "";
	public string StateDetail { get => stateDetail; set => SetProperty(ref stateDetail, value); }

	private StatusTone tone;

	private bool isPrimarySelected;

	private bool isSecondarySelected;

	public string Title { get; }

	public string Description { get; }
	public bool IsHardwareResult { get; init; }
	public string HardwareRole { get; init; } = "";
	public string HardwareSource { get; init; } = "";
	public string HardwareDetails { get; init; } = "";

	public string State
	{
		get
		{
			return state;
		}
		set
		{
			StateDetail = "";
			SetProperty(ref state, value, "State");
		}
	}

	public StatusTone Tone
	{
		get
		{
			return tone;
		}
		set
		{
			SetProperty(ref tone, value, "Tone");
		}
	}

	public string PrimaryText { get; }

	public AsyncRelayCommand? PrimaryCommand { get; }

	public string SecondaryText { get; }

	public AsyncRelayCommand? SecondaryCommand { get; }

	public bool IsChoiceCard { get; }

    public bool IsToggleCard => HasPrimaryAction && HasSecondaryAction &&
        (PrimaryText == "Activer" || PrimaryText == "Appliquer") &&
        (SecondaryText.StartsWith("Restaurer", System.StringComparison.Ordinal) || SecondaryText == "Désactiver");
    public bool ShowChoiceActions => IsChoiceCard || IsToggleCard;
    public bool ShowChoiceButtons => IsChoiceCard && !IsToggleCard;
    public bool ShowPairedButtons => !IsToggleCard;
    public bool? ToggleState => IsPrimarySelected == IsSecondarySelected ? null : IsPrimarySelected;
    private bool partiallyApplied;
    public bool IsPartiallyApplied { get => partiallyApplied; set { SetProperty(ref partiallyApplied, value); NotifyToggleState(); } }
    public string ToggleLabel => ToggleState == true ? (IsPartiallyApplied ? "Partiellement appliqué" : "Activé") : ToggleState == false
        ? "Désactivé" : "État à vérifier";
    public string ToggleHelp => !ToggleState.HasValue ? "Actualisez l’état du réglage avant de le modifier."
        : ToggleState.Value ? (SecondaryText.StartsWith("Restaurer", System.StringComparison.Ordinal) ? "Restaurer les valeurs précédentes" : "Désactiver le réglage")
        : "Activer le réglage";
    public AsyncRelayCommand ToggleCommand { get; }
    private AsyncRelayCommand? NextToggleAction => ToggleState == true ? SecondaryCommand : PrimaryCommand;
    private bool CanToggle() => IsToggleCard && ToggleState.HasValue &&
        !PrimaryCommand!.IsRunning && !SecondaryCommand!.IsRunning && NextToggleAction!.CanExecute(null);
    private async Task ExecuteToggleAsync()
    {
        // Keep the confirmed position until the existing operation verifies its result.
        var command = NextToggleAction;
        if (CanToggle() && command != null) await command.ExecuteAsync();
    }
    private void NotifyToggleState()
    {
        RaisePropertyChanged(nameof(ToggleState));
        RaisePropertyChanged(nameof(ToggleLabel));
        RaisePropertyChanged(nameof(ToggleHelp));
        ToggleCommand?.RaiseCanExecuteChanged();
    }

	public bool IsPrimarySelected
	{
		get
		{
			return isPrimarySelected;
		}
		private set
		{
			SetProperty(ref isPrimarySelected, value, "IsPrimarySelected");
			NotifyToggleState();
		}
	}

	public bool IsSecondarySelected
	{
		get
		{
			return isSecondarySelected;
		}
		private set
		{
			SetProperty(ref isSecondarySelected, value, "IsSecondarySelected");
			NotifyToggleState();
		}
	}

	public bool HasPrimaryAction
	{
		get
		{
			if (PrimaryCommand != null)
			{
				return !string.IsNullOrWhiteSpace(PrimaryText);
			}
			return false;
		}
	}

	public bool HasSecondaryAction
	{
		get
		{
			if (SecondaryCommand != null)
			{
				return !string.IsNullOrWhiteSpace(SecondaryText);
			}
			return false;
		}
	}

	public bool ShowStandardActions => !IsChoiceCard && !IsToggleCard;

	public StatusCard(string title, string description, string state, StatusTone tone, string? primaryText = null, AsyncRelayCommand? primaryCommand = null, string? secondaryText = null, AsyncRelayCommand? secondaryCommand = null, bool isChoiceCard = false, bool primarySelected = false, bool secondarySelected = false)
	{
		Title = title;
		Description = description;
		this.state = state;
		this.tone = tone;
		PrimaryText = primaryText ?? string.Empty;
		PrimaryCommand = primaryCommand;
		SecondaryText = secondaryText ?? string.Empty;
		SecondaryCommand = secondaryCommand;
		IsChoiceCard = isChoiceCard;
		isPrimarySelected = primarySelected;
		isSecondarySelected = secondarySelected;
        ToggleCommand = new AsyncRelayCommand(ExecuteToggleAsync, CanToggle, () => ToggleHelp);
        if (PrimaryCommand != null) PrimaryCommand.CanExecuteChanged += (_, _) => ToggleCommand.RaiseCanExecuteChanged();
        if (SecondaryCommand != null) SecondaryCommand.CanExecuteChanged += (_, _) => ToggleCommand.RaiseCanExecuteChanged();
	}

    public void ClearChoice(){IsPrimarySelected=false;IsSecondarySelected=false;}

	public void SelectChoice(bool primary)
	{
		IsPrimarySelected = primary;
		IsSecondarySelected = !primary;
	}
}
