[CmdletBinding()]
param(
    [ValidateSet('Machine','User','Both')]
    [string]$Scope = 'Both',

    [ValidateRange(10,300)]
    [int]$TimeoutSeconds = 90,

    [switch]$DeleteUserData,

    [string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [Collections.Generic.List[string]]::new()
$attempts = [Collections.Generic.List[object]]::new()
$removedRegistry = [Collections.Generic.List[string]]::new()
$removedDirectories = [Collections.Generic.List[string]]::new()

function Get-BastosOneDriveRegistryRoots {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    $roots = @()
    if ($RequestedScope -in @('User','Both')) {
        $roots += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    }
    if ($RequestedScope -in @('Machine','Both')) {
        $roots += 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
        $roots += 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    }
    return $roots
}

function Get-BastosOneDriveUninstallEntries {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    $entries = @()
    foreach ($root in @(Get-BastosOneDriveRegistryRoots -RequestedScope $RequestedScope)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ([string]$item.DisplayName -notmatch '(?i)^Microsoft OneDrive(?:$|\s)') { continue }
                $entries += [pscustomobject]@{
                    RegistryPath = $key.PSPath
                    DisplayName = [string]$item.DisplayName
                    UninstallString = [string]$item.UninstallString
                }
            } catch {}
        }
    }
    return $entries
}

function Test-BastosTrustedOneDriveSetupPath {
    param([Parameter(Mandatory)][string]$Path)
    try { $fullPath = [IO.Path]::GetFullPath($Path) } catch { return $false }
    if ([IO.Path]::GetFileName($fullPath) -ine 'OneDriveSetup.exe') { return $false }
    $trustedRoots = @(
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive' }),
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft OneDrive' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive' }),
        $(if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32' }),
        $(if ($env:SystemRoot) { Join-Path $env:SystemRoot 'SysWOW64' })
    ) | Where-Object { $_ }
    foreach ($root in $trustedRoots) {
        try {
            $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
            if ($fullPath.Equals((Join-Path $fullRoot 'OneDriveSetup.exe'), [StringComparison]::OrdinalIgnoreCase) -or
                $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } catch {}
    }
    return $false
}

function ConvertFrom-BastosOneDriveUninstallString {
    param([string]$Command)
    if (-not $Command) { return $null }
    $executable = ''
    $arguments = ''
    if ($Command -match '^\s*"(?<exe>[^"]+OneDriveSetup\.exe)"\s*(?<args>.*)$') {
        $executable = $Matches.exe
        $arguments = $Matches.args
    } elseif ($Command -match '^\s*(?<exe>\S*OneDriveSetup\.exe)\s*(?<args>.*)$') {
        $executable = $Matches.exe
        $arguments = $Matches.args
    } else { return $null }
    if ($arguments -notmatch '(?i)(?:^|\s)/uninstall(?:\s|$)') { return $null }
    if (-not (Test-BastosTrustedOneDriveSetupPath -Path $executable)) { return $null }
    return [pscustomobject]@{ Path=[IO.Path]::GetFullPath($executable); Arguments=$arguments.Trim() }
}

function Get-BastosOneDriveCandidates {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    $candidates = @()
    foreach ($entry in @(Get-BastosOneDriveUninstallEntries -RequestedScope $RequestedScope)) {
        $parsed = ConvertFrom-BastosOneDriveUninstallString -Command $entry.UninstallString
        if ($parsed -and (Test-Path -LiteralPath $parsed.Path -PathType Leaf)) { $candidates += $parsed }
    }
    if ($RequestedScope -in @('User','Both')) {
        $localRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'
        if (Test-Path -LiteralPath $localRoot -PathType Container) {
            foreach ($setup in @(Get-ChildItem -LiteralPath $localRoot -Filter 'OneDriveSetup.exe' -File -Recurse -ErrorAction SilentlyContinue)) {
                $candidates += [pscustomobject]@{ Path=$setup.FullName; Arguments='/uninstall' }
            }
        }
    }
    if ($RequestedScope -in @('Machine','Both')) {
        foreach ($setupPath in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDriveSetup.exe'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDriveSetup.exe' })
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }) {
            $candidates += [pscustomobject]@{ Path=$setupPath; Arguments='/uninstall' }
        }
    }
    $seen = @{}
    return @($candidates | Where-Object {
        if (-not (Test-BastosTrustedOneDriveSetupPath -Path $_.Path)) { return $false }
        $key = ('{0}|{1}' -f ([IO.Path]::GetFullPath($_.Path).ToLowerInvariant()),([string]$_.Arguments).ToLowerInvariant())
        if ($seen.ContainsKey($key)) { return $false }
        $seen[$key] = $true
        return $true
    })
}

