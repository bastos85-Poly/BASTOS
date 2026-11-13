[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
$hagsStateScript=Join-Path $PSScriptRoot 'Get-BASTOS-HagsState.ps1'
if(Test-Path -LiteralPath $hagsStateScript -PathType Leaf){. $hagsStateScript}

function Get-RegValue([string]$Path, [string]$Name) {
    try { return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop } catch { return $null }
}

$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController)
$cpuName = if ($cpu) { $cpu.Name } else { (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString }
$gpuNames = if ($gpus.Count -gt 0) {
    @($gpus | ForEach-Object { $_.Name })
} else {
    @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -Recurse | Get-ItemProperty | Where-Object DeviceDesc | ForEach-Object { $_.DeviceDesc } | Select-Object -Unique)
}
$hagsState=if(Get-Command Get-BastosHagsState -ErrorAction SilentlyContinue){Get-BastosHagsState}else{$null}
$mpo = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode'
$vbs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity'
$hvci = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
$deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
$vbsActual = if ($deviceGuard) { $deviceGuard.VirtualizationBasedSecurityStatus } else { 'inconnu' }
$gameMode = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
$gameDvr = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
$windowed = Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
$whea = @(Get-WinEvent -FilterHashtable @{ ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-7) })
$displayResets = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Id=4101; StartTime=(Get-Date).AddDays(-7) })

$checks = @(
    [pscustomobject]@{ Element='Windows'; Etat="$($os.DisplayVersion) build $($os.CurrentBuildNumber).$($os.UBR)"; Avis=$(if ($os.DisplayVersion -eq '25H2') {'OK'}else{'MISE À JOUR'}) },
    [pscustomobject]@{ Element='CPU'; Etat=$cpuName; Avis=$(if ($cpuName -match '9800X3D') {'OK'}else{'VÉRIFIER'}) },
    [pscustomobject]@{ Element='GPU'; Etat=($gpuNames -join '; '); Avis=$(if (($gpuNames -join ';') -match '9070 XT') {'OK'}else{'VÉRIFIER'}) },
    [pscustomobject]@{ Element='HAGS'; Etat=$(if($hagsState){[string]$hagsState.Text}else{'État indisponible'}); Avis='A/B seulement' },
    [pscustomobject]@{ Element='MPO'; Etat=$(if($mpo -eq 5){'OFF forcé'}else{'Actif/défaut'}); Avis=$(if($mpo -eq 5){'Seulement si symptôme'}else{'OK'}) },
    [pscustomobject]@{ Element='VBS/HVCI'; Etat="Registre VBS=$vbs, HVCI=$hvci; état réel=$vbsActual"; Avis='Sécurité; A/B facultatif' },
    [pscustomobject]@{ Element='Game Mode'; Etat=$gameMode; Avis=$(if($gameMode -eq 1){'OK'}else{'À ACTIVER'}) },
    [pscustomobject]@{ Element='Capture Xbox / Game DVR'; Etat=$gameDvr; Avis='LAISSÉE AU CHOIX UTILISATEUR' },
    [pscustomobject]@{ Element='Jeux fenêtrés'; Etat=$windowed; Avis=$(if($windowed -match 'SwapEffectUpgradeEnable=1'){'OK'}else{'À ACTIVER'}) },
    [pscustomobject]@{ Element='WHEA 7 jours'; Etat=$whea.Count; Avis=$(if($whea.Count -eq 0){'OK'}else{'INSTABILITÉ À ANALYSER'}) },
    [pscustomobject]@{ Element='Reset GPU 7 jours'; Etat=$displayResets.Count; Avis=$(if($displayResets.Count -eq 0){'OK'}else{'PILOTE/GPU À ANALYSER'}) }
)

$checks | Format-Table -AutoSize -Wrap
Write-Host ''
Write-Host ((& powercfg.exe /getactivescheme) -join ' ')
Write-Host 'Vérifications manuelles : SAM/ReBAR actif dans AMD Software; DX11 Enhanced dans PUBG; Collect GPU Crash Data désactivé.'
Write-Host 'En cas de WHEA : revenir aux valeurs stock, couper EXPO/PBO/Curve Optimizer et retester avant tout tweak Windows.'
