[CmdletBinding()]
param(
    [ValidateSet(
        'Status',
        'HagsOn', 'HagsOff', 'HagsDefault',
        'MpoOff', 'MpoOn',
        'NicStable', 'NicLowLatency', 'NicRestore',
        'PowerBalanced', 'PowerHigh', 'PowerBastosUltimate', 'Power9800X3D',
        'CoreParkingOn', 'CoreParkingRestore',
        'VbsOff', 'VbsOn',
        'GameModeOn', 'GameModeOff', 'GameModeDefault',
        'GameDvrOff', 'GameDvrOn',
        'TransparencyOff', 'TransparencyOn'
    )]
    [string]$Mode = 'Status',

    [switch]$ConfirmSecurityRisk,
    [switch]$NoRestart,
    [switch]$Quiet,
    [string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hagsStateScript=Join-Path $PSScriptRoot 'Get-BASTOS-HagsState.ps1'
if(Test-Path -LiteralPath $hagsStateScript -PathType Leaf){. $hagsStateScript}
$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$backupRoot = Join-Path $profileRoot 'Backups'
$nicBackup = Join-Path $backupRoot 'Realtek-NIC-Original.json'
$coreParkingBackup = Join-Path $backupRoot 'CoreParkingMin-Original.json'
$power9800X3DName = 'BASTOS 9800X3D Gaming'
$bastosUltimateGuid = '01001011-0100-1111-0101-001188888883'
$processorSubgroupGuid = '54533251-82be-4824-96c1-47b60b740d00'
$coreParkingMinGuid = '0cc5b647-c1df-4637-891a-dec35c318583'

function Write-OperationResult {
    param([bool]$Success, [string]$Message)
    if ([string]::IsNullOrWhiteSpace($ResultPath)) { return }
    $parent = Split-Path -Parent $ResultPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [pscustomobject]@{
        Success = $Success
        Message = $Message
    } | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}

trap {
    $failureMessage = $_.Exception.Message
    try { Write-OperationResult -Success $false -Message $failureMessage } catch {}
    Write-Error $failureMessage
    exit 1
}

function Write-Info([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-Administrator)) {
        throw 'Lance Windows PowerShell en tant qu''administrateur.'
    }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop } catch { return $null }
}

function Set-DwordValue {
    param([string]$Path, [string]$Name, [int]$Value)
    # Ne jamais recreer de force une cle existante : le provider Registre de
    # Windows PowerShell 5.1 peut tenter de la remplacer et echouer sur ses sous-cles.
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Remove-RegValueIfPresent {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -Path $Path)) { return }
    $key = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($key -and @($key.GetValueNames()) -contains $Name) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    }
}

function Invoke-PowerCfgChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& powercfg.exe @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg $($Arguments -join ' ') a echoue : $($output -join ' ')"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-PowerSchemeGuidByName {
    param([Parameter(Mandatory)][string]$Name)
    foreach ($line in @(& powercfg.exe /list 2>$null)) {
        if ([string]$line -notlike "*$Name*") { continue }
        $match = [regex]::Match([string]$line, '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b')
        if ($match.Success) { return $match.Value }
    }
    return $null
}

function Get-ActivePowerSchemeGuid {
    $output = @(& powercfg.exe /getactivescheme 2>$null) -join ' '
    $match = [regex]::Match($output, '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b')
    if (-not $match.Success) { throw 'Le plan alimentation actif ne fournit aucun GUID exploitable.' }
    return $match.Value.ToLowerInvariant()
}

function Get-CoreParkingMinValues {
    param([Parameter(Mandatory)][string]$SchemeGuid)
    $output = Invoke-PowerCfgChecked -Arguments @('/qh',$SchemeGuid,$processorSubgroupGuid,$coreParkingMinGuid)
    $hexValues = @([regex]::Matches(($output -join [Environment]::NewLine), '(?i)0x[0-9a-f]+') | ForEach-Object {
        [Convert]::ToUInt32($_.Value.Substring(2),16)
    })
    if ($hexValues.Count -lt 2) { throw 'Windows ne fournit pas les valeurs AC/DC de CPMINCORES.' }
    return [pscustomobject]@{
        Ac = [int]$hexValues[$hexValues.Count - 2]
        Dc = [int]$hexValues[$hexValues.Count - 1]
    }
}