function Get-BastosOneDriveRuntimeRemnants {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    $remaining = [Collections.Generic.List[string]]::new()
    if ($RequestedScope -in @('User','Both')) {
        $userExecutable = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
        if (Test-Path -LiteralPath $userExecutable -PathType Leaf) { $remaining.Add($userExecutable) }
    }
    if ($RequestedScope -in @('Machine','Both')) {
        foreach ($machineRoot in @(
            (Join-Path $env:ProgramFiles 'Microsoft OneDrive'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive' })
        ) | Where-Object { $_ }) {
            $machineExecutable = Join-Path $machineRoot 'OneDrive.exe'
            if (Test-Path -LiteralPath $machineExecutable -PathType Leaf) { $remaining.Add($machineExecutable) }
        }
    }
    foreach ($entry in @(Get-BastosOneDriveUninstallEntries -RequestedScope $RequestedScope)) {
        $remaining.Add(('registre de desinstallation: {0}' -f $entry.RegistryPath))
    }
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
                [string]$_.TaskName -like 'OneDrive*' -and
                ($RequestedScope -in @('Machine','Both') -or [string]$_.TaskName -like "*-$currentSid")
            })) { $remaining.Add(('tache planifiee: {0}{1}' -f $task.TaskPath,$task.TaskName)) }
        } catch {}
    }
    return @($remaining | Select-Object -Unique)
}

function Remove-BastosOneDriveScheduledTasks {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -or
        -not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            [string]$_.TaskName -like 'OneDrive*' -and
            ($RequestedScope -in @('Machine','Both') -or [string]$_.TaskName -like "*-$currentSid")
        })) {
            try { Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop }
            catch { $errors.Add(("Impossible de retirer la tache OneDrive {0}{1} : {2}" -f $task.TaskPath,$task.TaskName,$_.Exception.Message)) }
        }
    } catch { $errors.Add(("Lecture des taches OneDrive impossible : {0}" -f $_.Exception.Message)) }
}

function Invoke-BastosOneDriveCandidate {
    param([Parameter(Mandatory)]$Candidate)
    $exitCode = $null
    $timedOut = $false
    try {
        $process = Start-Process -FilePath $Candidate.Path -ArgumentList $Candidate.Arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        } else { $exitCode = $process.ExitCode }
    } catch { $exitCode = -1 }
    $attempts.Add([pscustomobject]@{ Path=$Candidate.Path; Arguments=$Candidate.Arguments; ExitCode=$exitCode; TimedOut=$timedOut })
    Start-Sleep -Seconds 3
}

function Remove-BastosRegistryTree {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        $removedRegistry.Add($Path)
    } catch { $errors.Add(("Suppression registre impossible {0} : {1}" -f $Path,$_.Exception.Message)) }
}

function Remove-BastosRegistryProperties {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][scriptblock]$Predicate)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        foreach ($property in @($item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
            if (& $Predicate ([string]$property.Name) $property.Value) {
                Remove-ItemProperty -LiteralPath $Path -Name $property.Name -Force -ErrorAction Stop
                $removedRegistry.Add(("{0}::{1}" -f $Path,$property.Name))
            }
        }
    } catch { $errors.Add(("Nettoyage registre impossible {0} : {1}" -f $Path,$_.Exception.Message)) }
}

