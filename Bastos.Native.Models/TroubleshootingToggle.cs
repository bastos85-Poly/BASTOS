using System;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class TroubleshootingToggle : ObservableObject
{
	private bool isOn;

	private bool isBusy;

	private string state;

	public string Key { get; }

	public string Title { get; }

	public string Description { get; }

	public bool IsOn
	{
		get
		{
			return isOn;
		}
		set
		{
			if (SetProperty(ref isOn, value, "IsOn"))
			{
				RaisePropertyChanged("IsRecommendationMet");
				RaisePropertyChanged("RecommendationText");
			}
		}
	}

	public bool IsBusy
	{
		get
		{
			return isBusy;
		}
		set
		{
			SetProperty(ref isBusy, value, "IsBusy");
		}
	}

	public string State
	{
		get
		{
			return state;
		}
		set
		{
			SetProperty(ref state, value, "State");
		}
	}

	public bool? RecommendedIsOn { get; }

	public string Recommendation { get; }

	public string HelpText { get; }

	public bool HasHelp => !string.IsNullOrWhiteSpace(HelpText);

	public bool IsRecommendationMet
	{
		get
		{
			if (RecommendedIsOn.HasValue)
			{
				return IsOn == RecommendedIsOn.Value;
			}
			return true;
		}
	}

	public string RecommendationText
	{
		get
		{
			if (RecommendedIsOn.HasValue)
			{
				return "Conseillé : " + (RecommendedIsOn.Value ? "activé" : "désactivé") + " — " + Recommendation;
			}
			return Recommendation;
		}
	}

	public AsyncRelayCommand ToggleCommand { get; }

	public TroubleshootingToggle(string key, string title, string description, bool initialState, Func<TroubleshootingToggle, Task> toggle, bool? recommendedIsOn = null, string recommendation = "", string helpText = "")
	{
		TroubleshootingToggle arg = this;
		Key = key;
		Title = title;
		Description = description;
		RecommendedIsOn = recommendedIsOn;
		Recommendation = recommendation;
		HelpText = helpText;
		isOn = initialState;
		state = (initialState ? "Activé" : "Désactivé");
		ToggleCommand = new AsyncRelayCommand(() => toggle(arg));
	}
}