function Enable-CoreParking {
    $schemeGuid = Get-ActivePowerSchemeGuid
    $values = Get-CoreParkingMinValues -SchemeGuid $schemeGuid
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    if (Test-Path -LiteralPath $coreParkingBackup -PathType Leaf) {
        $existing = Get-Content -LiteralPath $coreParkingBackup -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$existing.SchemeGuid -ne $schemeGuid) {
            throw 'Une sauvegarde du parking CPU existe deja pour un autre plan. Clique d abord sur Restaurer.'
        }
    } else {
        [pscustomobject]@{
            Version = 1
            SchemeGuid = $schemeGuid
            Ac = $values.Ac
            Dc = $values.Dc
            SavedUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $coreParkingBackup -Encoding UTF8
    }

    [void](Invoke-PowerCfgChecked -Arguments @('/setacvalueindex',$schemeGuid,$processorSubgroupGuid,$coreParkingMinGuid,'100'))
    [void](Invoke-PowerCfgChecked -Arguments @('/setdcvalueindex',$schemeGuid,$processorSubgroupGuid,$coreParkingMinGuid,'100'))
    $verified = Get-CoreParkingMinValues -SchemeGuid $schemeGuid
    if ($verified.Ac -ne 100 -or $verified.Dc -ne 100) {
        throw "Le mode sans parking n a pas ete applique correctement (AC=$($verified.Ac), DC=$($verified.Dc))."
    }
    Write-Info "Mode sans parking actif sur le plan $schemeGuid : CPMINCORES AC=100, DC=100. Les valeurs precedentes sont sauvegardees."
}

function Restore-CoreParking {
    if (-not (Test-Path -LiteralPath $coreParkingBackup -PathType Leaf)) {
        throw 'Aucune sauvegarde de parking CPU BASTOS a restaurer.'
    }
    $backup = Get-Content -LiteralPath $coreParkingBackup -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemeGuid = [string]$backup.SchemeGuid
    $availableSchemes = @(& powercfg.exe /list 2>$null) -join ' '
    if ($availableSchemes -notmatch [regex]::Escape($schemeGuid)) {
        throw "Le plan alimentation sauvegarde n existe plus : $schemeGuid"
    }

    [void](Invoke-PowerCfgChecked -Arguments @('/setacvalueindex',$schemeGuid,$processorSubgroupGuid,$coreParkingMinGuid,[string][int]$backup.Ac))
    [void](Invoke-PowerCfgChecked -Arguments @('/setdcvalueindex',$schemeGuid,$processorSubgroupGuid,$coreParkingMinGuid,[string][int]$backup.Dc))
    [void](Invoke-PowerCfgChecked -Arguments @('/setactive',$schemeGuid))
    $verified = Get-CoreParkingMinValues -SchemeGuid $schemeGuid
    if ($verified.Ac -ne [int]$backup.Ac -or $verified.Dc -ne [int]$backup.Dc) {
        throw "La restauration du parking CPU n a pas ete verifiee (AC=$($verified.Ac), DC=$($verified.Dc))."
    }
    Remove-Item -LiteralPath $coreParkingBackup -Force
    Write-Info "Parking CPU restaure exactement : CPMINCORES AC=$($verified.Ac), DC=$($verified.Dc)."
}

