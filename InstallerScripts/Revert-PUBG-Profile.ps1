[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Lance ce script depuis Windows PowerShell en tant qu''administrateur.'
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
}

$machineValues = @(
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive', 'DisableFileSyncNGSC'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests'),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'AllowGameDVR'),
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'BASTOS-ISO-FirstLogon')
)
$userValues = @(
    @('HKCU:\Software\Microsoft\GameBar', 'AllowAutoGameMode'),
    @('HKCU:\Software\Microsoft\GameBar', 'AutoGameModeEnabled'),
    @('HKCU:\System\GameConfigStore', 'GameDVR_Enabled'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AppCaptureEnabled'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AudioCaptureEnabled'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'HistoricalCaptureEnabled'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarDa'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarMn'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowTaskViewButton'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'SearchboxTaskbarMode'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled')
)

foreach ($item in $machineValues + $userValues) { Remove-RegValue -Path $item[0] -Name $item[1] }

$contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($name in @(
    'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
    'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled',
    'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
    'SystemPaneSuggestionsEnabled'
)) { Remove-RegValue -Path $contentPath -Name $name }

$gpuPrefs = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (Test-Path $gpuPrefs) {
    Get-ItemProperty $gpuPrefs | ForEach-Object {
        $_.PSObject.Properties | Where-Object { $_.Name -match 'TslGame\.exe$' } | ForEach-Object {
            Remove-ItemProperty -Path $gpuPrefs -Name $_.Name -ErrorAction SilentlyContinue
        }
    }
}

$directXGlobal = Get-ItemPropertyValue -Path $gpuPrefs -Name 'DirectXUserGlobalSettings' -ErrorAction SilentlyContinue
if ($directXGlobal) {
    $remaining = @($directXGlobal -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
    if ($remaining.Count -gt 0) {
        Set-ItemProperty -Path $gpuPrefs -Name 'DirectXUserGlobalSettings' -Value ((($remaining -join ';') + ';'))
    } else {
        Remove-ItemProperty -Path $gpuPrefs -Name 'DirectXUserGlobalSettings' -ErrorAction SilentlyContinue
    }
}
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\DirectX\GraphicsSettings' -Name 'SwapEffectUpgradeCache' -ErrorAction SilentlyContinue

$experimentScript = 'C:\ProgramData\BASTOS-ISO\Set-PUBG-Experiment.ps1'
if (Test-Path -LiteralPath $experimentScript) {
    try {
        & $experimentScript -Mode NicRestore -NoRestart -Quiet
    } catch {
        Write-Warning "Restauration NIC non appliquée : $($_.Exception.Message)"
    }
}

Write-Host 'Les strategies et preferences du profil ont ete retirees.' -ForegroundColor Green
Write-Host 'Les applications retirees de l''image ne sont pas reinstallees automatiquement.'
Write-Host 'Pour OneDrive, utilise l''installateur Microsoft officiel si tu veux le remettre.'
