using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class QuantumSchedulerModel : ObservableObject
{
	private string quantumLength = "Court";

	private string quantumType = "Variable";

	private string foregroundBoost = "Élevé (3:1)";

	private int currentValue = 38;

	private string state = "Prêt";

	public ObservableCollection<string> QuantumLengths { get; }

	public ObservableCollection<string> QuantumTypes { get; }

	public ObservableCollection<string> ForegroundBoosts { get; }

	public string QuantumLength
	{
		get
		{
			return quantumLength;
		}
		set
		{
			if (SetProperty(ref quantumLength, value, "QuantumLength"))
			{
				RaisePreview();
			}
		}
	}

	public string QuantumType
	{
		get
		{
			return quantumType;
		}
		set
		{
			if (SetProperty(ref quantumType, value, "QuantumType"))
			{
				RaisePreview();
			}
		}
	}

	public string ForegroundBoost
	{
		get
		{
			return foregroundBoost;
		}
		set
		{
			if (SetProperty(ref foregroundBoost, value, "ForegroundBoost"))
			{
				RaisePreview();
			}
		}
	}

	public int CurrentValue
	{
		get
		{
			return currentValue;
		}
		set
		{
			if (SetProperty(ref currentValue, value, "CurrentValue"))
			{
				RaisePropertyChanged("CurrentHex");
				RaisePropertyChanged("CurrentBinary");
				RaisePropertyChanged("CurrentSummary");
                SelectionSwitch?.Refresh();
			}
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

	public int PreviewValue => ((QuantumType == "Variable") ? 32 : 16) + ((QuantumLength == "Court") ? 4 : 8) + (ForegroundBoost.StartsWith("Élevé") ? 2 : (ForegroundBoost.StartsWith("Moyen") ? 1 : 0));

	public string PreviewHex => $"0x{PreviewValue:X2}";

	public string PreviewBinary => Convert.ToString(PreviewValue, 2).PadLeft(6, '0');

	public string PreviewSummary => $"Quantum {QuantumLength.ToLowerInvariant()}, {QuantumType.ToLowerInvariant()}, avantage {ForegroundBoost.ToLowerInvariant()}";

	public string RecommendationText => "Conseillé : Court · Variable · Élevé (3:1) = 0x26 — défaut Windows, adapté aux jeux au premier plan.";

	public bool IsRecommendedPreview => PreviewValue == 38;

	public string CurrentHex => $"0x{CurrentValue:X2}";

	public string CurrentBinary => Convert.ToString(CurrentValue, 2).PadLeft(6, '0');

	public string CurrentSummary => Decode(CurrentValue);

	public AsyncRelayCommand ApplyCommand { get; }

	public AsyncRelayCommand RestoreCommand { get; }
    public SettingSwitchModel SelectionSwitch {get;}

	public QuantumSchedulerModel(Func<Task> apply, Func<Task> restore)
	{
		int num = 2;
		List<string> list = new List<string>(num);
		CollectionsMarshal.SetCount(list, num);
		Span<string> span = CollectionsMarshal.AsSpan(list);
		int num2 = 0;
		span[num2] = "Court";
		num2++;
		span[num2] = "Long";
		num2++;
		QuantumLengths = new ObservableCollection<string>(list);
		num2 = 2;
		List<string> list2 = new List<string>(num2);
		CollectionsMarshal.SetCount(list2, num2);
		span = CollectionsMarshal.AsSpan(list2);
		num = 0;
		span[num] = "Variable";
		num++;
		span[num] = "Fixe";
		num++;
		QuantumTypes = new ObservableCollection<string>(list2);
		num = 3;
		List<string> list3 = new List<string>(num);
		CollectionsMarshal.SetCount(list3, num);
		span = CollectionsMarshal.AsSpan(list3);
		num2 = 0;
		span[num2] = "Aucun (1:1)";
		num2++;
		span[num2] = "Moyen (2:1)";
		num2++;
		span[num2] = "Élevé (3:1)";
		num2++;
		ForegroundBoosts = new ObservableCollection<string>(list3);
		ApplyCommand = new AsyncRelayCommand(apply);
		RestoreCommand = new AsyncRelayCommand(restore);
        SelectionSwitch=new("Planificateur Quantum",ApplyCommand,RestoreCommand,()=>CurrentValue!=38&&CurrentValue==PreviewValue,restoreHelp:"Restaurer le défaut Windows (0x26)");
	}

	public void LoadFromValue(int value)
	{
		CurrentValue = value;
		QuantumType = (((value & 0x20) != 0) ? "Variable" : "Fixe");
		QuantumLength = (((value & 4) != 0) ? "Court" : "Long");
		ForegroundBoost = (value & 3) switch
		{
			0 => "Aucun (1:1)", 
			1 => "Moyen (2:1)", 
			_ => "Élevé (3:1)", 
		};
	}

	private static string Decode(int value)
	{
		string value2 = (((value & 0x20) != 0) ? "variable" : "fixe");
		string value3 = (((value & 4) != 0) ? "court" : "long");
		string value4 = (value & 3) switch
		{
			0 => "aucun avantage", 
			1 => "avantage moyen", 
			_ => "avantage élevé", 
		};
		return $"Quantum {value3}, {value2}, {value4} au premier plan";
	}

	private void RaisePreview()
	{
		RaisePropertyChanged("PreviewValue");
		RaisePropertyChanged("PreviewHex");
		RaisePropertyChanged("PreviewBinary");
		RaisePropertyChanged("PreviewSummary");
		RaisePropertyChanged("IsRecommendedPreview");
        SelectionSwitch?.Refresh();
	}
}
