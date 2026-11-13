using System;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class WindowsTuningService(OperationLogService log)
{
	public const string BastosUltimateScheme = "01001011-0100-1111-0101-001188888883";

	private const string Bastos9800X3DName = "BASTOS 9800X3D Gaming";

	public bool GameModeEnabled => ReadDword(Registry.CurrentUser, "Software\\Microsoft\\GameBar", "AutoGameModeEnabled") == 1;

	public int? ForegroundPriorityValue => ReadDword(Registry.LocalMachine, "SYSTEM\\CurrentControlSet\\Control\\PriorityControl", "Win32PrioritySeparation");

	public bool ForegroundPriorityEnabled => ForegroundPriorityValue == 38;

	public bool FullscreenOptimizationsEnabled =>
		ReadDword(Registry.CurrentUser, "System\\GameConfigStore", "GameDVR_DXGIHonorFSEWindowsCompatible") is null or 0 &&
		ReadDword(Registry.CurrentUser, "System\\GameConfigStore", "GameDVR_FSEBehavior") is null or 0 &&
		ReadDword(Registry.CurrentUser, "System\\GameConfigStore", "GameDVR_FSEBehaviorMode") is null or 0 &&
		ReadDword(Registry.CurrentUser, "System\\GameConfigStore", "GameDVR_HonorUserFSEBehaviorMode") is null or 0;

	public bool IsPerformanceOptimizationEnabled(string id)
	{
        return NativeWorkerService.ReadPerformanceState(id).Applied;
	}

	public bool MpoDisabled => ReadDword(Registry.LocalMachine, "SOFTWARE\\Microsoft\\Windows\\Dwm", "OverlayTestMode") == 5;

	public bool BastosUltimatePowerSelected => string.Equals(ReadActivePowerScheme(), "01001011-0100-1111-0101-001188888883", StringComparison.OrdinalIgnoreCase);

	public bool Bastos9800X3DPowerSelected => string.Equals(ReadActivePowerSchemeName(), "BASTOS 9800X3D Gaming", StringComparison.OrdinalIgnoreCase);

	public string PowerPlanState
	{
		get
		{
			if (!BastosUltimatePowerSelected)
			{
				if (!Bastos9800X3DPowerSelected)
				{
					return "Autre plan actif : " + (ReadActivePowerSchemeName() ?? "nom inconnu");
				}
				return "BASTOS 9800X3D Gaming — actif";
			}
			return "Ultimate Performance — actif sur cet OS";
		}
	}

	public string SetGameMode(bool enabled)
	{
		using RegistryKey registryKey = Registry.CurrentUser.CreateSubKey("Software\\Microsoft\\GameBar");
		registryKey.SetValue("AutoGameModeEnabled", enabled ? 1 : 0, RegistryValueKind.DWord);
		registryKey.SetValue("AllowAutoGameMode", enabled ? 1 : 0, RegistryValueKind.DWord);
		string text = "Mode Jeu " + (enabled ? "activé" : "désactivé") + ".";
		log.Write("Optimisations", text);
		return text;
	}

	private static int? ReadDword(RegistryKey hive, string path, string name)
	{
		using RegistryKey registryKey = hive.OpenSubKey(path);
		return (registryKey?.GetValue(name) is int value) ? new int?(value) : ((int?)null);
	}

	public string SetFullscreenOptimizations(bool enabled)
	{
		using RegistryKey key = Registry.CurrentUser.CreateSubKey("System\\GameConfigStore") ?? throw new InvalidOperationException("GameConfigStore inaccessible.");
		key.SetValue("GameDVR_DXGIHonorFSEWindowsCompatible", enabled ? 0 : 1, RegistryValueKind.DWord);
		key.SetValue("GameDVR_FSEBehavior", enabled ? 0 : 2, RegistryValueKind.DWord);
		key.SetValue("GameDVR_FSEBehaviorMode", enabled ? 0 : 2, RegistryValueKind.DWord);
		key.SetValue("GameDVR_HonorUserFSEBehaviorMode", enabled ? 0 : 1, RegistryValueKind.DWord);
		if (FullscreenOptimizationsEnabled != enabled) throw new InvalidOperationException("Le réglage plein écran n’a pas pu être vérifié.");
		string message = enabled ? "Optimisations plein écran activées." : "Optimisations plein écran désactivées.";
		log.Write("Optimisations", message);
		return message;
	}

	private static bool DwordEquals(RegistryKey hive, string path, string name, int expected) => ReadDword(hive, path, name) == expected;

	private static bool StringEquals(RegistryKey hive, string path, string name, string expected)
	{
		using RegistryKey? key = hive.OpenSubKey(path);
		return string.Equals(key?.GetValue(name)?.ToString(), expected, StringComparison.Ordinal);
	}

	private static string? ReadActivePowerScheme()
	{
		using RegistryKey registryKey = Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Power\\User\\PowerSchemes");
		return registryKey?.GetValue("ActivePowerScheme")?.ToString();
	}

	private static string? ReadActivePowerSchemeName()
	{
		string text = ReadActivePowerScheme();
		if (string.IsNullOrWhiteSpace(text))
		{
			return null;
		}
		using RegistryKey registryKey = Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Power\\User\\PowerSchemes\\" + text);
		string text2 = registryKey?.GetValue("FriendlyName")?.ToString();
		if (string.IsNullOrWhiteSpace(text2))
		{
			return null;
		}
		int num = text2.LastIndexOf(',');
		string result;
		if (!text2.StartsWith('@') || num < 0 || num + 1 >= text2.Length)
		{
			result = text2;
		}
		else
		{
			string text3 = text2;
			int num2 = num + 1;
			result = text3.Substring(num2, text3.Length - num2);
		}
		return result;
	}
}
