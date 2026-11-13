[CmdletBinding()]
param(
    [ValidateSet('Get','Apply','Restore')][string]$Action = 'Get',
    [string]$AdapterId,
    [ValidateSet('Stable','LowLatency')][string]$Profile = 'Stable',
    [string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NetworkBackupRoot = Join-Path $env:ProgramData 'BASTOS\NetworkProfiles'

function Get-EthernetAdapters {
    @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
        $_.HardwareInterface -and [string]$_.MediaType -eq '802.3' -and
        [string]$_.PhysicalMediaType -eq '802.3' -and $_.PnPDeviceID
    })
}
function Get-NicId($Nic) { ([guid]$Nic.InterfaceGuid).ToString('D') }
function Get-SelectedNic([string]$Id) {
    $idValue = ([guid]$Id).ToString('D')
    $matches = @(Get-EthernetAdapters | Where-Object { (Get-NicId $_) -eq $idValue })
    if ($matches.Count -ne 1) { throw 'Carte Ethernet absente ou identification ambigue. Actualiser la detection.' }
    $matches[0]
}
function Get-NicCapabilities($Nic) {
    $name = [WildcardPattern]::Escape([string]$Nic.Name)
    $properties = @(Get-NetAdapterAdvancedProperty -Name $name -AllProperties -ErrorAction Stop)
    $power = $null
    try { $power = Get-NetAdapterPowerManagement -Name $name -ErrorAction Stop } catch {}
    # Only standard NDIS keywords are shared across vendors. Realtek-specific
    # keys are never written on another vendor, nor created when absent.
    $realtek = [string]$Nic.PnPDeviceID -match '(?i)(VEN_10EC|VID_0BDA)'
    $definitions = @(
        @('*EEE','Ethernet a economie d''energie (EEE)','0',$true),
        @('AdvancedEEE','Advanced EEE','0',$realtek),
        @('EnableGreenEthernet','Green Ethernet','0',$realtek),
        @('PowerSavingMode','Mode economie d''energie','0',$realtek),
        @('*RSS','Repartition de reception (RSS)','1',$true),
        @('*InterruptModeration','Moderation des interruptions','0',$true)
    )
    foreach ($definition in $definitions) {
        $property = @($properties | Where-Object RegistryKeyword -eq $definition[0])
        $supported = $definition[3] -and $property.Count -eq 1 -and
            @($property[0].RegistryValue).Count -eq 1 -and
            [string]$property[0].RegistryValue[0] -match '^-?[0-9]{1,10}$' -and
            @($property[0].ValidRegistryValues) -contains $definition[2] -and
            @($property[0].ValidRegistryValues) -contains [string]$property[0].RegistryValue[0]
        [pscustomobject]@{
            Key=$definition[0]; Label=$definition[1]; Kind='Advanced'; Supported=[bool]$supported
            Current=$(if ($property.Count -eq 1) { [string]($property[0].RegistryValue -join ',') } else { '' })
            Target=$definition[2]; LowOnly=($definition[0] -eq '*InterruptModeration')
            Handle=$(if ($property.Count -eq 1) { $property[0] } else { $null })
        }
    }
    foreach ($key in @('SelectiveSuspend','DeviceSleepOnDisconnect')) {
        $value = if ($null -ne $power) { [string]$power.$key } else { '' }
        [pscustomobject]@{
            Key=$key; Label=$(if ($key -eq 'SelectiveSuspend') { 'Suspension selective' } else { 'Veille lors de la deconnexion' })
            Kind='Power'; Supported=($value -in @('Enabled','Disabled')); Current=$value
            Target='Disabled'; LowOnly=$false; Handle=$power
        }
    }
}
function Get-BackupPath($Nic) { Join-Path $script:NetworkBackupRoot ((Get-NicId $Nic) + '.json') }
function Read-NicBackup($Nic) {
    $path = Get-BackupPath $Nic
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $backup = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($backup.Schema -ne 1 -or $backup.AdapterId -ne (Get-NicId $Nic) -or
        $backup.PnpId -ne [string]$Nic.PnPDeviceID) { throw 'Sauvegarde incompatible avec cette carte. Aucune modification.' }
    $allowed = @('*EEE','AdvancedEEE','EnableGreenEthernet','PowerSavingMode','*RSS','*InterruptModeration','SelectiveSuspend','DeviceSleepOnDisconnect')
    $keys = @()
    foreach ($entry in @($backup.Entries)) {
        if ($entry.Key -notin $allowed -or $entry.Key -in $keys -or
            $entry.Kind -notin @('Advanced','Power') -or $entry.Touched -isnot [bool] -or
            [string]$entry.Original -notmatch '^(?:-?[0-9]{1,10}|Enabled|Disabled)$' -or
            [string]$entry.Target -notmatch '^(?:-?[0-9]{1,10}|Enabled|Disabled)$') { throw 'Sauvegarde reseau invalide.' }
        $keys += $entry.Key
    }
    $backup
}
function Initialize-NicStorage {
    New-Item -ItemType Directory -Path $script:NetworkBackupRoot -Force | Out-Null
    # Machine-wide restoration data: writable only by administrators and SYSTEM.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545')) {
        $rights = if ($sid -eq 'S-1-5-32-545') { 'ReadAndExecute' } else { 'FullControl' }
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($sid)), $rights,
            'ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:NetworkBackupRoot -AclObject $acl
}
function Write-NicBackup($Nic,$Backup) {
    $path = Get-BackupPath $Nic
    $temp = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($Backup | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp,$path,($path + '.previous')) }
    else { [IO.File]::Move($temp,$path) }
}
function Test-NicValue($Capability,[string]$Value) {
    if (-not $Capability.Supported) { return $false }
    if ($Capability.Kind -eq 'Power') { return $Value -in @('Enabled','Disabled') }
    return @($Capability.Handle.ValidRegistryValues) -contains $Value
}
function Set-NicValue($Capability,[string]$Value) {
    if (-not (Test-NicValue $Capability $Value)) { throw ('Valeur non prise en charge : ' + $Capability.Key) }
    if ($Capability.Kind -eq 'Advanced') {
        Set-NetAdapterAdvancedProperty -InputObject $Capability.Handle -RegistryValue @($Value) -NoRestart -ErrorAction Stop | Out-Null
    } else {
        $parameters = @{ InputObject=$Capability.Handle; NoRestart=$true; ErrorAction='Stop' }
        $parameters[$Capability.Key] = $Value
        Set-NetAdapterPowerManagement @parameters | Out-Null
    }
}
function Get-CurrentCapability($Nic,[string]$Key) {
    $currentNic = Get-SelectedNic (Get-NicId $Nic)
    if ($currentNic.PnPDeviceID -ne $Nic.PnPDeviceID) { throw 'Identite de la carte modifiee.' }
    $current = @(Get-NicCapabilities $currentNic | Where-Object Key -eq $Key)
    if ($current.Count -ne 1) { throw ('Option devenue indisponible : ' + $Key) }
    $current[0]
}
function Restart-SelectedNic($Nic) {
    $current = Get-SelectedNic (Get-NicId $Nic)
    if ($current.PnPDeviceID -ne $Nic.PnPDeviceID) { throw 'Identite de la carte modifiee.' }
    Restart-NetAdapter -InputObject $current -Confirm:$false -ErrorAction Stop | Out-Null
}
function Get-NicSnapshot($Nic) {
    try {
        $capabilities = @(Get-NicCapabilities $Nic)
        $backup = Read-NicBackup $Nic
        $active = @($backup | Where-Object { $null -ne $_ } | ForEach-Object { $_.Entries } | Where-Object Touched)
        $state = 'Aucun profil Bastos actif'
        $canApply = $true
        if ($null -ne $backup -and $backup.Active) {
            $state = 'Dernier profil : ' + $backup.Profile
            if ($backup.PendingRestart) { $state += ' - redemarrage de la carte requis' }
            foreach ($entry in $active) {
                $cap = @($capabilities | Where-Object Key -eq $entry.Key)
                if ($cap.Count -ne 1 -or -not $cap[0].Supported -or $cap[0].Current -ne $entry.Target) {
                    $state += ' - etat modifie ou incomplet'; $canApply = $false; break
                }
            }
            if ($backup.DriverVersion -ne [string]$Nic.DriverVersion) {
                $state += ' - pilote modifie, restaurer avant un nouveau profil'; $canApply = $false
            }
        }
        [pscustomobject]@{
            Id=(Get-NicId $Nic); Name=[string]$Nic.Name; Description=[string]$Nic.InterfaceDescription
            Driver=[string]$Nic.DriverVersion; Status=[string]$Nic.Status; State=$state
            CanApply=($canApply -and @($capabilities | Where-Object Supported).Count -gt 0)
            CanRestore=($null -ne $backup -and $backup.Active)
            Capabilities=@($capabilities | Select-Object Key,Label,Kind,Supported,Current,Target,LowOnly)
        }
    } catch {
        [pscustomobject]@{ Id=(Get-NicId $Nic); Name=[string]$Nic.Name; Description=[string]$Nic.InterfaceDescription
            Driver=[string]$Nic.DriverVersion; Status=[string]$Nic.Status; State=$_.Exception.Message
            CanApply=$false; CanRestore=$false; Capabilities=@() }
    }
}
function Invoke-NicProfile([string]$Id,[string]$RequestedProfile) {
    $nic = Get-SelectedNic $Id
    if ([string]$nic.Status -eq 'Disabled') { throw 'Activer la carte dans Windows avant de modifier son profil.' }
    $capabilities = @(Get-NicCapabilities $nic)
    $backup = Read-NicBackup $nic
    if ($null -ne $backup -and $backup.Active -and $backup.DriverVersion -ne [string]$nic.DriverVersion) {
        throw 'Pilote modifie depuis la sauvegarde. Restaurer avant un nouveau profil.'
    }
    Initialize-NicStorage
    if ($null -eq $backup -or -not $backup.Active) {
        if ($null -ne $backup) {
            Copy-Item -LiteralPath (Get-BackupPath $nic) -Destination ((Get-BackupPath $nic) + '.' + [guid]::NewGuid().ToString('N') + '.history')
        }
        $backup = [pscustomobject]@{ Schema=1; AdapterId=(Get-NicId $nic); PnpId=[string]$nic.PnPDeviceID
            DriverVersion=[string]$nic.DriverVersion; CreatedUtc=[DateTime]::UtcNow.ToString('o')
            Active=$true; Profile='En cours'; PendingRestart=$false; Entries=@() }
    }
    $plan = @()
    foreach ($cap in $capabilities) {
        $entry = @($backup.Entries | Where-Object Key -eq $cap.Key) | Select-Object -First 1
        if ($null -ne $entry -and $entry.Touched -and (-not $cap.Supported -or $cap.Current -ne $entry.Target)) {
            throw ('Option modifiee hors Bastos ou indisponible : ' + $cap.Label + '. Restaurer avant de continuer.')
        }
        if (-not $cap.Supported) { continue }
        $target = $cap.Target
        if ($cap.LowOnly -and $RequestedProfile -eq 'Stable') {
            if ($null -eq $entry -or -not $entry.Touched) { continue }
            $target = [string]$entry.Original # Low Latency -> Stable restores original moderation.
        }
        if (-not (Test-NicValue $cap $target)) { throw ('Valeur sauvegardee incompatible : ' + $cap.Key) }
        if ($null -eq $entry) {
            $entry = [pscustomobject]@{Key=$cap.Key; Kind=$cap.Kind; Original=$cap.Current; Target=$cap.Current; Touched=$false}
            $backup.Entries += $entry
        } elseif (-not $entry.Touched) {
            # No ownership until our first actual write: preserve subsequent user edits.
            $entry.Original = $cap.Current
            $entry.Target = $cap.Current
        }
        if ($cap.Current -ne $target) { $plan += [pscustomobject]@{Key=$cap.Key; Before=$cap.Current; Target=$target; Entry=$entry} }
    }
    if (@($capabilities | Where-Object { $_.Supported -and (-not $_.LowOnly -or $RequestedProfile -eq 'LowLatency') }).Count -eq 0) {
        throw 'Aucune option compatible pour ce profil. Aucune modification.'
    }
    if ($RequestedProfile -eq 'LowLatency' -and -not ($capabilities | Where-Object { $_.Key -eq '*InterruptModeration' -and $_.Supported })) {
        throw 'La modulation des interruptions est indisponible. Utiliser le profil Stable.'
    }
    Write-NicBackup $nic $backup # Durable original values BEFORE any adapter write.
    $attempted = @()
    try {
        foreach ($item in $plan) {
            $cap = Get-CurrentCapability $nic $item.Key
            if ($cap.Current -ne $item.Before) { throw ('Option modifiee pendant l''operation : ' + $item.Key) }
            $item.Entry.Target = $item.Target
            $item.Entry.Touched = $true
            $backup.PendingRestart = $true
            Write-NicBackup $nic $backup # Journal even if the driver partially applies then fails.
            $attempted += $item
            Set-NicValue $cap $item.Target
            if ((Get-CurrentCapability $nic $item.Key).Current -ne $item.Target) { throw ('Verification echouee : ' + $item.Key) }
        }
        if ($backup.PendingRestart) { Restart-SelectedNic $nic }
        foreach ($item in $plan) {
            if ((Get-CurrentCapability $nic $item.Key).Current -ne $item.Target) { throw ('Verification apres redemarrage echouee : ' + $item.Key) }
        }
        $backup.PendingRestart = $false
        $backup.Profile = $RequestedProfile
        Write-NicBackup $nic $backup
        return ('Profil ' + $RequestedProfile + ' verifie : ' + $plan.Count + ' option(s) modifiee(s). Options non prises en charge ignorees. Valeurs initiales sauvegardees.')
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        [array]::Reverse($attempted)
        foreach ($item in $attempted) {
            try {
                Set-NicValue (Get-CurrentCapability $nic $item.Key) $item.Before
                if ((Get-CurrentCapability $nic $item.Key).Current -ne $item.Before) { throw 'Verification du retour arriere echouee.' }
                $item.Entry.Target = $item.Before
                $item.Entry.Touched = ($item.Before -ne $item.Entry.Original)
            } catch { $rollbackErrors += $item.Key }
        }
        if ($attempted.Count -gt 0) {
            try { Restart-SelectedNic $nic; $backup.PendingRestart=$false } catch { $rollbackErrors += 'Redemarrage'; $backup.PendingRestart=$true }
        }
        $backup.Profile = 'Operation incomplete - restauration disponible'
        Write-NicBackup $nic $backup
        if ($rollbackErrors.Count) { throw ($failure + ' Retour arriere incomplet : ' + ($rollbackErrors -join ', ') + '. Sauvegarde conservee.') }
        throw ($failure + ' Modifications de cette tentative annulees. Sauvegarde conservee.')
    }
}
function Restore-NicProfile([string]$Id) {
    $nic = Get-SelectedNic $Id
    $backup = Read-NicBackup $nic
    if ($null -eq $backup -or -not $backup.Active) { return 'Aucune sauvegarde active a restaurer.' }
    Initialize-NicStorage
    $failures = @()
    foreach ($entry in @($backup.Entries | Where-Object Touched)) {
        try {
            $cap = Get-CurrentCapability $nic $entry.Key
            if (-not (Test-NicValue $cap $entry.Original)) { throw 'Option absente ou ancienne valeur non prise en charge.' }
            if ($cap.Current -ne $entry.Original) {
                if ($cap.Current -ne $entry.Target) { throw 'Valeur modifiee hors Bastos : conservation pour eviter un conflit.' }
                $backup.PendingRestart=$true
                Write-NicBackup $nic $backup
                Set-NicValue $cap $entry.Original
                if ((Get-CurrentCapability $nic $entry.Key).Current -ne $entry.Original) { throw 'Verification echouee.' }
            }
            # Keep ownership until after restart; a crash leaves restoration available.
        } catch { $failures += ($entry.Key + ' : ' + $_.Exception.Message) }
    }
    if ($backup.PendingRestart) {
        try { Restart-SelectedNic $nic; $backup.PendingRestart=$false } catch { $failures += ('Redemarrage : ' + $_.Exception.Message) }
    }
    foreach ($entry in @($backup.Entries | Where-Object Touched)) {
        try {
            $cap = Get-CurrentCapability $nic $entry.Key
            if ($cap.Supported -and $cap.Current -eq $entry.Original) { $entry.Touched=$false; $entry.Target=$entry.Original }
            else { $failures += ('Non restaure : ' + $entry.Key) }
        } catch { $failures += $_.Exception.Message }
    }
    $backup.Active = (@($backup.Entries | Where-Object Touched).Count -gt 0 -or $backup.PendingRestart)
    $backup.Profile = $(if ($backup.Active) { 'Restauration incomplete' } else { 'Restaure' })
    Write-NicBackup $nic $backup
    if ($failures.Count) { throw ('Restauration partielle. Sauvegarde conservee. ' + ($failures -join ' / ')) }
    return 'Valeurs initiales restaurees et verifiees pour cette carte uniquement. Sauvegarde conservee.'
}
function Assert-NicAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Autorisation administrateur requise.' }
}
# Dot-sourcing loads functions only, allowing isolated regression tests with mocked hardware.
if ($MyInvocation.InvocationName -eq '.') { return }
$result = [ordered]@{Success=$false;Message='';Adapters=@()}
$lock = $null
try {
    if ($Action -eq 'Get') {
        $result.Adapters = @(Get-EthernetAdapters | ForEach-Object { Get-NicSnapshot $_ })
        $result.Message = 'Detection terminee. Aucun reglage modifie.'
    } else {
        Assert-NicAdministrator
        Initialize-NicStorage
        # Prevent two Bastos windows from changing the same machine concurrently.
        $lock = [IO.File]::Open((Join-Path $script:NetworkBackupRoot 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($Action -eq 'Apply') { $result.Message = Invoke-NicProfile $AdapterId $Profile }
        else { $result.Message = Restore-NicProfile $AdapterId }
    }
    $result.Success = $true
} catch { $result.Message = $_.Exception.Message }
finally { if ($null -ne $lock) { $lock.Dispose() } }
$json = $result | ConvertTo-Json -Depth 9
if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),$json,[Text.UTF8Encoding]::new($false)) }
else { $json }
if (-not $result.Success) { exit 1 }