function Restore-BastosKnownFoldersOutsideOneDrive {
    $personalRoot = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'OneDrive')).TrimEnd('\')
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if (-not (Test-Path -LiteralPath $key)) { return }
    $targets = [ordered]@{
        Desktop='%USERPROFILE%\Desktop'
        Personal='%USERPROFILE%\Documents'
        'My Pictures'='%USERPROFILE%\Pictures'
        'My Music'='%USERPROFILE%\Music'
        'My Video'='%USERPROFILE%\Videos'
        '{374DE290-123F-4565-9164-39C4925E467B}'='%USERPROFILE%\Downloads'
    }
    foreach ($name in $targets.Keys) {
        try {
            $current = [string](Get-ItemPropertyValue -LiteralPath $key -Name $name -ErrorAction Stop)
            $expanded = [Environment]::ExpandEnvironmentVariables($current)
            $full = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
            if ($full.Equals($personalRoot,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($personalRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
                $target = [string]$targets[$name]
                $targetExpanded = [Environment]::ExpandEnvironmentVariables($target)
                New-Item -ItemType Directory -Path $targetExpanded -Force | Out-Null
                New-ItemProperty -LiteralPath $key -Name $name -PropertyType ExpandString -Value $target -Force | Out-Null
                $removedRegistry.Add(("{0}::{1} redirige vers {2}" -f $key,$name,$target))
            }
        } catch [System.Management.Automation.PSArgumentException] {} catch [System.Management.Automation.ItemNotFoundException] {} catch {
            $errors.Add(("Restauration du dossier connu {0} impossible : {1}" -f $name,$_.Exception.Message))
        }
    }
}

function Remove-BastosExactDirectoryTree {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedPath)
    try {
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $fullExpected = [IO.Path]::GetFullPath($ExpectedPath).TrimEnd('\')
        $root = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
        if (-not $fullPath.Equals($fullExpected,[StringComparison]::OrdinalIgnoreCase) -or $fullPath.Equals($root,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Chemin refuse par la protection BASTOS : $fullPath"
        }
        if (-not (Test-Path -LiteralPath $fullPath)) { return }

        function Remove-BastosDirectoryNode([string]$NodePath) {
            $item = Get-Item -LiteralPath $NodePath -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName,$false) }
                else { [IO.File]::Delete($item.FullName) }
                return
            }
            if ($item.PSIsContainer) {
                foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) {
                    Remove-BastosDirectoryNode -NodePath $child.FullName
                }
                [IO.File]::SetAttributes($item.FullName,[IO.FileAttributes]::Directory)
                [IO.Directory]::Delete($item.FullName,$false)
            } else {
                [IO.File]::SetAttributes($item.FullName,[IO.FileAttributes]::Normal)
                [IO.File]::Delete($item.FullName)
            }
        }

        Remove-BastosDirectoryNode -NodePath $fullPath
        $removedDirectories.Add($fullPath)
    } catch { $errors.Add(("Suppression du dossier OneDrive refusee ou impossible {0} : {1}" -f $Path,$_.Exception.Message)) }
}

