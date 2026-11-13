[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Enable', 'Disable', 'Refresh')]
    [string]$Action,
    [ValidateSet('ShowThisPc', 'ShowRecycleBin', 'ShowUserFiles', 'ShowNetwork', 'ShowControlPanel', 'ShowDesktopIcons', 'ShortcutArrow', 'HideStartRecommendations')]
    [string]$Option,
    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$desktopIconsPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
$features = [ordered]@{
    ShowThisPc = @(@{ Path = $desktopIconsPath; Name = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'; Type = 'DWord'; On = 0; Off = 1 })
    ShowRecycleBin = @(@{ Path = $desktopIconsPath; Name = '{645FF040-5081-101B-9F08-00AA002F954E}'; Type = 'DWord'; On = 0; Off = 1 })
    ShowUserFiles = @(@{ Path = $desktopIconsPath; Name = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'; Type = 'DWord'; On = 0; Off = 1 })
    ShowNetwork = @(@{ Path = $desktopIconsPath; Name = '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}'; Type = 'DWord'; On = 0; Off = 1 })
    ShowControlPanel = @(@{ Path = $desktopIconsPath; Name = '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}'; Type = 'DWord'; On = 0; Off = 1 })
    ShowDesktopIcons = @(@{ Path = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideIcons'; Type = 'DWord'; On = 0; Off = 1 })
}
$shortcutPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
$hiddenShortcutValues = @('%windir%\System32\shell32.dll,-50', '%windir%\System32\shell32.dll,50')
$startPolicyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'

function Get-RegistryValue([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).($Name)
}

function Test-FeatureEnabled([object[]]$Entries) {
    foreach ($entry in $Entries) {
        $value = Get-RegistryValue $entry.Path $entry.Name
        if ($null -eq $value -or $value.ToString() -ne $entry.On.ToString()) { return $false }
    }
    return $true
}

function Test-ShortcutArrowVisible {
    $value = Get-RegistryValue $shortcutPath '29'
    if ([string]::IsNullOrWhiteSpace($value)) { return $true }
    if ($hiddenShortcutValues -contains $value) { return $false }
    $fileName = [System.IO.Path]::GetFileName($value)
    return $fileName -notin @('blank.ico', 'transparent.ico', 'blankicon.ico')
}

function Set-FeatureEnabled([object[]]$Entries, [bool]$Enabled) {
    foreach ($entry in $Entries) {
        if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
        $value = if ($Enabled) { $entry.On } else { $entry.Off }
        New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -PropertyType $entry.Type -Value $value -Force | Out-Null
    }
}

function Set-ShortcutArrowVisible([bool]$Visible) {
    if ($Visible) {
        if (Test-Path -LiteralPath $shortcutPath) { Remove-ItemProperty -LiteralPath $shortcutPath -Name '29' -ErrorAction SilentlyContinue }
    }
    else {
        if (-not (Test-Path -LiteralPath $shortcutPath)) { New-Item -Path $shortcutPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $shortcutPath -Name '29' -PropertyType ExpandString -Value $hiddenShortcutValues[0] -Force | Out-Null
    }
}

function Test-StartRecommendationsHidden {
    return (Get-RegistryValue $startPolicyPath 'HideRecommendedSection') -eq 1
}

function Set-StartRecommendationsHidden([bool]$Hidden) {
    if ($Hidden) {
        if (-not (Test-Path -LiteralPath $startPolicyPath)) { New-Item -Path $startPolicyPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $startPolicyPath -Name 'HideRecommendedSection' -PropertyType DWord -Value 1 -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $startPolicyPath) {
        Remove-ItemProperty -LiteralPath $startPolicyPath -Name 'HideRecommendedSection' -ErrorAction SilentlyContinue
    }
}

function Refresh-StartMenu {
    $session = (Get-Process -Id $PID).SessionId
    Get-Process -Name StartMenuExperienceHost -ErrorAction SilentlyContinue |
        Where-Object SessionId -eq $session |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Refresh-DesktopIcons {
    $refreshTool = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $refreshTool) {
        Start-Process -FilePath $refreshTool -ArgumentList '-ClearIconCache' -WindowStyle Hidden -Wait
        Start-Process -FilePath $refreshTool -ArgumentList '-show' -WindowStyle Hidden -Wait
    }
    if (-not ('BastosDesktopRefresh.NativeMethods' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace BastosDesktopRefresh {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
    }
}
'@
    }
    $broadcastResult = [IntPtr]::Zero
    [void][BastosDesktopRefresh.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'ShellState', 0x0002, 5000, [ref]$broadcastResult)
    [BastosDesktopRefresh.NativeMethods]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

$result = [ordered]@{ Success = $false; Message = ''; States = [ordered]@{} }
try {
    if ($Action -eq 'Get') {
        foreach ($name in $features.Keys) { $result.States[$name] = Test-FeatureEnabled $features[$name] }
        $result.States.ShortcutArrow = Test-ShortcutArrowVisible
        $result.States.HideStartRecommendations = Test-StartRecommendationsHidden
        $result.Success = $true
        $result.Message = 'État des options du Bureau lu.'
    }
    elseif ($Action -eq 'Refresh') {
        Refresh-DesktopIcons
        $result.Success = $true
        $result.Message = 'Affichage du Bureau et cache des icônes actualisés.'
    }
    else {
        $enabled = $Action -eq 'Enable'
        if ($Option -eq 'ShortcutArrow') { Set-ShortcutArrowVisible $enabled }
        elseif ($Option -eq 'HideStartRecommendations') { Set-StartRecommendationsHidden $enabled }
        elseif ($features.Contains($Option)) { Set-FeatureEnabled $features[$Option] $enabled }
        else { throw "Option du Bureau inconnue : $Option" }
        if ($Option -eq 'HideStartRecommendations') { Refresh-StartMenu } else { Refresh-DesktopIcons }
        $result.States[$Option] = if ($Option -eq 'ShortcutArrow') {
            Test-ShortcutArrowVisible
        } elseif ($Option -eq 'HideStartRecommendations') {
            Test-StartRecommendationsHidden
        } else {
            Test-FeatureEnabled $features[$Option]
        }
        $result.Success = $true
        $result.Message = if ($Option -eq 'ShowDesktopIcons') {
            if ($enabled) { 'Les éléments du Bureau sont affichés. Réduisez BASTOS pour les voir.' } else { 'Les éléments du Bureau sont masqués. Aucun fichier ni raccourci n''a été supprimé.' }
        } elseif ($Option -eq 'ShortcutArrow') {
            if ($enabled) { 'La petite flèche est affichée sur les raccourcis .lnk.' } else { 'La petite flèche est masquée sur les raccourcis .lnk.' }
        } elseif ($enabled) { 'Option du Bureau activée.' } else { 'Option du Bureau désactivée.' }
    }
}
catch { $result.Message = $_.Exception.Message }
finally {
    $directory = Split-Path -Parent $ResultPath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}
if (-not $result.Success) { exit 1 }
