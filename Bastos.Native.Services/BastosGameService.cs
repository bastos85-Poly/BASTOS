using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class BastosGameService(AppPaths paths, OperationLogService log)
{
	private readonly JsonSerializerOptions jsonOptions = new JsonSerializerOptions
	{
		WriteIndented = true,
		PropertyNameCaseInsensitive = true
	};

	public void Initialize()
	{
		BastosGameConfig bastosGameConfig = Load();
		SetStartup(bastosGameConfig);
		if (bastosGameConfig.Enabled)
		{
			Start();
		}
	}

	public BastosGameConfig Load()
	{
		try
		{
			if (File.Exists(paths.GameConfig))
			{
				return JsonSerializer.Deserialize<BastosGameConfig>(File.ReadAllText(paths.GameConfig), jsonOptions) ?? new BastosGameConfig();
			}
		}
		catch (Exception ex)
		{
			log.Write("Bastos Game", "Configuration illisible : " + ex.Message, error: true);
		}
		return new BastosGameConfig();
	}

	public void Save(BastosGameConfig config)
	{
		Directory.CreateDirectory(paths.GameRoot);
		config.Games = Normalize(config.Games, byName: false);
		config.BlockedApps = Normalize(config.BlockedApps, byName: true);
		File.WriteAllText(paths.GameConfig, JsonSerializer.Serialize(config, jsonOptions), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
		SetStartup(config);
	}

	public string StatusText()
	{
		BastosGameConfig bastosGameConfig = Load();
		if (!bastosGameConfig.Enabled)
		{
			return "Arrêté";
		}
		try
		{
			if (File.Exists(paths.GameStatus))
			{
				using JsonDocument jsonDocument = JsonDocument.Parse(File.ReadAllText(paths.GameStatus));
				JsonElement rootElement = jsonDocument.RootElement;
				string text = (rootElement.TryGetProperty("State", out var value) ? (value.GetString() ?? "") : "");
				DateTime dateTime = ((rootElement.TryGetProperty("UpdatedUtc", out var value2) && DateTime.TryParse(value2.GetString(), out var result)) ? result.ToUniversalTime() : DateTime.MinValue);
				if (text == "Ready" && DateTime.UtcNow - dateTime < TimeSpan.FromSeconds(6.0))
				{
					if (rootElement.TryGetProperty("ActiveGames", out var value3) && value3.ValueKind == JsonValueKind.Array && value3.GetArrayLength() > 0)
					{
						string text2 = string.Join(", ", value3.EnumerateArray().Select(delegate(JsonElement game)
						{
							JsonElement jsonElement = game;
							JsonElement value5;
							return jsonElement.TryGetProperty("Name", out value5) ? value5.GetString() : "Jeu";
						}));
						return "En jeu — " + text2;
					}
					return bastosGameConfig.AutoDetect ? "Prêt — détection automatique" : "Prêt — jeux autorisés uniquement";
				}
				if (text == "Error" && rootElement.TryGetProperty("Error", out var value4))
				{
					return "Erreur — " + value4.GetString();
				}
			}
		}
		catch
		{
		}
		return "Moniteur non démarré";
	}

	public void AddGame(string executable, bool blocked)
	{
		string fullPath = Path.GetFullPath(executable);
		if (!File.Exists(fullPath) || !fullPath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
		{
			throw new InvalidOperationException("Sélectionne un fichier .exe existant.");
		}
		BastosGameConfig bastosGameConfig = Load();
		GameEntry entry = new GameEntry
		{
			Path = fullPath,
			Name = (blocked ? Path.GetFileName(fullPath) : Path.GetFileNameWithoutExtension(fullPath))
		};
		List<GameEntry> list = (blocked ? bastosGameConfig.BlockedApps : bastosGameConfig.Games);
		if (!list.Any((GameEntry item) => string.Equals(blocked ? item.Name : item.Path, blocked ? entry.Name : entry.Path, StringComparison.OrdinalIgnoreCase)))
		{
			list.Add(entry);
		}
		Save(bastosGameConfig);
		Restart();
		log.Write("Bastos Game", (blocked ? "Application bloquée" : "Jeu autorisé") + " : " + fullPath);
	}

	public void Remove(GameEntry entry, bool blocked)
	{
		BastosGameConfig bastosGameConfig = Load();
		(blocked ? bastosGameConfig.BlockedApps : bastosGameConfig.Games).RemoveAll((GameEntry item) => string.Equals(blocked ? item.Name : item.Path, blocked ? entry.Name : entry.Path, StringComparison.OrdinalIgnoreCase));
		Save(bastosGameConfig);
		Restart();
		log.Write("Bastos Game", "Entrée retirée : " + entry.Name);
	}

	public void Start()
	{
		BastosGameConfig bastosGameConfig = Load();
		bastosGameConfig.Enabled = true;
		Save(bastosGameConfig);
		if (IsCanonicalMonitorRunning())
		{
			log.Write("Bastos Game", "Le moniteur est déjà actif.");
			return;
		}
		StopLegacyMonitorAndWait();
		if (!File.Exists(paths.GameEngine))
		{
			throw new FileNotFoundException("Le moteur natif Bastos Game est absent.", paths.GameEngine);
		}
		try
		{
			File.Delete(paths.GameStopRequest);
		}
		catch
		{
		}
		if (StartThroughAuthorizedTask())
		{
			log.Write("Bastos Game", "Moteur natif demarre par la tache autorisee, sans UAC.");
			return;
		}
		ProcessStartInfo processStartInfo = new ProcessStartInfo(paths.GameEngine)
		{
			UseShellExecute = false,
			CreateNoWindow = true,
			WindowStyle = ProcessWindowStyle.Hidden
		};
		foreach (string item in BuildMonitorArguments())
		{
			processStartInfo.ArgumentList.Add(item);
		}
		Process.Start(processStartInfo);
		log.Write("Bastos Game", "Moteur natif démarré.");
	}

	private bool StartThroughAuthorizedTask()
	{
		const string taskName = "\\BASTOS\\BASTOS Game";
		try
		{
			ProcessStartInfo query = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe"))
			{
				UseShellExecute = false,
				CreateNoWindow = true,
				WindowStyle = ProcessWindowStyle.Hidden
			};
			query.ArgumentList.Add("/Query");
			query.ArgumentList.Add("/TN");
			query.ArgumentList.Add(taskName);
			using Process? queryProcess = Process.Start(query);
			if (queryProcess == null || !queryProcess.WaitForExit(5000) || queryProcess.ExitCode != 0)
			{
				return false;
			}

			ProcessStartInfo run = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe"))
			{
				UseShellExecute = false,
				CreateNoWindow = true,
				WindowStyle = ProcessWindowStyle.Hidden
			};
			run.ArgumentList.Add("/Run");
			run.ArgumentList.Add("/TN");
			run.ArgumentList.Add(taskName);
			using Process? runProcess = Process.Start(run);
			if (runProcess != null && runProcess.WaitForExit(5000) && runProcess.ExitCode == 0)
			{
				return true;
			}
		}
		catch (Exception ex)
		{
			log.Write("Bastos Game", "Tache autorisee indisponible : " + ex.Message, error: true);
		}
		return false;
	}

	public void Stop(bool disable = true)
	{
		WriteStopRequest(paths.GameStopRequest);
		WriteStopRequest(paths.LegacyGameStopRequest);
		if (disable)
		{
			BastosGameConfig bastosGameConfig = Load();
			bastosGameConfig.Enabled = false;
			Save(bastosGameConfig);
		}
		WaitForMonitorExit(4000);
		log.Write("Bastos Game", "Demande d’arrêt envoyée.");
	}

	private static void WriteStopRequest(string path)
	{
		Directory.CreateDirectory(Path.GetDirectoryName(path));
		File.WriteAllText(path, DateTime.UtcNow.ToString("O"));
	}

	private void StopLegacyMonitorAndWait()
	{
		WriteStopRequest(paths.GameStopRequest);
		WriteStopRequest(paths.LegacyGameStopRequest);
		WaitForMonitorExit(4000);
	}

	private static void WaitForMonitorExit(int timeoutMilliseconds)
	{
		bool flag = false;
		try
		{
			using Mutex mutex = Mutex.OpenExisting("Local\\BASTOS-Game-Monitor");
			try
			{
				flag = mutex.WaitOne(timeoutMilliseconds);
			}
			catch (AbandonedMutexException)
			{
				flag = true;
			}
			if (!flag)
			{
				throw new InvalidOperationException("Bastos Game ne répond pas à la demande d’arrêt.");
			}
			mutex.ReleaseMutex();
		}
		catch (WaitHandleCannotBeOpenedException)
		{
		}
	}

	private bool IsCanonicalMonitorRunning()
	{
		try
		{
			if (!File.Exists(paths.GameStatus))
			{
				return false;
			}
			using JsonDocument jsonDocument = JsonDocument.Parse(File.ReadAllText(paths.GameStatus));
			JsonElement rootElement = jsonDocument.RootElement;
			if (!rootElement.TryGetProperty("State", out var value) || value.GetString() != "Ready")
			{
				return false;
			}
			if (!rootElement.TryGetProperty("UpdatedUtc", out var value2) || !DateTime.TryParse(value2.GetString(), out var result) || DateTime.UtcNow - result.ToUniversalTime() > TimeSpan.FromSeconds(6.0))
			{
				return false;
			}
			if (!rootElement.TryGetProperty("ProcessId", out var value3) || !value3.TryGetInt32(out var value4))
			{
				return false;
			}
			using Process process = Process.GetProcessById(value4);
			return !process.HasExited && string.Equals(process.ProcessName, "BASTOS-Game", StringComparison.OrdinalIgnoreCase);
		}
		catch
		{
			return false;
		}
	}

	public void Restart()
	{
		BastosGameConfig bastosGameConfig = Load();
		Stop(disable: false);
		if (bastosGameConfig.Enabled)
		{
			Start();
		}
	}

	private IEnumerable<string> BuildMonitorArguments()
	{
		return new string[14]
		{
			"--config", paths.GameConfig, "--status", paths.GameStatus, "--stop", paths.GameStopRequest, "--log", paths.GameLog, "--recovery", paths.GameRecovery,
			"--app", paths.NativeExecutable, "--icon", paths.GameTrayIcon
		};
	}

	private void SetStartup(BastosGameConfig config)
	{
		using (RegistryKey registryKey = Registry.CurrentUser.CreateSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Run"))
		{
			// Le demarrage eleve est gere par une tache planifiee creee une seule
			// fois pendant l'installation. Config.json conserve le choix utilisateur.
			registryKey.DeleteValue("BASTOS Game", throwOnMissingValue: false);
		}
	}

	private static List<GameEntry> Normalize(IEnumerable<GameEntry> entries, bool byName)
	{
		List<GameEntry> list = new List<GameEntry>();
		foreach (GameEntry entry in entries)
		{
			try
			{
				string full = Path.GetFullPath(entry.Path);
				string name = ((!byName) ? Path.GetFileNameWithoutExtension(full) : (string.IsNullOrWhiteSpace(entry.Name) ? Path.GetFileName(full) : entry.Name));
				if (!list.Any((GameEntry item) => string.Equals(byName ? item.Name : item.Path, byName ? name : full, StringComparison.OrdinalIgnoreCase)))
				{
					list.Add(new GameEntry
					{
						Path = full,
						Name = name,
						AddedUtc = (string.IsNullOrWhiteSpace(entry.AddedUtc) ? DateTime.UtcNow.ToString("O") : entry.AddedUtc)
					});
				}
			}
			catch
			{
			}
		}
		return list;
	}
}
