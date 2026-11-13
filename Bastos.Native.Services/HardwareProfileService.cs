using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Text.Json;
using System.Threading.Tasks;
using Bastos.Native.Models;
using Microsoft.Win32;

namespace Bastos.Native.Services;

public sealed class HardwareProfileService
{
    private const int CurrentVersion = 1;
    private readonly string cachePath;
    private readonly Func<Task<HardwareProfile>> detector;
    private readonly object detectionGate = new();
    private Task<(HardwareProfile Profile, bool FromCache)>? activeDetection;

    public string CachePath => cachePath;

    public HardwareProfileService(AppPaths paths)
        : this(Path.Combine(paths.StateRoot, "Hardware-Profile-v1.json"), DetectAsync)
    {
    }

    public HardwareProfileService(string path, Func<Task<HardwareProfile>> detector)
    {
        cachePath = path;
        this.detector = detector;
    }

    public HardwareProfile? Load()
    {
        try
        {
            if (!File.Exists(cachePath)) return null;
            HardwareProfile? profile = JsonSerializer.Deserialize<HardwareProfile>(File.ReadAllText(cachePath));
            if (profile is not { Version: CurrentVersion } || !IsUsable(profile)) return null;
            TrimFields(profile);
            return profile;
        }
        catch
        {
            return null;
        }
    }

    public Task<(HardwareProfile Profile, bool FromCache)> GetOrDetectAsync()
    {
        lock(detectionGate)
        {
            if(activeDetection is { IsCompleted:false })return activeDetection;
            return activeDetection=Task.Run(DetectOrLoadAsync);
        }
    }

    private async Task<(HardwareProfile Profile, bool FromCache)> DetectOrLoadAsync()
    {
        HardwareProfile? cached = Load();
        if (cached != null)
        {
            // Le pilote d'affichage peut être remplacé après la première détection
            // (pilote générique Microsoft, puis pilote AMD/NVIDIA/Intel). Le profil
            // reste instantanément disponible depuis le cache, mais son nom GPU est
            // revalidé en arrière-plan à chaque démarrage.
            try
            {
                HardwareProfile live = await detector();
                Normalize(live);
                bool gpuNameChanged = IsSpecificGpuName(live.GpuName) &&
                    !string.Equals(cached.GpuName, live.GpuName, StringComparison.OrdinalIgnoreCase);
                bool inventoryChanged = live.GpuDeviceIds != null &&
                    (cached.GpuDeviceIds == null || !cached.GpuDeviceIds.SequenceEqual(live.GpuDeviceIds, StringComparer.OrdinalIgnoreCase));
                if (gpuNameChanged || inventoryChanged)
                {
                    if (gpuNameChanged) cached.GpuName = live.GpuName;
                    if (live.GpuDeviceIds != null) cached.GpuDeviceIds = live.GpuDeviceIds;
                    cached.DetectedUtc = DateTime.UtcNow;
                    Normalize(cached);
                    Save(cached);
                    return (cached, false);
                }
            }
            catch
            {
                // Une détection momentanément indisponible ne doit pas invalider le cache.
            }
            return (cached, true);
        }

        HardwareProfile detected;
        try
        {
            detected = await detector();
        }
        catch
        {
            detected = CreateFallback();
        }
        Normalize(detected);
        Save(detected);
        return (detected, false);
    }

