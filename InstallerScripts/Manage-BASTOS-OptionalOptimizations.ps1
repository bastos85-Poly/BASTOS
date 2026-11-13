param(
    [ValidateSet('Get', 'Enable', 'Restore')]
    [string]$Action = 'Get',
    [string]$Id = 'all',
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:ProgramData 'BASTOS-ISO\State\OptionalOptimizations'

$definitions = [ordered]@{
    'nagle' = @{
        Mechanism = 'Nagle'
        Restart = $true
    }
    'game-dvr' = @{
        Mechanism = 'Registry'
        Values = @(
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Desired = 0; Kind = 'DWord'; CreateKey = $true }
        )
    }
    'fax' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'Fax'; DesiredStart = 4 })
    }
    'retail-demo' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'RetailDemo'; DesiredStart = 4 })
    }
    'maps-broker' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'MapsBroker'; DesiredStart = 3 })
    }
    'wmp-network' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'WMPNetworkSvc'; DesiredStart = 4 })
    }
    'distributed-link-tracking' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'TrkWks'; DesiredStart = 4 })
    }
    'connected-devices' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'CDPSvc'; DesiredStart = 4 })
    }
    'connected-devices-user' = @{
        Mechanism = 'Registry'
        Restart = $true
        Values = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\CDPUserSvc'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true }
        )
    }
    'sysmain' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'SysMain'; DesiredStart = 4 })
    }
    'image-acquisition' = @{
        Mechanism = 'Service'
        Services = @(@{ Name = 'stisvc'; DesiredStart = 4 })
    }
    'phone-link' = @{
        Mechanism = 'Registry'
        Restart = $true
        Values = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\PhoneSvc'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SmsRouter'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\MessagingService'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\UnistoreSvc'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\UserDataSvc'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true },
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\PimIndexMaintenanceSvc'; Name = 'Start'; Desired = 4; Kind = 'DWord'; RequireKey = $true }
        )
    }
}

function Get-BackupPath([string]$optionId) {
    Join-Path $stateRoot ($optionId + '.json')
}

function Test-RegistryValue([string]$path, [string]$name) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $key = Get-Item -LiteralPath $path
    return @($key.GetValueNames()) -contains $name
}

function Read-RegistryRecord([string]$path, [string]$name) {
    $exists = Test-RegistryValue $path $name
    $value = $null
    $kind = 'String'
    if ($exists) {
        $key = Get-Item -LiteralPath $path
        $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind($name).ToString()
    }
    [pscustomobject]@{ Path = $path; Name = $name; Exists = $exists; Value = $value; Kind = $kind }
}

function Set-RegistryValue([string]$path, [string]$name, $value, [string]$kind, [bool]$createKey) {
    if (-not (Test-Path -LiteralPath $path)) {
        if (-not $createKey) { return $false }
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType $kind -Force | Out-Null
    return $true
}

function Restore-RegistryRecord($record) {
    if ([bool]$record.Exists) {
        Set-RegistryValue ([string]$record.Path) ([string]$record.Name) $record.Value ([string]$record.Kind) $true | Out-Null
    }
    elseif (Test-Path -LiteralPath ([string]$record.Path)) {
        Remove-ItemProperty -LiteralPath ([string]$record.Path) -Name ([string]$record.Name) -ErrorAction SilentlyContinue
    }
}

function Get-ServiceRecord([string]$name) {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $start = Read-RegistryRecord $path 'Start'
    $delayed = Read-RegistryRecord $path 'DelayedAutoStart'
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name = $name
        Start = $start
        DelayedAutoStart = $delayed
        WasRunning = [bool]($null -ne $service -and $service.Status -eq 'Running')
    }
}

function Set-ServiceStart([string]$name, [int]$start, [bool]$delayed = $false) {
    $mode = switch ($start) {
        0 { 'boot' }
        1 { 'system' }
        2 { if ($delayed) { 'delayed-auto' } else { 'auto' } }
        3 { 'demand' }
        4 { 'disabled' }
        default { throw "Type de demarrage non pris en charge pour $name : $start" }
    }
    $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
    & $sc config $name start= $mode | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossible de configurer le service $name (code $LASTEXITCODE)." }
    if ($start -eq 3 -or $start -eq 4) {
        & $sc stop $name | Out-Null
    }
}

