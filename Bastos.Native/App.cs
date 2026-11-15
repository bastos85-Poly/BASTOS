using System;
using System.Windows;
using Bastos.Native.Services;

namespace Bastos.Native;

public partial class App : Application
{
	protected override async void OnStartup(StartupEventArgs e)
	{
		if (Array.Exists(e.Args, arg => arg.Equals("--display-profile-agent", StringComparison.OrdinalIgnoreCase)))
		{
			ShutdownMode = ShutdownMode.OnExplicitShutdown;
			await DisplayProfileAgent.RunAsync();
			Shutdown();
			return;
		}
		string text = ReadArgument(e.Args, "--native-worker");
		string resultPath = ReadArgument(e.Args, "--result");
		if (text != null)
		{
			Shutdown(await NativeWorkerService.ExecuteAsync(text, resultPath));
			return;
		}
		base.OnStartup(e);
        LocalizedPresentation.Initialize();
		base.MainWindow = new MainWindow();
        LocalizedPresentation.Watch(base.MainWindow);
		base.MainWindow.Show();
	}

	private static string? ReadArgument(string[] args, string name)
	{
		for (int i = 0; i < args.Length - 1; i++)
		{
			if (args[i].Equals(name, StringComparison.OrdinalIgnoreCase))
			{
				return args[i + 1];
			}
		}
		return null;
	}
}
