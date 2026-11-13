using System;
using System.IO;

namespace Bastos.Native.Services;

public sealed class AppPaths
{
	public string Root { get; }

	public string VersionFile { get; }

	public string DataRoot { get; }

	public string LogRoot { get; }

	public string StateRoot { get; }

	public string GameRoot { get; }

	public string LegacyGameRoot { get; }

	public string GameConfig { get; }

	public string GameStatus { get; }

	public string GameStopRequest { get; }

	public string GameRecovery { get; }

	public string LegacyGameStopRequest { get; }

	public string GameLog { get; }

	public string GameEngine { get; }

	public string GameTrayIcon { get; }

	public string NativeExecutable { get; }

	public string NativeLog { get; }

	public string PackageManagerReadyMarker { get; }

	public string Version
	{
		get
		{
			if (!File.Exists(VersionFile))
			{
				return "inconnue";
			}
			return File.ReadAllText(VersionFile).Trim();
		}
	}

	public AppPaths() : this(null, null) { }
    internal AppPaths(string? applicationRoot, string? dataRoot)
	{
		string text = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
		string text2 = Directory.GetParent(text)?.FullName ?? text;
		string text3 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "BASTOS");
		Root = applicationRoot ?? (File.Exists(Path.Combine(text, "VERSION.txt")) ? text : (File.Exists(Path.Combine(text2, "VERSION.txt")) ? text2 : (File.Exists(Path.Combine(text3, "VERSION.txt")) ? text3 : text2)));
		VersionFile = Path.Combine(Root, "VERSION.txt");
		DataRoot = dataRoot ?? SmokeDataRoot() ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS");
		LogRoot = Path.Combine(DataRoot, "Logs");
		StateRoot = Path.Combine(DataRoot, "State");
		GameRoot = Path.Combine(DataRoot, "Bastos Game");
		LegacyGameRoot = Path.Combine(DataRoot, "Game");
		GameConfig = Path.Combine(GameRoot, "Config.json");
		GameStatus = Path.Combine(GameRoot, "Status.json");
		GameStopRequest = Path.Combine(GameRoot, "Stop.request");
		GameRecovery = Path.Combine(GameRoot, "Recovery.json");
		LegacyGameStopRequest = Path.Combine(LegacyGameRoot, "Stop.request");
		GameLog = Path.Combine(LogRoot, "Bastos-Game.log");
		GameEngine = Path.Combine(Root, "Bastos.Game", "BASTOS-Game.exe");
		GameTrayIcon = Path.Combine(Root, "Assets", "Bastos-Game-Tray.ico");
		NativeExecutable = Path.Combine(Root, "Bastos.Native", "BASTOS-Native.exe");
		NativeLog = Path.Combine(LogRoot, "BASTOS-Native.log");
		PackageManagerReadyMarker = Path.Combine(StateRoot, "PackageManager-Ready-v1.ok");
	}

	public string Script(string name)
	{
		return Path.Combine(Root, name);
	}

    private static string? SmokeDataRoot()
    {
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--smoke-test") < 0)return null;
        string? path=Environment.GetEnvironmentVariable("BASTOS_TEST_DATA");
        if(string.IsNullOrWhiteSpace(path))return null;
        string full=Path.GetFullPath(path), temporary=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        if(!full.StartsWith(temporary,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Les donnees de test doivent rester dans le dossier temporaire du test.");
        return full;
    }
}