function Enable-9800X3DGamingPowerPlan {
    $cpuNames = @(
        Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
            ForEach-Object { [string]$_.Name }
    )
    if (@($cpuNames | Where-Object { $_ -match '(?i)AMD\s+Ryzen\s+7\s+9800X3D' }).Count -eq 0) {
        throw "Le profil $power9800X3DName est reserve au processeur AMD Ryzen 7 9800X3D. Processeur detecte : $($cpuNames -join ', ')"
    }

    $guid = Get-PowerSchemeGuidByName -Name $power9800X3DName
    if (-not $guid) {
        $duplicateOutput = Invoke-PowerCfgChecked -Arguments @('/duplicatescheme','SCHEME_BALANCED')
        $guidMatch = [regex]::Match(($duplicateOutput -join ' '), '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b')
        if (-not $guidMatch.Success) { throw 'Le nouveau plan alimentation cree depuis Equilibre ne fournit aucun GUID exploitable.' }
        $guid = $guidMatch.Value
    }

    [void](Invoke-PowerCfgChecked -Arguments @('/changename',$guid,$power9800X3DName,'Clone Equilibre valide sur 9800X3D : boost actif, CPPC jeu et parking desactive.'))

    # Base volontairement proche du plan Equilibre utilise par AMD pour ses tests 9800X3D.
    # La frequence minimale reste a 5 %. Seul le parking est desactive : deux
    # passages LatencyMon de 12 min 30 ont abaisse le pic de 31,58 ms a
    # 518,8 puis 124,3 us sur la machine cible. La valeur precedente reste
    # sauvegardee et reversible par CoreParkingRestore.
    if (-not (Test-Path -LiteralPath $coreParkingBackup -PathType Leaf)) {
        $parkingBefore = Get-CoreParkingMinValues -SchemeGuid $guid
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        [pscustomobject]@{
            Version = 1
            SchemeGuid = $guid.ToLowerInvariant()
            Ac = $parkingBefore.Ac
            Dc = $parkingBefore.Dc
            SavedUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $coreParkingBackup -Encoding UTF8
    }
    $acSettings = @(
        @('PROCTHROTTLEMIN','5'),
        @('PROCTHROTTLEMAX','100'),
        @('PERFBOOSTMODE','2'),
        @('PERFEPP','15'),
        @('CPMINCORES','100')
    )
    $dcSettings = @(
        @('PROCTHROTTLEMIN','5'),
        @('PROCTHROTTLEMAX','100'),
        @('PERFBOOSTMODE','1'),
        @('PERFEPP','40'),
        @('CPMINCORES','100')
    )
    foreach ($setting in $acSettings) {
        [void](Invoke-PowerCfgChecked -Arguments @('/setacvalueindex',$guid,'SUB_PROCESSOR',$setting[0],$setting[1]))
    }
    foreach ($setting in $dcSettings) {
        [void](Invoke-PowerCfgChecked -Arguments @('/setdcvalueindex',$guid,'SUB_PROCESSOR',$setting[0],$setting[1]))
    }
    [void](Invoke-PowerCfgChecked -Arguments @('/setactive',$guid))
    $active = ((& powercfg.exe /getactivescheme 2>$null) -join ' ')
    if ($active -notmatch [regex]::Escape($guid)) { throw 'Le profil 9800X3D a ete cree mais Windows ne l a pas active.' }
    $parkingVerified = Get-CoreParkingMinValues -SchemeGuid $guid
    if ($parkingVerified.Ac -ne 100 -or $parkingVerified.Dc -ne 100) {
        throw "Le profil 9800X3D est actif mais le parking CPU n a pas ete desactive correctement (AC=$($parkingVerified.Ac), DC=$($parkingVerified.Dc))."
    }
    Write-Info 'Profil BASTOS 9800X3D Gaming active avec parking CPU desactive et restauration exacte disponible.'
}

function Get-TargetNics {
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match 'Realtek.*(2\.5GbE|8125)'
    })
}

function Save-NicBackup {
    if (Test-Path -LiteralPath $nicBackup) { return }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $records = @()
    foreach ($nic in Get-TargetNics) {
        $wanted = @('*EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'PowerSavingMode', '*InterruptModeration', '*RSS')
        $properties = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -AllProperties -ErrorAction SilentlyContinue | Where-Object {
            $wanted -contains $_.RegistryKeyword
        } | ForEach-Object {
            [pscustomobject]@{
                keyword = $_.RegistryKeyword
                value = @($_.RegistryValue | ForEach-Object { [string]$_ })
            }
        })
        $power = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
        $records += [pscustomobject]@{
            name = $nic.Name
            interfaceDescription = $nic.InterfaceDescription
            properties = $properties
            power = [pscustomobject]@{
                selectiveSuspend = if ($power) { [string]$power.SelectiveSuspend } else { $null }
                deviceSleepOnDisconnect = if ($power) { [string]$power.DeviceSleepOnDisconnect } else { $null }
            }
        }
    }
    if (@($records).Count -gt 0) {
        $records | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $nicBackup -Encoding UTF8
    }
}

function Set-AdvancedIfPresent {
    param($Nic, [string]$Keyword, [string[]]$Value)
    $property = Get-NetAdapterAdvancedProperty -Name $Nic.Name -RegistryKeyword $Keyword -AllProperties -ErrorAction SilentlyContinue
    if ($property) {
        Set-NetAdapterAdvancedProperty -Name $Nic.Name -RegistryKeyword $Keyword -RegistryValue $Value -NoRestart -ErrorAction Stop
        Write-Info ("{0}: {1} = {2}" -f $Nic.Name, $Keyword, ($Value -join ','))
    }
}

