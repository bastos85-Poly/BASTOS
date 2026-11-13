using System;
using System.ComponentModel;
using System.Windows.Input;

namespace Bastos.Native.Infrastructure;

public sealed class RelayCommand(Action execute, Func<bool>? canExecute = null, Func<string>? disabledReason = null) : ICommand, INotifyPropertyChanged
{
	public event PropertyChangedEventHandler? PropertyChanged;
	public string DisabledReason => CanExecute(null) ? "" : disabledReason?.Invoke() ?? "";
	public event EventHandler? CanExecuteChanged;

	public bool CanExecute(object? parameter)
	{
		return canExecute?.Invoke() ?? true;
	}

	public void Execute(object? parameter)
	{
		if (CanExecute(parameter)) execute();
	}

	public void RaiseCanExecuteChanged()
	{
		CanExecuteChanged?.Invoke(this, EventArgs.Empty);
		PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisabledReason)));
	}
}