function Remove-BastosOneDriveOwnedRegistry {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    if ($RequestedScope -in @('User','Both')) {
        $personalRoot = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'OneDrive'))
        $localRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'))

        foreach ($path in @(
            'HKCU:\Software\Microsoft\OneDrive',
            'HKCU:\Software\Policies\Microsoft\OneDrive',
            'HKCU:\Software\Classes\grvopen',
            'HKCU:\Software\Classes\odopen',
            'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'HKCU:\Software\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        )) { Remove-BastosRegistryTree -Path $path }

        foreach ($parent in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'HKCU:\Software\SyncEngines\Providers'
        )) {
            if (Test-Path -LiteralPath $parent) {
                foreach ($child in @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'OneDrive*' })) {
                    Remove-BastosRegistryTree -Path $child.PSPath
                }
            }
        }

        foreach ($path in @(
            'HKCU:\Environment',
            'HKCU:\Volatile Environment'
        )) { Remove-BastosRegistryProperties -Path $path -Predicate { param($name,$value) $name -match '(?i)^OneDrive(?:$|Consumer$|Commercial$)' } }

        foreach ($path in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
            'HKCU:\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU:\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
            'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store',
            'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
        )) {
            Remove-BastosRegistryProperties -Path $path -Predicate {
                param($name,$value)
                $data = (@($value) -join ';')
                $name -match '(?i)OneDrive|Microsoft\.OneDrive' -or $data.IndexOf($personalRoot,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $data.IndexOf($localRoot,[StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        }

        Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' -Name 'IsOneDriveResumeAllowed' -Force -ErrorAction SilentlyContinue
        $winlogonPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
        try {
            $excluded = [string](Get-ItemPropertyValue -LiteralPath $winlogonPath -Name 'ExcludeProfileDirs' -ErrorAction Stop)
            $filtered = @(($excluded -split ';') | Where-Object { $_.Trim() -and $_.Trim() -ine 'OneDrive' }) -join ';'
            if ($filtered -ne $excluded) {
                Set-ItemProperty -LiteralPath $winlogonPath -Name 'ExcludeProfileDirs' -Value $filtered -Force
                $removedRegistry.Add(("{0}::ExcludeProfileDirs/OneDrive" -f $winlogonPath))
            }
        } catch {}

        foreach ($entry in @(Get-BastosOneDriveUninstallEntries -RequestedScope User)) { Remove-BastosRegistryTree -Path $entry.RegistryPath }
    }

    if ($RequestedScope -in @('Machine','Both')) {
        foreach ($path in @(
            'HKLM:\SOFTWARE\Microsoft\OneDrive',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive'
        )) { Remove-BastosRegistryTree -Path $path }
        foreach ($entry in @(Get-BastosOneDriveUninstallEntries -RequestedScope Machine)) { Remove-BastosRegistryTree -Path $entry.RegistryPath }
    }
}

function Get-BastosOneDriveOwnedRemnants {
    param([ValidateSet('Machine','User','Both')][string]$RequestedScope)
    $remaining = [Collections.Generic.List[string]]::new()
    foreach ($item in @(Get-BastosOneDriveRuntimeRemnants -RequestedScope $RequestedScope)) { $remaining.Add($item) }
    if ($RequestedScope -in @('User','Both')) {
        if ($DeleteUserData) {
            $personal = Join-Path $env:USERPROFILE 'OneDrive'
            if (Test-Path -LiteralPath $personal) { $remaining.Add($personal) }
        }
        foreach ($path in @(
            'HKCU:\Software\Microsoft\OneDrive',
            'HKCU:\Software\Policies\Microsoft\OneDrive',
            'HKCU:\Software\Classes\grvopen',
            'HKCU:\Software\Classes\odopen',
            'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        )) { if (Test-Path -LiteralPath $path) { $remaining.Add(("registre: $path")) } }
        foreach ($path in @('HKCU:\Environment','HKCU:\Volatile Environment')) {
            if (Test-Path -LiteralPath $path) {
                foreach ($name in @((Get-ItemProperty -LiteralPath $path).PSObject.Properties.Name | Where-Object { $_ -match '(?i)^OneDrive(?:$|Consumer$|Commercial$)' })) {
                    $remaining.Add(("registre: {0}::{1}" -f $path,$name))
                }
            }
        }
    }
    if ($RequestedScope -in @('Machine','Both')) {
        foreach ($path in @('HKLM:\SOFTWARE\Microsoft\OneDrive','HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive')) {
            if (Test-Path -LiteralPath $path) { $remaining.Add(("registre: $path")) }
        }
    }
    return @($remaining | Select-Object -Unique)
}

Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-BastosOneDriveScheduledTasks -RequestedScope $Scope
$before = @(Get-BastosOneDriveRuntimeRemnants -RequestedScope $Scope)
if ($before.Count -gt 0) {
    foreach ($candidate in @(Get-BastosOneDriveCandidates -RequestedScope $Scope)) {
        if (@(Get-BastosOneDriveRuntimeRemnants -RequestedScope $Scope).Count -eq 0) { break }
        Invoke-BastosOneDriveCandidate -Candidate $candidate
    }
}

Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-BastosOneDriveScheduledTasks -RequestedScope $Scope

if ($Scope -in @('User','Both')) {
    Restore-BastosKnownFoldersOutsideOneDrive
}
Remove-BastosOneDriveOwnedRegistry -RequestedScope $Scope

if ($Scope -in @('User','Both')) {
    $localRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'
    Remove-BastosExactDirectoryTree -Path $localRoot -ExpectedPath $localRoot
    foreach ($shortcut in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'),
        (Join-Path $env:USERPROFILE 'Desktop\OneDrive.lnk')
    )) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }
    if ($DeleteUserData) {
        $personalRoot = Join-Path $env:USERPROFILE 'OneDrive'
        Remove-BastosExactDirectoryTree -Path $personalRoot -ExpectedPath $personalRoot
    }
}
if ($Scope -in @('Machine','Both')) {
    foreach ($machineRoot in @(
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive' })
    ) | Where-Object { $_ }) { Remove-BastosExactDirectoryTree -Path $machineRoot -ExpectedPath $machineRoot }
    Remove-Item -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\OneDrive.lnk') -Force -ErrorAction SilentlyContinue
}

$remaining = @(Get-BastosOneDriveOwnedRemnants -RequestedScope $Scope)
if ($remaining.Count -gt 0) { $errors.Add(('Restes OneDrive apres nettoyage : {0}' -f ($remaining -join ', '))) }
$success = $remaining.Count -eq 0 -and $errors.Count -eq 0
$result = [pscustomobject]@{
    Success = $success
    Scope = $Scope
    PresentBefore = $before
    Remaining = $remaining
    Attempts = @($attempts)
    Errors = @($errors)
    RegistryEntriesRemoved = @($removedRegistry)
    DirectoriesRemoved = @($removedDirectories)
    UserDataDeleted = [bool]($DeleteUserData -and $Scope -in @('User','Both') -and -not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'OneDrive')))
    CheckedUtc = [DateTime]::UtcNow.ToString('o')
}

if ($ResultPath) {
    $parent = Split-Path -Parent $ResultPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($ResultPath, ($result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
return $result
