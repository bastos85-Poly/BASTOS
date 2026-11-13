using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class GpuOptimizationService
{
    public static string[] DetectVendors(IEnumerable<string>? deviceIds) => (deviceIds ?? Array.Empty<string>())
        .Select(id => System.Text.RegularExpressions.Regex.Match(id ?? "", @"^PCI\\VEN_(1002|10DE|8086)&", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
        .Where(match => match.Success)
        .Select(match => match.Groups[1].Value.ToUpperInvariant() switch { "1002" => "amd", "10DE" => "nvidia", _ => "intel" })
        .Distinct().OrderBy(vendor => vendor).ToArray();

    public static bool IsVisibleForVendors(string id, IEnumerable<string> vendors) =>
        vendors.Any(vendor => id.StartsWith(vendor + "-", StringComparison.Ordinal));

	public bool IsApplicable(string id) => GetTargets(id).Count > 0;
	public bool IsEnabled(string id)
	{
		List<Target> targets = GetTargets(id);
		return targets.Count > 0 && targets.All(target => ReadDword(target.Path, target.Name) == target.Value);
	}

	private static List<Target> GetTargets(string id)
	{
		(string vendor, (string Name, int Value)[] values) = id switch
		{
			"amd-ulps" => ("amd", new[] { ("EnableULPS", 0) }),
			"amd-power-gating" => ("amd", new[] { ("DisablePowerGating", 1), ("PP_GPUPowerDownEnabled", 0), ("DisableDynamicPstate", 1) }),
			"amd-video-gating" => ("amd", new[] { ("DisableVCEPowerGating", 1), ("DisableVceClockGating", 1), ("EnableUvdClockGating", 0), ("EnableVceSwClockGating", 0) }),
			"amd-aspm" => ("amd", new[] { ("EnableAspmL0s", 0), ("EnableAspmL1", 0) }),
			"nvidia-dynamic-pstate" => ("nvidia", new[] { ("DisableDynamicPstate", 1) }),
			"nvidia-async-pstate" => ("nvidia", new[] { ("DisableASyncPstates", 1) }),
			"intel-async-flips" => ("intel", new[] { ("Display1_DisableAsyncFlips", 1) }),
			"intel-adaptive-vsync" => ("intel", new[] { ("AdaptiveVsyncEnable", 0) }),
			_ => ("", Array.Empty<(string, int)>())
		};
		const string rootPath = "SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}";
		using RegistryKey? root = Registry.LocalMachine.OpenSubKey(rootPath);
		var result = new List<Target>();
		foreach (string subName in root?.GetSubKeyNames().Where(name => name.Length == 4 && name.All(char.IsDigit)) ?? Array.Empty<string>())
		{
			using RegistryKey? key = root!.OpenSubKey(subName);
			string identity = string.Join(" ", key?.GetValue("DriverDesc"), key?.GetValue("ProviderName"), key?.GetValue("MatchingDeviceId")).ToLowerInvariant();
			bool match = vendor == "amd" ? identity.Contains("amd") || identity.Contains("advanced micro") || identity.Contains("ven_1002") : vendor == "nvidia" ? identity.Contains("nvidia") || identity.Contains("ven_10de") : vendor == "intel" && (identity.Contains("intel") || identity.Contains("ven_8086"));
			if (match) result.AddRange(values.Select(value => new Target(rootPath + "\\" + subName, value.Name, value.Value)));
		}
		return result;
	}
	private static int? ReadDword(string path, string name) { using RegistryKey? key = Registry.LocalMachine.OpenSubKey(path); return key?.GetValue(name) is int value ? value : null; }
	private sealed record Target(string Path, string Name, int Value);
}