    private void Save(HardwareProfile profile)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        string temporary = cachePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(profile, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, cachePath, true);
    }

    private static async Task<HardwareProfile> DetectAsync()
    {
        HardwareProfile fallback = CreateFallback();
        string powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) return fallback;

        const string command = "$ErrorActionPreference='SilentlyContinue';" +
            "$cpu=(Get-CimInstance Win32_Processor|Select-Object -First 1 -ExpandProperty Name);" +
            "$video=@(Get-CimInstance Win32_VideoController -ErrorAction Stop|Where-Object {$_.ConfigManagerErrorCode -ne 45});" +
            "$gpu=($video|Where-Object {$_.Name -notmatch 'Basic Display|Microsoft.*base|Carte vid.o de base'}|Sort-Object AdapterRAM -Descending|Select-Object -First 1 -ExpandProperty Name);" +
            "$gpuIds=@($video|ForEach-Object {$_.PNPDeviceID}|Where-Object {$_}|Sort-Object -Unique);" +
            "$ram=@(Get-CimInstance Win32_PhysicalMemory);$bytes=($ram|Measure-Object Capacity -Sum).Sum;$speed=($ram|Measure-Object ConfiguredClockSpeed -Maximum).Maximum;$t=($ram|Select-Object -First 1 -ExpandProperty SMBIOSMemoryType);$kind=switch($t){34{'DDR5'}26{'DDR4'}24{'DDR3'}default{'RAM'}};$memory=if($bytes){('{0:0.#} Go {1}{2}' -f ($bytes/1GB),$kind,$(if($speed){'-'+$speed}else{''}))}else{'Mémoire vive'};" +
            "$disk=(Get-CimInstance Win32_DiskDrive|Sort-Object Index|Select-Object -First 1 -ExpandProperty Model);" +
            "$net=(Get-CimInstance Win32_NetworkAdapter|Where-Object {$_.PhysicalAdapter -and $_.NetEnabled}|Select-Object -First 1 -ExpandProperty Name);" +
            "[ordered]@{CpuName=$cpu;MemoryName=$memory;GpuName=$gpu;GpuDeviceIds=$gpuIds;DiskName=$disk;NetworkName=$net}|ConvertTo-Json -Compress";

        using Process process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = powershell,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };
        process.StartInfo.ArgumentList.Add("-NoProfile");
        process.StartInfo.ArgumentList.Add("-NonInteractive");
        process.StartInfo.ArgumentList.Add("-ExecutionPolicy");
        process.StartInfo.ArgumentList.Add("Bypass");
        process.StartInfo.ArgumentList.Add("-Command");
        process.StartInfo.ArgumentList.Add(command);
        process.Start();
        Task<string> outputTask = process.StandardOutput.ReadToEndAsync();
        try
        {
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
        }
        catch (TimeoutException)
        {
            process.Kill(true);
            return fallback;
        }
        string output = await outputTask;
        if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output)) return fallback;

        HardwareProfile? profile = JsonSerializer.Deserialize<HardwareProfile>(output, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (profile == null) return fallback;
        profile.Version = CurrentVersion;
        profile.DetectedUtc = DateTime.UtcNow;
        FillMissing(profile, fallback);
        return profile;
    }

    private static HardwareProfile CreateFallback()
    {
        string cpu = "Processeur";
        try { cpu = Registry.GetValue("HKEY_LOCAL_MACHINE\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", "ProcessorNameString", cpu)?.ToString()?.Trim() ?? cpu; } catch { }
        string network = "Carte réseau";
        try { network = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(item => item.OperationalStatus == OperationalStatus.Up && item.NetworkInterfaceType != NetworkInterfaceType.Loopback)?.Description ?? network; } catch { }
        return new HardwareProfile { CpuName = cpu, NetworkName = network };
    }

    private static bool IsUsable(HardwareProfile profile) =>
        !string.IsNullOrWhiteSpace(profile.CpuName) && !string.IsNullOrWhiteSpace(profile.MemoryName) &&
        !string.IsNullOrWhiteSpace(profile.GpuName) && !string.IsNullOrWhiteSpace(profile.DiskName) &&
        !string.IsNullOrWhiteSpace(profile.NetworkName);

    private static bool IsSpecificGpuName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        string value = name.Trim();
        return !value.Equals("Carte graphique", StringComparison.OrdinalIgnoreCase) &&
               !value.Contains("Basic Display", StringComparison.OrdinalIgnoreCase) &&
               !value.Contains("de base Microsoft", StringComparison.OrdinalIgnoreCase);
    }

    private static void FillMissing(HardwareProfile profile, HardwareProfile fallback)
    {
        if (string.IsNullOrWhiteSpace(profile.CpuName)) profile.CpuName = fallback.CpuName;
        if (string.IsNullOrWhiteSpace(profile.MemoryName)) profile.MemoryName = fallback.MemoryName;
        if (string.IsNullOrWhiteSpace(profile.GpuName)) profile.GpuName = fallback.GpuName;
        if (string.IsNullOrWhiteSpace(profile.DiskName)) profile.DiskName = fallback.DiskName;
        if (string.IsNullOrWhiteSpace(profile.NetworkName)) profile.NetworkName = fallback.NetworkName;
    }

    private static void Normalize(HardwareProfile profile)
    {
        profile.Version = CurrentVersion;
        if (profile.DetectedUtc == default) profile.DetectedUtc = DateTime.UtcNow;
        FillMissing(profile, CreateFallback());
        TrimFields(profile);
    }

    private static void TrimFields(HardwareProfile profile)
    {
        profile.CpuName = profile.CpuName.Trim();
        profile.MemoryName = profile.MemoryName.Trim();
        profile.GpuName = profile.GpuName.Trim();
        profile.DiskName = profile.DiskName.Trim();
        profile.NetworkName = profile.NetworkName.Trim();
    }
}
