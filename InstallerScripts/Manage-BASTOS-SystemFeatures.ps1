[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Enable', 'Disable')]
    [string]$Action,
    [ValidateSet('NumLockOnBoot', 'VerboseStatus', 'UtcHardwareClock', 'DisableSmartNameResolution', 'DeveloperMode', 'AllowAllTrustedApps', 'LongPathsEnabled', 'ShowBatteryPercentage', 'RiskUnsafeDownloads')]
    [string]$Option,
    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$features = [ordered]@{
    NumLockOnBoot = @(
        @{ Path = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard'; Name = 'InitialKeyboardIndicators'; Type = 'String'; On = '2'; Off = '0' },
        @{ Path = 'Registry::HKEY_CURRENT_USER\Control Panel\Keyboard'; Name = 'InitialKeyboardIndicators'; Type = 'String'; On = '2'; Off = '0' }
    )
    VerboseStatus = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'VerboseStatus'; Type = 'DWord'; On = 1; Off = 0 })
    UtcHardwareClock = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'; Name = 'RealTimeIsUniversal'; Type = 'DWord'; On = 1; Off = 0 })
    DisableSmartNameResolution = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Name = 'DisableSmartNameResolution'; Type = 'DWord'; On = 1; Off = 0 })
    DeveloperMode = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; Name = 'AllowDevelopmentWithoutDevLicense'; Type = 'DWord'; On = 1; Off = 0 })
    AllowAllTrustedApps = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; Name = 'AllowAllTrustedApps'; Type = 'DWord'; On = 1; Off = 0 })
    LongPathsEnabled = @(@{ Path = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'LongPathsEnabled'; Type = 'DWord'; On = 1; Off = 0 })
    ShowBatteryPercentage = @(@{ Path = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'IsBatteryPercentageEnabled'; Type = 'DWord'; On = 1; Off = 0 })
    RiskUnsafeDownloads = @(
        @{ Path = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3'; Name = '1806'; Type = 'DWord'; On = 0; Off = 3 },
        @{ Path = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3'; Name = '1806'; Type = 'DWord'; On = 0; Off = 3 },
        @{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Internet Explorer\Security'; Name = 'DisableSecuritySettingsCheck'; Type = 'DWord'; On = 1; Off = 0 }
    )
}

function Get-UnsafeDownloadsBackupPath {
    $root = Join-Path $env:ProgramData 'BASTOS\RiskyOptimizationBaselines'
    Join-Path $root 'RiskUnsafeDownloads.json'
}

function Get-RegistrySnapshot {
    param([Parameter(Mandatory = $true)]$Entry)
    try {
        [pscustomobject]@{ Path = $Entry.Path; Name = $Entry.Name; Exists = $true; Value = (Get-ItemPropertyValue -LiteralPath $Entry.Path -Name $Entry.Name -ErrorAction Stop) }
    }
    catch { [pscustomobject]@{ Path = $Entry.Path; Name = $Entry.Name; Exists = $false; Value = $null } }
}

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)
    if ([bool]$Snapshot.Exists) {
        if (-not (Test-Path -LiteralPath $Snapshot.Path)) { New-Item -Path $Snapshot.Path -Force | Out-Null }
        New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -PropertyType DWord -Value ([int]$Snapshot.Value) -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $Snapshot.Path) {
        Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -ErrorAction SilentlyContinue
    }
}

function Set-UnsafeDownloadsEnabled {
    param([Parameter(Mandatory = $true)][bool]$Enabled)
    $backupPath = Get-UnsafeDownloadsBackupPath
    if ($Enabled) {
        if (-not (Test-Path -LiteralPath $backupPath)) {
            $directory = Split-Path -Parent $backupPath
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $backup = [ordered]@{ Registry = @($features.RiskUnsafeDownloads | ForEach-Object { Get-RegistrySnapshot -Entry $_ }) }
            [IO.File]::WriteAllText($backupPath, ($backup | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        }
        Set-FeatureEnabled -Entries $features.RiskUnsafeDownloads -Enabled $true
        return
    }

    if (Test-Path -LiteralPath $backupPath) {
        $backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
        foreach ($snapshot in @($backup.Registry)) { Restore-RegistrySnapshot -Snapshot $snapshot }
        Remove-Item -LiteralPath $backupPath -Force
    }
    else {
        foreach ($entry in $features.RiskUnsafeDownloads) {
            if (Test-Path -LiteralPath $entry.Path) { Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue }
        }
    }
}

function Test-FeatureEnabled {
    param([Parameter(Mandatory = $true)][object[]]$Entries)
    foreach ($entry in $Entries) {
        if (-not (Test-Path -LiteralPath $entry.Path)) { return $false }
        $value = (Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue).($entry.Name)
        if ($null -eq $value -or $value.ToString() -ne $entry.On.ToString()) { return $false }
    }
    return $true
}

function Set-FeatureEnabled {
    param([Parameter(Mandatory = $true)][object[]]$Entries, [Parameter(Mandatory = $true)][bool]$Enabled)
    foreach ($entry in $Entries) {
        if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
        $value = if ($Enabled) { $entry.On } else { $entry.Off }
        New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -PropertyType $entry.Type -Value $value -Force | Out-Null
    }
}

$result = [ordered]@{ Success = $false; Message = ''; States = [ordered]@{} }
try {
    if ($Action -eq 'Get') {
        foreach ($name in $features.Keys) { $result.States[$name] = Test-FeatureEnabled -Entries $features[$name] }
        $result.Success = $true
        $result.Message = 'État des options système lu.'
    }
    else {
        if (-not $features.Contains($Option)) { throw "Option système inconnue : $Option" }
        if ($Option -eq 'RiskUnsafeDownloads') { Set-UnsafeDownloadsEnabled -Enabled ($Action -eq 'Enable') }
        else { Set-FeatureEnabled -Entries $features[$Option] -Enabled ($Action -eq 'Enable') }
        $result.States[$Option] = Test-FeatureEnabled -Entries $features[$Option]
        $result.Success = $true
        $result.Message = if ($Action -eq 'Enable') { 'Option système activée.' } else { 'Option système désactivée.' }
    }
}
catch { $result.Message = $_.Exception.Message }
finally {
    $directory = Split-Path -Parent $ResultPath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}
if (-not $result.Success) { exit 1 }