function Get-NagleValues {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $values = @()
    foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        $values += [pscustomobject]@{ Path = $key.PSPath; Name = 'TcpAckFrequency'; Desired = 1; Kind = 'DWord'; CreateKey = $false }
        $values += [pscustomobject]@{ Path = $key.PSPath; Name = 'TCPNoDelay'; Desired = 1; Kind = 'DWord'; CreateKey = $false }
    }
    return @($values)
}

function Get-ApplicableRegistryValues($definition) {
    if ([string]$definition.Mechanism -eq 'Nagle') { return @(Get-NagleValues) }
    $values = @()
    foreach ($value in @($definition.Values)) {
        $requiresKey = $value.ContainsKey('RequireKey') -and [bool]$value.RequireKey
        if (-not $requiresKey -or (Test-Path -LiteralPath ([string]$value.Path))) {
            $values += [pscustomobject]@{
                Path = [string]$value.Path
                Name = [string]$value.Name
                Desired = $value.Desired
                Kind = [string]$value.Kind
                CreateKey = [bool]($value.ContainsKey('CreateKey') -and $value.CreateKey)
            }
        }
    }
    return @($values)
}

function New-Backup($definition) {
    $registry = @()
    $services = @()
    if ([string]$definition.Mechanism -eq 'Service') {
        foreach ($serviceDefinition in @($definition.Services)) {
            $record = Get-ServiceRecord ([string]$serviceDefinition.Name)
            if ($null -ne $record) { $services += $record }
        }
    }
    else {
        foreach ($value in @(Get-ApplicableRegistryValues $definition)) {
            $registry += Read-RegistryRecord ([string]$value.Path) ([string]$value.Name)
        }
    }
    [pscustomobject]@{
        CapturedUtc = [DateTime]::UtcNow.ToString('o')
        Registry = @($registry)
        Services = @($services)
    }
}

function Save-Backup([string]$optionId, $definition) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $path = Get-BackupPath $optionId
    if (-not (Test-Path -LiteralPath $path)) {
        New-Backup $definition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        return
    }

    # A network interface can appear after the first activation. Preserve its state too.
    if ([string]$definition.Mechanism -eq 'Nagle') {
        $backup = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $records = @($backup.Registry)
        foreach ($value in @(Get-ApplicableRegistryValues $definition)) {
            $found = $records | Where-Object { $_.Path -eq $value.Path -and $_.Name -eq $value.Name } | Select-Object -First 1
            if ($null -eq $found) { $records += Read-RegistryRecord ([string]$value.Path) ([string]$value.Name) }
        }
        $backup.Registry = @($records)
        $backup | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Test-OptionApplicable($definition) {
    if ([string]$definition.Mechanism -eq 'Service') {
        foreach ($serviceDefinition in @($definition.Services)) {
            if (Test-Path -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + [string]$serviceDefinition.Name)) { return $true }
        }
        return $false
    }
    return @(Get-ApplicableRegistryValues $definition).Count -gt 0
}

function Test-OptionApplied($definition) {
    if (-not (Test-OptionApplicable $definition)) { return $false }
    if ([string]$definition.Mechanism -eq 'Service') {
        $checked = 0
        foreach ($serviceDefinition in @($definition.Services)) {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + [string]$serviceDefinition.Name
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $checked++
            $current = (Get-ItemProperty -LiteralPath $path -Name Start -ErrorAction SilentlyContinue).Start
            if ([int]$current -ne [int]$serviceDefinition.DesiredStart) { return $false }
        }
        return $checked -gt 0
    }

    $values = @(Get-ApplicableRegistryValues $definition)
    foreach ($value in $values) {
        if (-not (Test-RegistryValue ([string]$value.Path) ([string]$value.Name))) { return $false }
        $current = (Get-ItemProperty -LiteralPath ([string]$value.Path) -Name ([string]$value.Name)).([string]$value.Name)
        if ([string]$current -ne [string]$value.Desired) { return $false }
    }
    return $values.Count -gt 0
}

