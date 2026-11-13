using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public static class NativeWorkerService
{
	public static async Task<int> ExecuteAsync(string action, string? resultPath)
	{
		NativeActionResult result;
		try
		{
			result = action.ToLowerInvariant() switch
			{
				"memory-standby-clear" => StandbyMemoryService.Clear(),
				"power-install" => PowerPlanService.InstallBundledPlans(),
				var request when request.StartsWith("power-select:", StringComparison.Ordinal) => PowerPlanService.Activate(request.Substring("power-select:".Length)),
                "settings-audit" => new NativeActionResult(true,JsonSerializer.Serialize(new{Performance=new[]{"keyboard","accessibility-hotkeys","background-apps","service-hosts","mmcss-gaming","webdav-limit"}.ToDictionary(id=>id,ReadPerformanceState),Gpu=new[]{"amd-ulps","amd-power-gating","amd-video-gating","amd-aspm","nvidia-dynamic-pstate","nvidia-async-pstate","intel-async-flips","intel-adaptive-vsync"}.Where(id=>new GpuOptimizationService().IsApplicable(id)).ToDictionary(id=>id,id=>new GpuOptimizationService().IsEnabled(id)),Mouse=MouseCurveProfiles.CurrentName()})),
                "engine-self-test" => VerifyPackagedEngine(),
                "self-test" => new NativeActionResult(Success: true, "Worker natif opérationnel."), 
				"hags-on" => SetRegistryDword(Registry.LocalMachine, "SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "HwSchMode", 2, "HAGS sera activé après redémarrage."), 
				"hags-off" => SetRegistryDword(Registry.LocalMachine, "SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "HwSchMode", 1, "HAGS sera désactivé après redémarrage."), 
				"foreground-priority-on" => SetForegroundPriority(enable: true),
				"foreground-priority-restore" => SetForegroundPriority(enable: false),
				var request when request.StartsWith("performance-on:", StringComparison.Ordinal) => SetPerformanceOptimization(request.Substring("performance-on:".Length), enable: true),
				var request when request.StartsWith("performance-restore:", StringComparison.Ordinal) => SetPerformanceOptimization(request.Substring("performance-restore:".Length), enable: false),
				var request when request.StartsWith("gpu-on:", StringComparison.Ordinal) => SetGpuOptimization(request.Substring("gpu-on:".Length), enable: true),
				var request when request.StartsWith("gpu-restore:", StringComparison.Ordinal) => SetGpuOptimization(request.Substring("gpu-restore:".Length), enable: false),
				"mpo-off" => SetRegistryDword(Registry.LocalMachine, "SOFTWARE\\Microsoft\\Windows\\Dwm", "OverlayTestMode", 5, "MPO désactivé. Une reconnexion peut être nécessaire."), 
				"mpo-default" => DeleteRegistryValue(Registry.LocalMachine, "SOFTWARE\\Microsoft\\Windows\\Dwm", "OverlayTestMode", "MPO restauré au comportement Windows."), 
				"power-performance" => PowerPlanService.Activate(PowerPlanService.PerformanceId.ToString("D")),
				"power-balanced" => PowerPlanService.Activate(PowerPlanService.BalancedId.ToString("D")),
				"power-bastos-ultimate" => await ActivateBastosUltimateAsync(), 
				"sfc-verify" => await RunRepairCommand("sfc.exe", resultPath, true, "/verifyonly"),
				"dism-scan" => await RunRepairCommand("dism.exe", resultPath, false, "/Online", "/Cleanup-Image", "/ScanHealth"),
				"repair-sfc" => await RunRepairCommand("sfc.exe", resultPath, true, "/scannow"),
				"repair-dism" => await RunRepairCommand("dism.exe", resultPath, false, "/Online", "/Cleanup-Image", "/RestoreHealth"),
				"repair-dns" => await RunRepairCommand("ipconfig.exe", resultPath, false, "/flushdns"),
				"repair-chkdsk" => OpenChkdskConsole(),
				_ => new NativeActionResult(Success: false, "Commande native inconnue.", 2), 
			};
		}
		catch (Exception ex)
		{
			result = new NativeActionResult(Success: false, ex.Message, 1);
		}
		if (!string.IsNullOrWhiteSpace(resultPath))
		{
			try
			{
				string fullPath = Path.GetFullPath(resultPath);
				Directory.CreateDirectory(Path.GetDirectoryName(fullPath));
				await File.WriteAllTextAsync(fullPath, JsonSerializer.Serialize(result), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
			}
			catch
			{
			}
		}
		return (!result.Success) ? Math.Max(1, result.ExitCode) : 0;
	}

    private static NativeActionResult VerifyPackagedEngine(){using var lease=new WorkerIntegrityService(new AppPaths().Root).Acquire("Manage-BASTOS-SecurityPrivacy.ps1");return new(true,lease.CheckedFiles+" fichiers moteur vérifiés avec le catalogue embarqué.");}

	private static NativeActionResult SetRegistryDword(RegistryKey hive, string path, string name, int value, string message)
	{
		using RegistryKey registryKey = hive.CreateSubKey(path, writable: true) ?? throw new InvalidOperationException("Clé Registre inaccessible.");
		registryKey.SetValue(name, value, RegistryValueKind.DWord);
		return new NativeActionResult(Success: true, message);
	}

	private static NativeActionResult DeleteRegistryValue(RegistryKey hive, string path, string name, string message)
	{
		using RegistryKey registryKey = hive.OpenSubKey(path, writable: true);
		registryKey?.DeleteValue(name, throwOnMissingValue: false);
		return new NativeActionResult(Success: true, message);
	}

	private static NativeActionResult SetForegroundPriority(bool enable)
	{
		const string registryPath = "SYSTEM\\CurrentControlSet\\Control\\PriorityControl";
		const string valueName = "Win32PrioritySeparation";
		const int foregroundValue = 38;
		string stateRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BASTOS-ISO", "State");
		string backupPath = Path.Combine(stateRoot, "Foreground-Priority-Backup-v1.json");

		using RegistryKey key = Registry.LocalMachine.CreateSubKey(registryPath, writable: true) ?? throw new InvalidOperationException("Clé de priorité Windows inaccessible.");
		if (enable)
		{
			if (!File.Exists(backupPath))
			{
				object? original = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
				var backup = new ForegroundPriorityBackup(original != null, original == null ? null : Convert.ToInt32(original), DateTime.UtcNow);
				Directory.CreateDirectory(stateRoot);
				SaveStateDocument(backupPath, JsonSerializer.Serialize(backup));
			}
			key.SetValue(valueName, foregroundValue, RegistryValueKind.DWord);
			if (key.GetValue(valueName) is not int verified || verified != foregroundValue) throw new InvalidOperationException("La priorité des applications actives n’a pas pu être vérifiée.");
			return new NativeActionResult(true, "Applications actives prioritaires — valeur vérifiée : 0x26.");
		}

		if (!File.Exists(backupPath)) return new NativeActionResult(true, "Aucune sauvegarde BASTOS : le réglage Windows actuel est conservé.");
		ForegroundPriorityBackup? saved = JsonSerializer.Deserialize<ForegroundPriorityBackup>(File.ReadAllText(backupPath));
		if (saved == null) throw new InvalidOperationException("Sauvegarde de priorité invalide.");
		if (saved.Existed && saved.DwordValue.HasValue) key.SetValue(valueName, saved.DwordValue.Value, RegistryValueKind.DWord);
		else key.DeleteValue(valueName, throwOnMissingValue: false);
		object? restored = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
		bool valid = saved.Existed ? restored is int number && number == saved.DwordValue : restored == null;
		if (!valid) throw new InvalidOperationException("La restauration de la priorité Windows n’a pas pu être vérifiée.");
		File.Delete(backupPath);
		return new NativeActionResult(true, saved.Existed ? $"Priorité Windows restaurée à 0x{saved.DwordValue:X2}." : "Valeur ajoutée par BASTOS supprimée.");
	}

	private sealed record ForegroundPriorityBackup(bool Existed, int? DwordValue, DateTime SavedUtc);

	private static NativeActionResult SetPerformanceOptimization(string id, bool enable)
	{
		RegistryChange[] changes = BuildPerformanceChanges(id);
		string stateRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BASTOS-ISO", "State");
		string backupPath = Path.Combine(stateRoot, $"Performance-{id}-Backup-v1.json");
		if (enable)
		{
			if (!File.Exists(backupPath))
			{
				var saved = changes.Select(change => ReadRegistryBackup(change)).ToArray();
				Directory.CreateDirectory(stateRoot);
				SaveStateDocument(backupPath, JsonSerializer.Serialize(saved));
			}
			ValidatePerformanceBackup(backupPath,changes);
            if(id=="keyboard")KeyboardRepeatService.Apply(0,31);
			foreach (RegistryChange change in changes) WriteRegistryChange(change);
			if (!changes.All(IsRegistryChangeApplied)) throw new InvalidOperationException("Une ou plusieurs valeurs n’ont pas pu être vérifiées.");
			return new NativeActionResult(true, "Optimisation appliquée et vérifiée. Une reconnexion ou un redémarrage peut être nécessaire.");
		}

		if (!File.Exists(backupPath)) return new NativeActionResult(true, "Aucune sauvegarde BASTOS : les réglages Windows actuels sont conservés.");
		RegistryBackup[]? backups = JsonSerializer.Deserialize<RegistryBackup[]>(File.ReadAllText(backupPath));
		ValidatePerformanceBackup(backupPath,changes);
        if (backups == null) throw new InvalidOperationException("Sauvegarde de réglages invalide.");
		if(id=="keyboard"){
                int delay=int.TryParse(backups.FirstOrDefault(b=>b.Name=="KeyboardDelay")?.Value,out var d)?d:1;
                int speed=int.TryParse(backups.FirstOrDefault(b=>b.Name=="KeyboardSpeed")?.Value,out var v)?v:31;
                KeyboardRepeatService.Apply(delay,speed);
            }
		foreach (RegistryBackup backup in backups) RestoreRegistryBackup(backup);
		File.Delete(backupPath);
		return new NativeActionResult(true, "Valeurs précédentes restaurées exactement.");
	}

    internal static void SaveStateDocument(string path,string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{
            var bytes=new UTF8Encoding(false).GetBytes(content);
            using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None,4096,FileOptions.WriteThrough)){stream.Write(bytes);stream.Flush(true);}
            if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
        }finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
    private static void ValidatePerformanceBackup(string path,RegistryChange[] changes)
    {
        var saved=JsonSerializer.Deserialize<RegistryBackup[]>(File.ReadAllText(path));
        if(saved==null||saved.Length!=changes.Length||!saved.Select(b=>b.Hive+"|"+b.Path+"|"+b.Name).OrderBy(x=>x).SequenceEqual(changes.Select(c=>c.Hive+"|"+c.Path+"|"+c.Name).OrderBy(x=>x)))
            throw new InvalidOperationException("Sauvegarde invalide : aucune modification du profil ne sera effectuée.");
    }
    public sealed record PerformanceState(bool Applied,int Matched,int Total,string Message);
    public static PerformanceState ReadPerformanceState(string id)
    {
        var targets=BuildPerformanceChanges(id);
        int matched=targets.Count(IsRegistryChangeApplied);
        string message=matched==targets.Length?"Appliqué — valeurs Windows vérifiées":matched==0?"Non appliqué — valeurs Windows relues":"Partiellement appliqué — "+matched+"/"+targets.Length+" valeurs conformes";
        if(id=="keyboard")message+=". "+KeyboardRepeatService.Describe();
        return new(matched==targets.Length,matched,targets.Length,message);
    }
    public static string CapturePerformanceValues(string id)=>JsonSerializer.Serialize(BuildPerformanceChanges(id).Select(ReadRegistryBackup).ToArray());

	private static RegistryChange[] BuildPerformanceChanges(string id)
	{
		const string mmcss = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile";
		return id.ToLowerInvariant() switch
		{
			"background-apps" => new[] {
				new RegistryChange("HKCU", "Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications", "GlobalUserDisabled", 1, RegistryValueKind.DWord),
				new RegistryChange("HKCU", "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search", "BackgroundAppGlobalToggle", 0, RegistryValueKind.DWord) },
			"service-hosts" => new[] { new RegistryChange("HKLM", "SYSTEM\\CurrentControlSet\\Control", "SvcHostSplitThresholdInKB", PhysicalMemoryService.TotalKilobytes, RegistryValueKind.DWord) },
			"mmcss-gaming" => new[] {
				new RegistryChange("HKLM", mmcss, "NoLazyMode", 1, RegistryValueKind.DWord), new RegistryChange("HKLM", mmcss, "AlwaysOn", 1, RegistryValueKind.DWord),
				new RegistryChange("HKLM", mmcss, "NetworkThrottlingIndex", -1, RegistryValueKind.DWord), new RegistryChange("HKLM", mmcss, "SystemResponsiveness", 10, RegistryValueKind.DWord),
				new RegistryChange("HKLM", mmcss + "\\Tasks\\Games", "Priority", 2, RegistryValueKind.DWord), new RegistryChange("HKLM", mmcss + "\\Tasks\\Games", "Scheduling Category", "High", RegistryValueKind.String),
				new RegistryChange("HKLM", mmcss + "\\Tasks\\Games", "SFIO Priority", "High", RegistryValueKind.String), new RegistryChange("HKLM", mmcss + "\\Tasks\\Games", "GPU Priority", 8, RegistryValueKind.DWord) },
			"keyboard" => new[] { new RegistryChange("HKCU", "Control Panel\\Keyboard", "KeyboardDelay", "0", RegistryValueKind.String), new RegistryChange("HKCU", "Control Panel\\Keyboard", "KeyboardSpeed", "31", RegistryValueKind.String) },
			"accessibility-hotkeys" => new[] {
				new RegistryChange("HKCU", "Control Panel\\Accessibility\\StickyKeys", "Flags", "26", RegistryValueKind.String),
				new RegistryChange("HKCU", "Control Panel\\Accessibility\\Keyboard Response", "Flags", "2", RegistryValueKind.String),
				new RegistryChange("HKCU", "Control Panel\\Accessibility\\ToggleKeys", "Flags", "34", RegistryValueKind.String) },
			"webdav-limit" => new[] { new RegistryChange("HKLM", "SYSTEM\\CurrentControlSet\\Services\\WebClient\\Parameters", "FileSizeLimitInBytes", -1, RegistryValueKind.DWord) },
			_ => throw new InvalidOperationException("Optimisation Performance.cs inconnue.")
		};
	}

	private static RegistryKey GetHive(string hive) => hive == "HKLM" ? Registry.LocalMachine : Registry.CurrentUser;
	private static RegistryBackup ReadRegistryBackup(RegistryChange change)
	{
		using RegistryKey? key = GetHive(change.Hive).OpenSubKey(change.Path);
		object? value = key?.GetValue(change.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
		return new RegistryBackup(change.Hive, change.Path, change.Name, value != null, value == null ? null : key!.GetValueKind(change.Name).ToString(), value?.ToString());
	}
	private static void WriteRegistryChange(RegistryChange change)
	{
		using RegistryKey key = GetHive(change.Hive).CreateSubKey(change.Path, writable: true) ?? throw new InvalidOperationException("Clé Registre inaccessible.");
		key.SetValue(change.Name, change.Value, change.Kind);
	}
	private static bool IsRegistryChangeApplied(RegistryChange change)
	{
		using RegistryKey? key = GetHive(change.Hive).OpenSubKey(change.Path);
		object? actual = key?.GetValue(change.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
		return actual != null && actual.ToString() == change.Value.ToString();
	}
	private static void RestoreRegistryBackup(RegistryBackup backup)
	{
		using RegistryKey key = GetHive(backup.Hive).CreateSubKey(backup.Path, writable: true) ?? throw new InvalidOperationException("Clé Registre inaccessible.");
		if (!backup.Existed) { key.DeleteValue(backup.Name, throwOnMissingValue: false); return; }
		RegistryValueKind kind = Enum.Parse<RegistryValueKind>(backup.Kind!);
		object value = kind == RegistryValueKind.DWord ? int.Parse(backup.Value!) : backup.Value!;
		key.SetValue(backup.Name, value, kind);
	}

	private sealed record RegistryChange(string Hive, string Path, string Name, object Value, RegistryValueKind Kind);
	private sealed record RegistryBackup(string Hive, string Path, string Name, bool Existed, string? Kind, string? Value);

	private static NativeActionResult SetGpuOptimization(string id, bool enable)
	{
		RegistryChange[] changes = BuildGpuChanges(id);
		if (changes.Length == 0) return new NativeActionResult(false, "Aucune carte graphique compatible détectée.");
		string stateRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BASTOS-ISO", "State");
		string backupPath = Path.Combine(stateRoot, $"Gpu-{id}-Backup-v1.json");
		if (enable)
		{
			if (!File.Exists(backupPath)) { Directory.CreateDirectory(stateRoot); SaveStateDocument(backupPath, JsonSerializer.Serialize(changes.Select(ReadRegistryBackup).ToArray())); }
			foreach (RegistryChange change in changes) WriteRegistryChange(change);
			if (!changes.All(IsRegistryChangeApplied)) throw new InvalidOperationException("Le réglage GPU n’a pas pu être vérifié.");
			return new NativeActionResult(true, "Réglage GPU appliqué et vérifié. Redémarrage recommandé.");
		}
		if (!File.Exists(backupPath)) return new NativeActionResult(true, "Aucune sauvegarde BASTOS : réglages actuels conservés.");
		RegistryBackup[] backups = JsonSerializer.Deserialize<RegistryBackup[]>(File.ReadAllText(backupPath)) ?? throw new InvalidOperationException("Sauvegarde GPU invalide.");
		foreach (RegistryBackup backup in backups) RestoreRegistryBackup(backup);
		File.Delete(backupPath);
		return new NativeActionResult(true, "Réglages GPU précédents restaurés.");
	}

	private static RegistryChange[] BuildGpuChanges(string id)
	{
		(string vendor, (string Name, int Value)[] values) = id.ToLowerInvariant() switch
		{
			"amd-ulps" => ("amd", new[] { ("EnableULPS", 0) }),
			"amd-power-gating" => ("amd", new[] { ("DisablePowerGating", 1), ("PP_GPUPowerDownEnabled", 0), ("DisableDynamicPstate", 1) }),
			"amd-video-gating" => ("amd", new[] { ("DisableVCEPowerGating", 1), ("DisableVceClockGating", 1), ("EnableUvdClockGating", 0), ("EnableVceSwClockGating", 0) }),
			"amd-aspm" => ("amd", new[] { ("EnableAspmL0s", 0), ("EnableAspmL1", 0) }),
			"nvidia-dynamic-pstate" => ("nvidia", new[] { ("DisableDynamicPstate", 1) }),
			"nvidia-async-pstate" => ("nvidia", new[] { ("DisableASyncPstates", 1) }),
			"intel-async-flips" => ("intel", new[] { ("Display1_DisableAsyncFlips", 1) }),
			"intel-adaptive-vsync" => ("intel", new[] { ("AdaptiveVsyncEnable", 0) }),
			_ => throw new InvalidOperationException("Optimisation GPU inconnue.")
		};
		const string rootPath = "SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}";
		using RegistryKey root = Registry.LocalMachine.OpenSubKey(rootPath) ?? throw new InvalidOperationException("Classe des cartes graphiques inaccessible.");
		var result = new System.Collections.Generic.List<RegistryChange>();
		foreach (string subName in root.GetSubKeyNames().Where(name => name.Length == 4 && name.All(char.IsDigit)))
		{
			using RegistryKey? key = root.OpenSubKey(subName);
			string identity = string.Join(" ", key?.GetValue("DriverDesc"), key?.GetValue("ProviderName"), key?.GetValue("MatchingDeviceId")).ToLowerInvariant();
			bool match = vendor == "amd" ? identity.Contains("amd") || identity.Contains("advanced micro") || identity.Contains("ven_1002") : vendor == "nvidia" ? identity.Contains("nvidia") || identity.Contains("ven_10de") : identity.Contains("intel") || identity.Contains("ven_8086");
			if (match) result.AddRange(values.Select(value => new RegistryChange("HKLM", rootPath + "\\" + subName, value.Name, value.Value, RegistryValueKind.DWord)));
		}
		return result.ToArray();
	}

	private static async Task<NativeActionResult> RunSystemCommand(string file, params string[] arguments)
	{
		var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), file);
		CommandResult commandResult = await new ProcessExecutionService().RunAsync(executable, arguments, elevate: false, 110);
		string text = string.Join(Environment.NewLine, new string[2] { commandResult.Output, commandResult.Error }.Where((string value) => !string.IsNullOrWhiteSpace(value))).Trim();
		return new NativeActionResult(commandResult.Success, (!string.IsNullOrWhiteSpace(text)) ? text : (commandResult.Success ? "Opération terminée." : "Échec de l’opération."), commandResult.ExitCode);
	}

	private static Task<NativeActionResult> RunRepairCommand(string file, string? resultPath, bool unicodeOutput, params string[] arguments) =>
		RepairCommandRunner.RunAsync(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), file), arguments, unicodeOutput,
			string.IsNullOrWhiteSpace(resultPath) ? null : resultPath + ".progress");

	private static NativeActionResult OpenChkdskConsole()
	{
		var drive = Path.GetPathRoot(Environment.SystemDirectory)?.TrimEnd('\\');
		if (drive == null || drive.Length != 2 || !char.IsAsciiLetter(drive[0]) || drive[1] != ':')
			return new NativeActionResult(false, "Lecteur Windows introuvable. Aucune commande lancée.", 1);
		var start = new System.Diagnostics.ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"))
		{
			UseShellExecute = false,
			CreateNoWindow = false,
			WindowStyle = System.Diagnostics.ProcessWindowStyle.Normal
		};
		start.ArgumentList.Add("/k");
		start.ArgumentList.Add("chkdsk " + drive + " /f");
		using var process = System.Diagnostics.Process.Start(start) ?? throw new InvalidOperationException("La console de vérification n’a pas démarré.");
		return new NativeActionResult(true, "Console CHKDSK ouverte. Si Windows le demande, accepte la vérification au prochain redémarrage dans cette console. Résultat de réparation non encore connu.");
	}

	private static async Task<NativeActionResult> ActivateBastosUltimateAsync()
	{
		NativeActionResult nativeActionResult = await RunSystemCommand("powercfg.exe", "/list");
		if (!nativeActionResult.Success)
		{
			return nativeActionResult;
		}
		if (!nativeActionResult.Message.Contains("01001011-0100-1111-0101-001188888883", StringComparison.OrdinalIgnoreCase))
		{
			NativeActionResult nativeActionResult2 = await RunSystemCommand("powercfg.exe", "/duplicatescheme", "e9a42b02-d5df-448d-aa00-03f14749eb61", "01001011-0100-1111-0101-001188888883");
			if (!nativeActionResult2.Success)
			{
				return nativeActionResult2;
			}
			NativeActionResult nativeActionResult3 = await RunSystemCommand("powercfg.exe", "/changename", "01001011-0100-1111-0101-001188888883", "Ultimate Performance", "Profil actif BASTOS reproduit depuis le modèle Windows Ultimate Performance.");
			if (!nativeActionResult3.Success)
			{
				return nativeActionResult3;
			}
		}
		NativeActionResult nativeActionResult4 = await RunSystemCommand("powercfg.exe", "/setactive", "01001011-0100-1111-0101-001188888883");
		return nativeActionResult4.Success ? new NativeActionResult(Success: true, "Plan Ultimate Performance de cet OS activé.") : nativeActionResult4;
	}
}
