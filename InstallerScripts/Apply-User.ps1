[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$removalOptions = [pscustomobject]@{RemoveOneDrive=$true;DisableConsumerContent=$true}
$removalOptionsPath = Join-Path $profileRoot 'BASTOS-Removal-Options.json'
if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
    $removalOptions = Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$logRoot = Join-Path $profileRoot 'Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Start-Transcript -Path (Join-Path $logRoot 'Apply-User.log') -Append | Out-Null
$userMarker = Join-Path $profileRoot 'UserProfileApplied.ok'
$userCoreMarker = Join-Path $profileRoot 'UserProfileCoreApplied.ok'

function Set-DwordValue {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-OptionalDwordValue {
    param([string]$Path, [string]$Name, [int]$Value)
    try {
        Set-DwordValue -Path $Path -Name $Name -Value $Value
    } catch [System.UnauthorizedAccessException] {
        Write-Host "Reglage visuel facultatif ignore par Windows : $Path\$Name" -ForegroundColor DarkYellow
    }
}

function Set-DirectXGlobalSetting {
    param([string]$Name, [string]$Value)
    $path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path -Path $path)) { New-Item -Path $path -Force | Out-Null }
    $current = ''
    try {
        $current = [string](Get-ItemPropertyValue -Path $path -Name 'DirectXUserGlobalSettings' -ErrorAction Stop)
    } catch {
        # Cette valeur n'existe normalement pas encore sur un nouveau profil Windows.
        $current = ''
    }
    $parts = @($current -split ';' | Where-Object { $_ -and $_ -notmatch ('^' + [regex]::Escape($Name) + '=') })
    $newValue = (($parts + "$Name=$Value") -join ';') + ';'
    New-ItemProperty -Path $path -Name 'DirectXUserGlobalSettings' -PropertyType String -Value $newValue -Force | Out-Null
}