function Enable-Option([string]$optionId, $definition) {
    if (-not (Test-OptionApplicable $definition)) { throw "Ce composant Windows n'est pas installe sur ce PC." }
    Save-Backup $optionId $definition

    if ([string]$definition.Mechanism -eq 'Service') {
        foreach ($serviceDefinition in @($definition.Services)) {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + [string]$serviceDefinition.Name
            if (Test-Path -LiteralPath $path) {
                Set-ServiceStart ([string]$serviceDefinition.Name) ([int]$serviceDefinition.DesiredStart)
            }
        }
    }
    else {
        foreach ($value in @(Get-ApplicableRegistryValues $definition)) {
            Set-RegistryValue ([string]$value.Path) ([string]$value.Name) $value.Desired ([string]$value.Kind) ([bool]$value.CreateKey) | Out-Null
        }
    }
}

function Restore-Option([string]$optionId, $definition) {
    $path = Get-BackupPath $optionId
    if (-not (Test-Path -LiteralPath $path)) { throw "Aucune sauvegarde Bastos n'existe pour ce reglage ; aucune valeur arbitraire n'a ete appliquee." }
    $backup = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    foreach ($record in @($backup.Registry)) { Restore-RegistryRecord $record }
    foreach ($serviceRecord in @($backup.Services)) {
        $start = [int]$serviceRecord.Start.Value
        $delayed = [bool]($serviceRecord.DelayedAutoStart.Exists -and [int]$serviceRecord.DelayedAutoStart.Value -eq 1)
        Set-ServiceStart ([string]$serviceRecord.Name) $start $delayed
        Restore-RegistryRecord $serviceRecord.DelayedAutoStart
        if ([bool]$serviceRecord.WasRunning -and $start -ne 4) {
            Start-Service -Name ([string]$serviceRecord.Name) -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $path -Force
}

function New-StateResult([bool]$success, [string]$message) {
    $states = [ordered]@{}
    $applicable = [ordered]@{}
    $hasBackup = [ordered]@{}
    foreach ($entry in $definitions.GetEnumerator()) {
        $states[$entry.Key] = [bool](Test-OptionApplied $entry.Value)
        $applicable[$entry.Key] = [bool](Test-OptionApplicable $entry.Value)
        $hasBackup[$entry.Key] = Test-Path -LiteralPath (Get-BackupPath $entry.Key)
    }
    [ordered]@{
        Success = $success
        Message = $message
        States = $states
        Applicable = $applicable
        HasBackup = $hasBackup
    }
}

$success = $true
$message = 'Etat des optimisations actualise.'
try {
    if ($Action -ne 'Get') {
        if ($Id -eq 'all') { $selectedIds = @($definitions.Keys) }
        elseif ($definitions.Contains($Id)) { $selectedIds = @($Id) }
        else { throw "Optimisation inconnue : $Id" }

        foreach ($optionId in $selectedIds) {
            if ($Action -eq 'Enable') { Enable-Option $optionId $definitions[$optionId] }
            else { Restore-Option $optionId $definitions[$optionId] }
        }
        $needsRestart = @($selectedIds | Where-Object { $definitions[$_].ContainsKey('Restart') -and $definitions[$_].Restart }).Count -gt 0
        if ($Action -eq 'Enable') {
            $message = if ($needsRestart) { 'Optimisation appliquee - redemarrage ou reconnexion requis.' } else { 'Optimisation appliquee et etat precedent sauvegarde.' }
        }
        else {
            $message = if ($needsRestart) { 'Etat precedent restaure - redemarrage ou reconnexion requis.' } else { 'Etat precedent restaure.' }
        }
    }
}
catch {
    $success = $false
    $message = $_.Exception.Message
}

$result = New-StateResult $success $message
if ($ResultPath) {
    $parent = Split-Path -Parent $ResultPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}
if (-not $success) { exit 1 }
