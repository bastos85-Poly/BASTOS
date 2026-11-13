using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class TweakingTool : ObservableObject
{
	private string state;

	public string Name { get; }

	public string Description { get; }

	public string? PackageId { get; }

	public string? SourceUrl { get; }

	public string? CustomAction { get; }

	public string? LocalRelativePath { get; }

	public string ActionLabel { get; }

	public ObservableCollection<string> Executables { get; }

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

	public AsyncRelayCommand RunCommand { get; }

	public TweakingTool(string name, string description, string? packageId, string? sourceUrl, string? customAction, IEnumerable<string>? executables, Func<TweakingTool, Task> run, string? localRelativePath = null, string actionLabel = "Installer / ouvrir", string initialState = "Prêt")
	{
		TweakingTool arg = this;
		Name = name;
		Description = description;
		PackageId = packageId;
		SourceUrl = sourceUrl;
		CustomAction = customAction;
		LocalRelativePath = localRelativePath;
		ActionLabel = actionLabel;
		Executables = new ObservableCollection<string>(executables ?? Array.Empty<string>());
		state = initialState;
		RunCommand = new AsyncRelayCommand(() => run(arg));
	}
}
