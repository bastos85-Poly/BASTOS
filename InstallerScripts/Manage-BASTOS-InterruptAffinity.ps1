param(
    [ValidateSet('Plan','Get','GetDefaults','Enable','Disable')][string]$Action = 'Get',
    [ValidateSet('Custom','SixCore','DualCcd','Intel','X3D')][string]$Profile = 'X3D',
    [int]$GpuCore = 2,
    [int]$UsbCore = 3,
    [int]$NetworkCore = 4,
    [int]$AudioCore = 5,
    [string]$ResultPath
)
$ErrorActionPreference = 'Stop'

# Independent BASTOS implementation of the device categories and profile values
# supplied by the user. No third-party CMD is executed or redistributed.
function Get-Layout {
    switch ($Profile) {
        'SixCore' { return @{ GPU=2; USB=3; NETWORK=4; AUDIO=4 } }
        'DualCcd' { return @{ GPU=8; USB=9; NETWORK=10; AUDIO=11 } }
        'Intel'   { return @{ GPU=2; USB=3; NETWORK=4; AUDIO=5 } }
        'X3D'     { return @{ GPU=2; USB=3; NETWORK=4; AUDIO=5 } }
        default   { return @{ GPU=$GpuCore; USB=$UsbCore; NETWORK=$NetworkCore; AUDIO=$AudioCore } }
    }
}
function Get-Topology {
    $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
    if (-not $processors.Count) { throw 'Processeur introuvable.' }
    $cores = [int](($processors | Measure-Object NumberOfCores -Sum).Sum)
    $logical = [int](($processors | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
    if ($cores -lt 1 -or $logical -lt $cores -or $logical -gt 64) { throw 'Topologie processeur non prise en charge.' }
    if ($logical -ne $cores -and $logical -ne (2 * $cores)) {
        throw 'Topologie hybride ou asymetrique : la correspondance des coeurs du profil ne peut pas etre garantie.'
    }
    return @{ Cores=$cores; Logical=$logical; Step=($logical / $cores); Name=[string]$processors[0].Name }
}
function Get-Mask([int]$logicalCpu) {
    if ($logicalCpu -lt 0 -or $logicalCpu -ge 64) { throw 'Processeur logique hors du masque 64 bits.' }
    $bytes = [byte[]]::new(8)
    $bytes[[int][Math]::Floor($logicalCpu / 8)] = [byte](1 -shl ($logicalCpu % 8))
    return $bytes
}
function Get-Targets {
    foreach ($device in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.PNPDeviceID -like 'PCI\*' })) {
        $role = $null
        if ($device.PNPClass -eq 'Display') { $role = 'GPU' }
        elseif ($device.PNPClass -eq 'Net') { $role = 'NETWORK' }
        elseif ($device.PNPClass -eq 'USB') { $role = 'USB' }
        elseif ($device.Service -eq 'HDAudBus') { $role = 'AUDIO' }
        if ($role) {
            [pscustomobject]@{ Role=$role; Name=[string]$device.Name; Id=[string]$device.PNPDeviceID;
                Key=('SYSTEM\CurrentControlSet\Enum\' + [string]$device.PNPDeviceID + '\Device Parameters\Interrupt Management\Affinity Policy') }
        }
    }
}
function Read-Value($key,[string]$name) {
    if ($null -eq $key -or -not (@($key.GetValueNames()) -ccontains $name)) { return @{ Exists=$false; Value=$null; Kind=$null } }
    return @{ Exists=$true; Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); Kind=$key.GetValueKind($name) }
}
function Restore-Value($key,[string]$name,$record) {
    if ($record.Exists) { $key.SetValue($name,$record.Value,$record.Kind) }
    else { $key.DeleteValue($name,$false) }
}
function Write-Result($result) {
    $json = $result | ConvertTo-Json -Depth 7 -Compress
    if ($ResultPath) {
        $allowed = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'BASTOS\Logs')).TrimEnd('\') + '\'
        $full = [IO.Path]::GetFullPath($ResultPath)
        if (-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($full) -ne '.json') {
            throw 'Chemin de compte rendu refuse.'
        }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full)) | Out-Null
        [IO.File]::WriteAllText($full,$json,[Text.UTF8Encoding]::new($false))
    }
    Write-Output $json
}
try {
    $layout = Get-Layout
    $topology = $null; $logical = @{}; $masks = @{}
    if ($Action -notin @('Disable','GetDefaults')) {
        $topology = Get-Topology
        if ($Profile -eq 'X3D' -and $topology.Name -notmatch '(?i)AMD.*X3D') { throw 'Profil X3D reserve aux Ryzen X3D.' }
        if ($Profile -eq 'Intel' -and $topology.Name -notmatch '(?i)Intel') { throw 'Profil Intel reserve aux processeurs Intel.' }
        if ($Profile -eq 'DualCcd' -and ($topology.Name -notmatch '(?i)AMD' -or $topology.Cores -lt 12)) { throw 'Profil double CCD reserve aux Ryzen adequats.' }
        foreach ($role in @('GPU','USB','NETWORK','AUDIO')) {
            if ([int]$layout[$role] -lt 0 -or [int]$layout[$role] -ge $topology.Cores) {
                throw "Coeur $role hors de la plage 0..$($topology.Cores-1)."
            }
        }
        foreach ($role in $layout.Keys) {
            $logical[$role] = [int]($layout[$role] * $topology.Step)
            $masks[$role] = Get-Mask $logical[$role]
        }
    }
    if ($Action -eq 'Plan') {
        Write-Result ([pscustomobject]@{ Success=$true; Action=$Action; Profile=$Profile; Cpu=$topology.Name;
            Cores=$topology.Cores; Logical=$topology.Logical; Layout=$layout; LogicalProcessors=$logical;
            Masks=@{ GPU=[Convert]::ToHexString($masks.GPU); USB=[Convert]::ToHexString($masks.USB);
                NETWORK=[Convert]::ToHexString($masks.NETWORK); AUDIO=[Convert]::ToHexString($masks.AUDIO) };
            Message='Plan uniquement ; aucun reglage modifie.' })
        return
    }
    $targets = @(Get-Targets)
    if (-not $targets.Count) { throw 'Aucun peripherique PCI cible detecte.' }
    $registry = [Microsoft.Win32.Registry]::LocalMachine
    if ($Action -in @('Get','GetDefaults')) {
        $states = foreach ($target in $targets) {
            $key = $registry.OpenSubKey($target.Key,$false)
            try {
                $policy = Read-Value $key 'DevicePolicy'; $mask = Read-Value $key 'AssignmentSetOverride'
                $matches = if ($Action -eq 'GetDefaults') { -not $policy.Exists -and -not $mask.Exists }
                           else {
                               $expected = $masks[$target.Role]
                               $policy.Exists -and [int]$policy.Value -eq 4 -and $mask.Exists -and
                                   $mask.Value -is [byte[]] -and [Linq.Enumerable]::SequenceEqual([byte[]]$mask.Value,[byte[]]$expected)
                           }
                [pscustomobject]@{ Role=$target.Role; Name=$target.Name; Id=$target.Id; Matches=$matches; Pinned=($policy.Exists -and [int]$policy.Value -eq 4) }
            } finally { if ($key) { $key.Dispose() } }
        }
        $matching = @($states | Where-Object Matches).Count
        $rss = @()
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
        if ($Action -eq 'Get') { $adapters = @($adapters | Where-Object Status -eq 'Up') }
        foreach ($adapter in $adapters) {
            try {
                $config = Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop
                $wanted = if ($Action -eq 'GetDefaults') { 0 } else { [int]$logical.NETWORK }
                $rss += [pscustomobject]@{ Name=$adapter.Name; BaseProcessorNumber=[int]$config.BaseProcessorNumber;
                    Matches=([int]$config.BaseProcessorNumber -eq $wanted) }
            } catch { $rss += [pscustomobject]@{ Name=$adapter.Name; BaseProcessorNumber=$null; Matches=$false; Error=$_.Exception.Message } }
        }
        $rssMatches = @($rss | Where-Object Matches).Count
        $applied = $matching -eq $states.Count -and $rssMatches -eq $rss.Count
        Write-Result ([pscustomobject]@{ Success=$true; Action=$Action; Profile=$Profile; Matching=$matching; Total=$states.Count;
            Applied=$applied; Devices=$states; Rss=$rss;
            Message="$matching/$($states.Count) peripheriques et $rssMatches/$($rss.Count) cartes RSS correspondent $(if ($Action -eq 'GetDefaults') {'aux reglages sans affinite forcee'} else {"au profil $Profile"})." })
        return
    }
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Droits administrateur requis.' }
    $changed = 0
    $history = @()
    foreach ($target in $targets) {
        $key = if ($Action -eq 'Enable') { $registry.CreateSubKey($target.Key,$true) }
               else { $registry.OpenSubKey($target.Key,$true) }
        if ($Action -eq 'Disable' -and -not $key) { continue }
        if (-not $key) { throw "Cle du peripherique inaccessible : $($target.Name)" }
        try {
            $beforePolicy = Read-Value $key 'DevicePolicy'
            $beforeMask = Read-Value $key 'AssignmentSetOverride'
            try {
                if ($Action -eq 'Enable') {
                    $key.SetValue('DevicePolicy',4,[Microsoft.Win32.RegistryValueKind]::DWord)
                    $key.SetValue('AssignmentSetOverride',[byte[]]$masks[$target.Role],[Microsoft.Win32.RegistryValueKind]::Binary)
                } else {
                    $key.DeleteValue('DevicePolicy',$false)
                    $key.DeleteValue('AssignmentSetOverride',$false)
                }
                $history += [pscustomobject]@{ Key=$target.Key; Policy=$beforePolicy; Mask=$beforeMask }
                $changed++
            } catch {
                Restore-Value $key 'DevicePolicy' $beforePolicy
                Restore-Value $key 'AssignmentSetOverride' $beforeMask
                throw
            }
        } finally { $key.Dispose() }
    }
    $rssErrors = @()
    $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
    if ($Action -eq 'Enable') { $adapters = @($adapters | Where-Object Status -eq 'Up') }
    foreach ($adapter in $adapters) {
        try {
            Set-NetAdapterRss -Name $adapter.Name -BaseProcessorNumber $(if ($Action -eq 'Enable') { $logical.NETWORK } else { 0 }) -ErrorAction Stop
        } catch { $rssErrors += "$($adapter.Name): $($_.Exception.Message)" }
    }
    $ok = $rssErrors.Count -eq 0
    $verb = if ($Action -eq 'Enable') { 'applique' } else { 'retire' }
    $message = "Profil $Profile : affinite $verb pour $changed peripheriques. Redemarrage requis."
    if (-not $ok) { $message += ' RSS non confirme : ' + ($rssErrors -join '; ') }
    Write-Result ([pscustomobject]@{ Success=$ok; Action=$Action; Profile=$Profile; Changed=$changed; RssErrors=$rssErrors; Message=$message })
    if (-not $ok) { exit 2 }
} catch {
    $message = 'Affinite des interruptions : ' + $_.Exception.Message
    if ($history) {
        foreach ($record in @($history)[($history.Count-1)..0]) {
            $rollbackKey = $null
            try {
                $rollbackKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($record.Key,$true)
                if ($rollbackKey) {
                    Restore-Value $rollbackKey 'DevicePolicy' $record.Policy
                    Restore-Value $rollbackKey 'AssignmentSetOverride' $record.Mask
                }
            } catch { $message += ' Retour arriere incomplet : ' + $_.Exception.Message }
            finally { if ($rollbackKey) { $rollbackKey.Dispose() } }
        }
    }
    Write-Result ([pscustomobject]@{ Success=$false; Action=$Action; Profile=$Profile; Message=$message })
    exit 1
}
