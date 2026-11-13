using System;
using System.ComponentModel;

namespace Bastos.Native.Models;

public sealed class RufusInstallOptions : INotifyPropertyChanged
{
    private bool useExactRufusExperience;
    private bool useCleanBastosInstallation;
    public bool UseCleanBastosInstallation
    {
        get => useCleanBastosInstallation;
        set
        {
            if (useCleanBastosInstallation == value) return;
            useCleanBastosInstallation = value;
            ApplySimplifiedProfile();
            PropertyChanged?.Invoke(this, new(null));
        }
    }
    public event PropertyChangedEventHandler? PropertyChanged;
    public bool UseExactRufusExperience
    {
        get => useExactRufusExperience;
        set { if (useExactRufusExperience == value) return; useExactRufusExperience = value; if(value) useCleanBastosInstallation = false; PropertyChanged?.Invoke(this, new(null)); }
    }
    public void ApplySimplifiedProfile()
    {
        useExactRufusExperience = false;
        DisableTelemetry = DisableConsumerContent = RemoveOneDrive = RemoveTeams = RemoveOutlook = DisableCopilot = DisableWidgets = useCleanBastosInstallation;
    }
    public int Schema { get; set; } = 1;
    public string UserName { get; set; } = "BastOS";
    public string ComputerName { get; set; } = Environment.MachineName;
    public string WindowsLocale { get; set; } = "fr-FR";
    public string WindowsUILanguage { get; set; } = "";
    public string KeyboardLayout { get; set; } = "040C:0000040C";
    public bool KeepOnlyRecoveryPartition { get; set; } = true;
    public bool BypassHardwareChecks { get; set; }
    public bool PreserveDrivers { get; set; } = true;
    public bool DisableTelemetry { get; set; }
    public bool DisableConsumerContent { get; set; }
    public bool RemoveOneDrive { get; set; }
    public bool RemoveTeams { get; set; }
    public bool RemoveOutlook { get; set; }
    public bool DisableCopilot { get; set; }
    public bool DisableWidgets { get; set; }
    public string RecoveryPartitionGuid { get; set; } = "";
    public string WindowsDiskIdentity { get; set; } = "";
    public string DiskSafetySnapshot { get; set; } = "";
    public int WindowsImageIndex { get; set; }
    public string WindowsEditionId { get; set; } = "";
    public string WindowsImageName { get; set; } = "";
    public string EditionIsoPath { get; set; } = "";
    public string EditionIsoSha256 { get; set; } = "";
}
