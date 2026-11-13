using System;
using System.ComponentModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Bastos.Native.Infrastructure;

public sealed class AsyncRelayCommand(Func<Task> execute, Func<bool>? canExecute = null, Func<string>? disabledReason = null) : ICommand, INotifyPropertyChanged
{
	private bool running;
    public bool IsRunning => running;
	public event PropertyChangedEventHandler? PropertyChanged;
	public string DisabledReason => running ? "Cette action est en cours. Attends sa fin." : CanExecute(null) ? "" : disabledReason?.Invoke() ?? "";

	public event EventHandler? CanExecuteChanged;

	public bool CanExecute(object? parameter)
	{
		if (!running)
		{
			return canExecute?.Invoke() ?? true;
		}
		return false;
	}

	public async void Execute(object? parameter)
	{
		if (!CanExecute(parameter))
		{
			return;
		}
		running = true;
		RaiseCanExecuteChanged();
		try
		{
			await execute();
		}
		finally
		{
			running = false;
			RaiseCanExecuteChanged();
		}
	}

	public async Task ExecuteAsync()
	{
		if (!CanExecute(null))
		{
			return;
		}
		running = true;
		RaiseCanExecuteChanged();
		try
		{
			await execute();
		}
		finally
		{
			running = false;
			RaiseCanExecuteChanged();
		}
	}

	public void RaiseCanExecuteChanged()
	{
		CanExecuteChanged?.Invoke(this, EventArgs.Empty);
		PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisabledReason)));
	}
}