function Set-NicProfile {
    param([ValidateSet('Stable', 'LowLatency')][string]$Profile)
    Save-NicBackup
    # PowerShell deroule la sortie d'une fonction : avec une seule carte,
    # $nics deviendrait un objet scalaire sans propriete Count sous StrictMode.
    $nics = @(Get-TargetNics)
    if ($nics.Count -eq 0) {
        Write-Info 'Aucun Realtek 2.5 GbE compatible n''a été trouvé; aucune modification réseau.'
        return
    }
    foreach ($nic in $nics) {
        Set-AdvancedIfPresent $nic '*EEE' @('0')
        Set-AdvancedIfPresent $nic 'AdvancedEEE' @('0')
        Set-AdvancedIfPresent $nic 'EnableGreenEthernet' @('0')
        Set-AdvancedIfPresent $nic 'PowerSavingMode' @('0')
        Set-AdvancedIfPresent $nic '*RSS' @('1')
        if ($Profile -eq 'LowLatency') {
            Set-AdvancedIfPresent $nic '*InterruptModeration' @('0')
        }
        Set-NetAdapterRss -Name $nic.Name -Enabled $true -NoRestart -ErrorAction SilentlyContinue
        Set-NetAdapterPowerManagement -Name $nic.Name -SelectiveSuspend Disabled -DeviceSleepOnDisconnect Disabled -NoRestart -ErrorAction SilentlyContinue
        if (-not $NoRestart) { Restart-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction SilentlyContinue }
    }
    if ($Profile -eq 'Stable') {
        Write-Info 'Profil NIC Stable appliqué. Interrupt Moderation reste inchangé.'
    } else {
        Write-Info 'Profil NIC LowLatency appliqué. Compare le jitter et les DPC avant/après.'
    }
}

function Restore-NicProfile {
    if (-not (Test-Path -LiteralPath $nicBackup)) { throw "Sauvegarde NIC introuvable : $nicBackup" }
    $decoded = Get-Content -LiteralPath $nicBackup -Raw | ConvertFrom-Json
    $records = @()
    foreach ($item in $decoded) { $records += $item }
    foreach ($record in $records) {
        $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq $record.name -or $_.InterfaceDescription -eq $record.interfaceDescription
        } | Select-Object -First 1
        if (-not $nic) { continue }
        foreach ($property in @($record.properties)) {
            Set-AdvancedIfPresent $nic ([string]$property.keyword) @($property.value | ForEach-Object { [string]$_ })
        }
        if ($record.power.selectiveSuspend -and $record.power.selectiveSuspend -ne 'Unsupported') {
            Set-NetAdapterPowerManagement -Name $nic.Name -SelectiveSuspend $record.power.selectiveSuspend -NoRestart -ErrorAction SilentlyContinue
        }
        if ($record.power.deviceSleepOnDisconnect -and $record.power.deviceSleepOnDisconnect -ne 'Unsupported') {
            Set-NetAdapterPowerManagement -Name $nic.Name -DeviceSleepOnDisconnect $record.power.deviceSleepOnDisconnect -NoRestart -ErrorAction SilentlyContinue
        }
        if (-not $NoRestart) { Restart-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction SilentlyContinue }
    }
    Write-Info 'Paramètres NIC d''origine restaurés.'
}