function Disable-BastosPointerPrecision {
    $mousePath = 'HKCU:\Control Panel\Mouse'
    if (-not (Test-Path -Path $mousePath)) { New-Item -Path $mousePath -Force | Out-Null }
    foreach ($setting in @(
        @{ Name='MouseSpeed'; Value='0' },
        @{ Name='MouseThreshold1'; Value='0' },
        @{ Name='MouseThreshold2'; Value='0' }
    )) {
        New-ItemProperty -Path $mousePath -Name $setting.Name -PropertyType String -Value $setting.Value -Force | Out-Null
    }

    if (-not ('Bastos.NativeMouseSettings' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Bastos {
    public static class NativeMouseSettings {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SystemParametersInfo(int action, int parameter, int[] values, int flags);
    }
}
'@
    }
    $mouseValues = [int[]](0,0,0)
    if (-not [Bastos.NativeMouseSettings]::SystemParametersInfo(0x0004, 0, $mouseValues, 0x0003)) {
        throw 'Windows n a pas applique immediatement la desactivation de la precision du pointeur.'
    }
}

function Set-BastosWallpaper {
    $wallpaper = Join-Path $profileRoot 'Assets\BASTOS-Wallpaper.jpg'
    if(-not(Test-Path -LiteralPath $wallpaper -PathType Leaf)){Write-Host 'Fond BASTOS absent; reglage ignore.' -ForegroundColor DarkYellow;return}
    $desktopPath = 'HKCU:\Control Panel\Desktop'
    New-ItemProperty -Path $desktopPath -Name Wallpaper -PropertyType String -Value $wallpaper -Force | Out-Null
    New-ItemProperty -Path $desktopPath -Name WallpaperStyle -PropertyType String -Value '10' -Force | Out-Null
    New-ItemProperty -Path $desktopPath -Name TileWallpaper -PropertyType String -Value '0' -Force | Out-Null
    if(-not('Bastos.NativeWallpaper' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
namespace Bastos { public static class NativeWallpaper { [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SystemParametersInfo(int action,int parameter,string value,int flags); } }
'@
    }
    [void][Bastos.NativeWallpaper]::SystemParametersInfo(20,0,$wallpaper,3)
    Write-Host "Fond d ecran BASTOS applique : $wallpaper"
}

try {
    if ((Test-Path -LiteralPath $userMarker -PathType Leaf) -and -not $Force) {
        Write-Host 'Profil utilisateur BASTOS deja applique; seconde execution ignoree.'
        return
    }
    Remove-Item -LiteralPath $userMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $userCoreMarker -Force -ErrorAction SilentlyContinue
    Write-Host 'Application du profil utilisateur PUBG-Stable...'
    Set-BastosWallpaper

    # Game Mode actif. BASTOS ne modifie plus la capture Xbox afin de garder tout l'ecosysteme fonctionnel.
    Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Remove-ItemProperty -LiteralPath 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Force -ErrorAction SilentlyContinue
    foreach ($legacyCaptureValue in @('AppCaptureEnabled','AudioCaptureEnabled','HistoricalCaptureEnabled')) {
        Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name $legacyCaptureValue -Force -ErrorAction SilentlyContinue
    }

    # Active le flip model moderne pour les jeux DX10/DX11 fenêtrés/borderless.
    Set-DirectXGlobalSetting 'SwapEffectUpgradeEnable' '1'
    Set-DwordValue 'HKCU:\Software\Microsoft\DirectX\GraphicsSettings' 'SwapEffectUpgradeCache' 1

    # Nettoie l'interface et les suggestions sans casser Recherche, Store ou WebView2.
    # Ces trois valeurs visuelles peuvent etre protegees sur certaines builds Windows 11.
    # Leur refus ne doit pas annuler les reglages de jeu et de confidentialite deja appliques.
    if ($removalOptions.DisableConsumerContent) {
        Set-OptionalDwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
        Set-OptionalDwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
        Set-OptionalDwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    }
    Disable-BastosPointerPrecision

    if ($removalOptions.DisableConsumerContent) {
        $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        foreach ($name in @(
        'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
        'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled',
        'SoftLandingEnabled', 'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled', 'SystemPaneSuggestionsEnabled'
        )) {
            Set-DwordValue $contentPath $name 0
        }
    }

    if ($removalOptions.RemoveOneDrive) {
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'BASTOS-ISO-FirstLogon' -ErrorAction SilentlyContinue

    # Restaurer le comportement natif du menu Demarrer.
    $startPolicyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    foreach ($startPolicyName in @('ConfigureStartPins','ConfigureStartPinsJSON','HideRecommendedSection','HideRecentlyAddedApps','HideRecommendedPersonalizedSites')) {
        Remove-ItemProperty -LiteralPath $startPolicyPath -Name $startPolicyName -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoStartMenuMorePrograms' -ErrorAction SilentlyContinue

    # Place BASTOS sur le Bureau du premier utilisateur sans lancer automatiquement une application en arriere-plan.
    $launcherRoot = $profileRoot
    $launcher = Join-Path $launcherRoot 'Bastos.Native\BASTOS-Native.exe'
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ((Test-Path -LiteralPath $launcher) -and $desktop) {
        $shortcutPath = Join-Path $desktop 'BASTOS.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $launcher
        $shortcut.WorkingDirectory = $launcherRoot
        $shortcut.Description = 'BASTOS - maintenance, optimisations et pilotes officiels'
        $iconPath = Join-Path $launcherRoot 'Assets\Bastos-App.ico'
        if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
            $shortcut.IconLocation = "$iconPath,0"
        }
        $shortcut.Save()
        Write-Host "Raccourci BASTOS cree sur le Bureau : $shortcutPath"

        # Le raccourci du menu Démarrer est créé une seule fois pour tous les
        # utilisateurs par Apply-Machine.ps1.
    }

    $directXSettings = [string](Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings' -ErrorAction Stop)
    if ($directXSettings -notmatch '(^|;)SwapEffectUpgradeEnable=1;') {
        throw 'La verification du reglage DirectX utilisateur a echoue.'
    }
    foreach ($requiredValue in @(
        @{ Path='HKCU:\Software\Microsoft\GameBar'; Name='AutoGameModeEnabled'; Value=1 },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name='SearchboxTaskbarMode'; Value=0 }
    )) {
        $actual = Get-ItemPropertyValue -Path $requiredValue.Path -Name $requiredValue.Name -ErrorAction Stop
        if ([int]$actual -ne [int]$requiredValue.Value) {
            throw "La verification utilisateur a echoue pour $($requiredValue.Path)\$($requiredValue.Name)."
        }
    }

    foreach ($mouseSetting in @('MouseSpeed','MouseThreshold1','MouseThreshold2')) {
        if ([string](Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Mouse' -Name $mouseSetting -ErrorAction Stop) -ne '0') {
            throw "La verification de la precision du pointeur a echoue pour $mouseSetting."
        }
    }
    New-Item -ItemType File -Path $userCoreMarker -Force | Out-Null
    New-Item -ItemType File -Path $userMarker -Force | Out-Null
    Write-Host 'Profil utilisateur applique. La configuration Internet et logiciels reste manuelle dans BASTOS.'
}
finally {
    Stop-Transcript | Out-Null
}
