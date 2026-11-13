using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class TroubleshootingChoice : ObservableObject
{
	private string selectedValue;

	private string state = "Prêt";

	public string Key { get; }

	public string Title { get; }

	public string Description { get; }

	public ObservableCollection<string> Values { get; }

	public string SelectedValue
	{
		get
		{
			return selectedValue;
		}
		set
		{
			if (SetProperty(ref selectedValue, value, "SelectedValue"))
			{
				RaisePropertyChanged("IsRecommendationMet");
				RaisePropertyChanged("RecommendationText");
			}
		}
	}

	public string RecommendedValue { get; }

	public string Recommendation { get; }

	public bool IsRecommendationMet
	{
		get
		{
			if (!string.IsNullOrWhiteSpace(RecommendedValue))
			{
				return string.Equals(SelectedValue, RecommendedValue, StringComparison.Ordinal);
			}
			return true;
		}
	}

	public string RecommendationText
	{
		get
		{
			if (!string.IsNullOrWhiteSpace(RecommendedValue))
			{
				return "Conseillé : " + RecommendedValue + " — " + Recommendation;
			}
			return Recommendation;
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

	public AsyncRelayCommand ApplyCommand { get; }
	public AsyncRelayCommand DefaultCommand { get; }
	public AsyncRelayCommand BastosCommand { get; }

	public TroubleshootingChoice(string key, string title, string description, IEnumerable<string> values, string selected, Func<TroubleshootingChoice, Task> apply, string recommendedValue = "", string recommendation = "")
	{
		TroubleshootingChoice arg = this;
		Key = key;
		Title = title;
		Description = description;
		Values = new ObservableCollection<string>(values);
		RecommendedValue = recommendedValue;
		Recommendation = recommendation;
		selectedValue = selected;
		ApplyCommand = new AsyncRelayCommand(() => apply(arg));
		DefaultCommand = new AsyncRelayCommand(() => ApplyPresetAsync("Par défaut Windows"), () => ApplyCommand.CanExecute(null));
		BastosCommand = new AsyncRelayCommand(() => ApplyPresetAsync("Personnalisation Bastos"), () => ApplyCommand.CanExecute(null));
		ApplyCommand.CanExecuteChanged += (_, _) => { DefaultCommand.RaiseCanExecuteChanged(); BastosCommand.RaiseCanExecuteChanged(); };
	}

	private async Task ApplyPresetAsync(string value)
	{
		if (!ApplyCommand.CanExecute(null)) return;
		SelectedValue = value;
		await ApplyCommand.ExecuteAsync();
	}
}