function Show-Status {
    $hagsState=if(Get-Command Get-BastosHagsState -ErrorAction SilentlyContinue){Get-BastosHagsState}else{$null}
    $hagsText=if($hagsState){[string]$hagsState.Text}else{'État indisponible'}
    $mpo = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode'
    $vbs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity'
    $hvci = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    $deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    Write-Host "HAGS             : $hagsText"
    Write-Host ("MPO              : {0}" -f $(if ($mpo -eq 5) { 'Forcé OFF' } else { 'Actif/par défaut' }))
    Write-Host "VBS registre     : $vbs"
    Write-Host "Memory Integrity : $hvci"
    if ($deviceGuard) { Write-Host "VBS état réel    : $($deviceGuard.VirtualizationBasedSecurityStatus) (0=off, 1=configuré, 2=actif)" }
    Write-Host ("Plan alimentation: {0}" -f ((& powercfg.exe /getactivescheme) -join ' '))
    foreach ($nic in Get-TargetNics) {
        Write-Host "NIC              : $($nic.Name) - $($nic.InterfaceDescription)"
        Get-NetAdapterAdvancedProperty -Name $nic.Name -AllProperties -ErrorAction SilentlyContinue |
            Where-Object { @('*EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'PowerSavingMode', '*InterruptModeration', '*RSS') -contains $_.RegistryKeyword } |
            Select-Object RegistryKeyword, DisplayValue, RegistryValue |
            Format-Table -AutoSize
    }
    Write-Host 'SAM/ReBAR        : à vérifier dans AMD Software > Performance > Réglage.'
}

if ($Mode -ne 'Status') { Assert-Administrator }

switch ($Mode) {
    'Status' { Show-Status }
    'HagsOn' {
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
        Write-Info 'HAGS forcé ON. Redémarrage requis.'
    }
    'HagsOff' {
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1
        Write-Info 'HAGS forcé OFF. Redémarrage requis.'
    }
    'HagsDefault' {
        Remove-RegValueIfPresent 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
        Write-Info 'HAGS rendu au choix par défaut de Windows/pilote. Redémarrage requis.'
    }
    'MpoOff' {
        Set-DwordValue 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5
        Write-Info 'MPO forcé OFF. À utiliser seulement contre flicker, écran noir ou stutter DWM. Redémarrage requis.'
    }
    'MpoOn' {
        Remove-RegValueIfPresent 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode'
        Write-Info 'MPO restauré au comportement normal. Redémarrage requis.'
    }
    'NicStable' { Set-NicProfile -Profile Stable }
    'NicLowLatency' { Set-NicProfile -Profile LowLatency }
    'NicRestore' { Restore-NicProfile }
    'PowerBalanced' {
        & powercfg.exe /setactive SCHEME_BALANCED | Out-Null
        Write-Info 'Plan Windows Équilibré activé.'
    }
    'PowerHigh' {
        & powercfg.exe /setactive SCHEME_MIN | Out-Null
        Write-Info 'Plan Haute performance activé pour essai A/B. Sur 9800X3D, Équilibré reste la référence AMD.'
    }
    'PowerBastosUltimate' {
        $schemes = ((& powercfg.exe /list 2>$null) -join ' ')
        if ($schemes -notmatch [regex]::Escape($bastosUltimateGuid)) {
            [void](Invoke-PowerCfgChecked -Arguments @('/duplicatescheme','e9a42b02-d5df-448d-aa00-03f14749eb61',$bastosUltimateGuid))
            [void](Invoke-PowerCfgChecked -Arguments @('/changename',$bastosUltimateGuid,'Ultimate Performance','Profil actif BASTOS reproduit depuis le modèle Windows Ultimate Performance.'))
        }
        [void](Invoke-PowerCfgChecked -Arguments @('/setactive',$bastosUltimateGuid))
        Write-Info 'Plan Ultimate Performance de cet OS activé.'
    }
    'Power9800X3D' { Enable-9800X3DGamingPowerPlan }
    'CoreParkingOn' { Enable-CoreParking }
    'CoreParkingRestore' { Restore-CoreParking }
    'VbsOff' {
        if (-not $ConfirmSecurityRisk) {
            throw 'Ce mode réduit la protection du noyau. Relance avec -ConfirmSecurityRisk si tu acceptes ce risque.'
        }
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
        & bcdedit.exe /set hypervisorlaunchtype off | Out-Null
        Write-Info 'VBS/HVCI désactivés pour benchmark uniquement. Hyper-V, WSL2 et Sandbox ne fonctionneront pas. Redémarrage requis.'
    }
    'VbsOn' {
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 1
        Set-DwordValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1
        & bcdedit.exe /set hypervisorlaunchtype auto | Out-Null
        Write-Info 'VBS/HVCI réactivés. Redémarrage requis.'
    }
    'GameModeOn' {
        Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
        Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
        Write-Info 'Mode Jeu Windows activé.'
    }
    'GameModeOff' {
        Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 0
        Set-DwordValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
        Write-Info 'Mode Jeu Windows désactivé.'
    }
    'GameModeDefault' {
        Remove-RegValueIfPresent 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode'
        Remove-RegValueIfPresent 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        Write-Info 'Mode Jeu rendu au comportement par défaut de Windows.'
    }
    'GameDvrOff' {
        Set-DwordValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Write-Info 'Capture et enregistrement Windows en arrière-plan désactivés.'
    }
    'GameDvrOn' {
        Set-DwordValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1
        Write-Info 'Capture et enregistrement Windows réactivés.'
    }
    'TransparencyOff' {
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        Write-Info 'Effets de transparence Windows désactivés.'
    }
    'TransparencyOn' {
        Set-DwordValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
        Write-Info 'Effets de transparence Windows activés.'
    }
}

Write-OperationResult -Success $true -Message "$Mode applique avec succes."
