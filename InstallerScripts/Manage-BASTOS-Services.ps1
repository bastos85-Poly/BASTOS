[CmdletBinding()]
param(
    [ValidateSet('Get','Apply','Restore')][string]$Action='Get',
    [string]$ExpectedSnapshotHash='',
    [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($module in @('Microsoft.PowerShell.Utility','Microsoft.PowerShell.Management','Microsoft.PowerShell.Security','CimCmdlets')){
    Import-Module (Join-Path $PSHOME ('Modules\'+$module+'\'+$module+'.psd1')) -ErrorAction Stop
}

function Get-AtomCatalog {
    $catalog=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Bastos.AtomServices.psd1')
    if($catalog.Schema -ne 1 -or $catalog.Profile -ne 'atom-0.0.8-all'){throw 'Invalid service catalog.'}
    foreach($name in $catalog.Names){if($name -notmatch '^[a-zA-Z0-9_.-]+$'){throw 'Invalid service name.'}}
    return $catalog
}
function Test-AtomTemplateType([int]$type) {
    # SERVICE_USER_SERVICE, without USER_INSTANCE or any driver flag.
    return (($type -band 0x40) -ne 0 -and ($type -band 0x80) -eq 0 -and ($type -band 0x30) -ne 0 -and ($type -band 3) -eq 0)
}
function Get-AtomTemplate($name) {
    $path='HKLM:\SYSTEM\CurrentControlSet\Services\'+$name
    if(-not(Test-Path -LiteralPath $path)){return $null}
    $key=Get-Item -LiteralPath $path -ErrorAction Stop
    $type=$key.GetValue('Type',$null)
    if($null -eq $type -or -not(Test-AtomTemplateType ([int]$type))){return $null}
    $start=$key.GetValue('Start',$null)
    $mode=switch($start){2{'Auto'} 3{'Manual'} 4{'Disabled'} default{throw ('Unsupported user template startup: '+$name)}}
    [pscustomobject]@{Name=$name;Type=[int]$type;StartMode=$mode}
}
function Get-AtomPlan($catalog) {
    $services=@(Get-CimInstance Win32_Service -ErrorAction Stop)
    $rows=@(foreach($name in $catalog.Names){
        $matches=@($services|Where-Object { $_.Name -ieq $name -or $_.Name -imatch ('^'+[regex]::Escape($name)+'_[0-9a-f]+$') })
        $template=Get-AtomTemplate $name
        if($null -ne $template){
            $display=if($matches.Count){[string]$matches[0].DisplayName -replace '_[0-9a-f]+$',''}else{$name}
            [pscustomobject]@{Name=$name;DisplayName=$display;Present=$true;StartMode=$template.StartMode;State='Template';TargetKind='UserTemplate';InstanceCount=$matches.Count;Outcome='Detected';Error=''}
            continue
        }
        if(-not $matches.Count){[pscustomobject]@{Name=$name;DisplayName='';Present=$false;StartMode='';State='';TargetKind='Service';InstanceCount=0;Outcome='Unavailable';Error=''};continue}
        foreach($service in $matches){
            $kind=if($service.Name -ine $name){'UserInstance'}else{'Service'}
            [pscustomobject]@{Name=[string]$service.Name;DisplayName=[string]$service.DisplayName;Present=$true;StartMode=[string]$service.StartMode;State=[string]$service.State;TargetKind=$kind;InstanceCount=0;Outcome='Detected';Error=''}
        }
    })
    # Win32_Service excludes kernel and file-system drivers. Never write driver Start values.
    return @($rows|Sort-Object Name -Unique)
}
function Get-AtomSnapshotHash($rows) {
    $text=(@($rows|Where-Object TargetKind -ne 'LegacyInstance'|Sort-Object Name|ForEach-Object {$_.Name.ToLowerInvariant()+'|'+$_.Present+'|'+$_.StartMode+'|'+$_.TargetKind}) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}
}
function Write-AtomDocument($path,$document) {
    $parent=Split-Path -Parent $path;[IO.Directory]::CreateDirectory($parent)|Out-Null
    for($cursor=[IO.Path]::GetFullPath($parent);$cursor;$cursor=Split-Path -Parent $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked journal path refused.'}}
    $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($document|ConvertTo-Json -Depth 12))
        $stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,($path+'.previous'))}else{[IO.File]::Move($tmp,$path)}
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Get-AtomDelayedStart($name) {
    $key=Get-Item -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$name) -ErrorAction Stop
    $exists=$key.GetValueNames() -contains 'DelayedAutoStart'
    [pscustomobject]@{Exists=$exists;Value=$(if($exists){[int]$key.GetValue('DelayedAutoStart')}else{0})}
}
function Get-AtomCurrentMode($name,$kind) {
    if($kind -eq 'UserTemplate'){
        $template=Get-AtomTemplate $name
        if($null -eq $template){throw 'User service template no longer available.'}
        return $template.StartMode
    }
    $service=Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction Stop
    if($null -eq $service){throw 'Service no longer available.'}
    return $service.StartMode
}
function Test-AtomOriginal($row,$entry) {
    return ((Get-AtomCurrentMode $row.Name $row.TargetKind) -eq $entry.OriginalMode -and ((Get-AtomDelayedStart $row.Name|ConvertTo-Json -Compress) -eq ($entry.Delayed|ConvertTo-Json -Compress)))
}
function Set-AtomStartMode($name,$mode,$delayed=$null,$kind='Service') {
    $startup=switch($mode){'Auto'{'Automatic'} 'Manual'{'Manual'} 'Disabled'{'Disabled'} default{throw 'Unsupported service startup mode.'}}
    if($kind -eq 'UserTemplate'){
        $template=Get-AtomTemplate $name
        if($null -eq $template){throw 'User service template no longer available.'}
        $start=switch($mode){'Auto'{2} 'Manual'{3} 'Disabled'{4}}
        New-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$name) -Name Start -PropertyType DWord -Value $start -Force -ErrorAction Stop|Out-Null
        $verified=Get-AtomTemplate $name
        if($null -eq $verified -or $verified.Type -ne $template.Type -or $verified.StartMode -ne $mode){throw 'User template startup verification failed.'}
    }elseif($kind -in @('UserInstance','LegacyInstance')){
        throw 'User service template unavailable; no instance was modified.'
    }else{Set-Service -Name $name -StartupType $startup -ErrorAction Stop}
    if($null -ne $delayed){
        $path='HKLM:\SYSTEM\CurrentControlSet\Services\'+$name
        $actual=Get-AtomDelayedStart $name
        if($actual.Exists -ne $delayed.Exists -or ($actual.Exists -and $actual.Value -ne $delayed.Value)){
            if($delayed.Exists){New-ItemProperty -LiteralPath $path -Name DelayedAutoStart -PropertyType DWord -Value ([int]$delayed.Value) -Force -ErrorAction Stop|Out-Null}
            else{Remove-ItemProperty -LiteralPath $path -Name DelayedAutoStart -ErrorAction Stop}
        }
        $actual=Get-AtomDelayedStart $name
        if($actual.Exists -ne $delayed.Exists -or ($actual.Exists -and $actual.Value -ne $delayed.Value)){throw 'Delayed startup verification failed.'}
    }
    if((Get-AtomCurrentMode $name $kind) -ne $mode){throw 'Service startup verification failed.'}
}
function Invoke-AtomChanges($action,$rows,$journal,$journalPath) {
    foreach($row in $rows){
        if(-not $row.Present){continue}
        $saved=@($journal.Entries|Where-Object Name -ieq $row.Name)
        $entry=$null
        try {
            if($action -eq 'Apply'){
                if($row.StartMode -eq 'Disabled'){$row.Outcome='AlreadyDisabled';continue}
                if($row.StartMode -notin @('Auto','Manual')){throw 'Unsupported original startup mode.'}
                if($saved.Count -and $saved[0].Restored -ne $true){
                    $entry=$saved[0]
                    $state=if($entry.PSObject.Properties['WriteState']){$entry.WriteState}else{'Legacy'}
                    if($state -eq 'Applied' -or -not(Test-AtomOriginal $row $entry)){$row.Outcome='Conflict';throw 'Service changed after a previous application; restore or review it first.'}
                    # Reuse the original durable backup after a refused/interrupted write.
                }else{
                    $entry=[pscustomobject]@{Name=$row.Name;OriginalMode=$row.StartMode;Delayed=(Get-AtomDelayedStart $row.Name);Restored=$false;WriteState='Pending'}
                    $journal.Entries=@($journal.Entries|Where-Object Name -ine $row.Name)+@($entry)
                }
                $entry|Add-Member -NotePropertyName WriteState -NotePropertyValue Pending -Force
                # Durable backup BEFORE every service write, including interrupted/failed writes.
                Write-AtomDocument $journalPath $journal
                Set-AtomStartMode $row.Name 'Disabled' $null $row.TargetKind
                $row.Outcome='Disabled';$row.StartMode='Disabled'
                $entry.WriteState='Applied';Write-AtomDocument $journalPath $journal
            }else{
                if(-not $saved.Count -or $saved[0].Restored){$row.Outcome='NoBackup';continue}
                $entry=$saved[0]
                if($row.StartMode -ne 'Disabled'){
                    if(Test-AtomOriginal $row $entry){$entry.Restored=$true;Write-AtomDocument $journalPath $journal;$row.Outcome='Restored';continue}
                    $row.Outcome='Conflict';throw 'Service changed outside BASTOS; restoration refused.'
                }
                Set-AtomStartMode $row.Name $entry.OriginalMode $entry.Delayed $row.TargetKind
                $entry.Restored=$true;Write-AtomDocument $journalPath $journal
                $row.Outcome='Restored';$row.StartMode=$entry.OriginalMode
            }
        }catch{
            $failure=$_.Exception
            if($row.Outcome -ne 'Conflict'){
                $row.Outcome='Failed'
                for($cause=$failure;$null -ne $cause;$cause=$cause.InnerException){
                    if($cause -is [UnauthorizedAccessException] -or ($cause.PSObject.Properties['NativeErrorCode'] -and $cause.NativeErrorCode -eq 5)){$row.Outcome='Denied';break}
                }
            }
            $row.Error=$failure.Message
            if($action -eq 'Apply' -and $null -ne $entry -and $row.Outcome -ne 'Conflict'){
                try{
                    if(Test-AtomOriginal $row $entry){$entry|Add-Member -NotePropertyName WriteState -NotePropertyValue Unchanged -Force;Write-AtomDocument $journalPath $journal}
                }catch{} # Never hide the original refusal or claim an unverified write succeeded.
            }
        }
    }
    return @($rows)
}

$mutex=$null;$held=$false
try {
    $catalog=Get-AtomCatalog
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $journalRoot=Join-Path $env:ProgramData ('BASTOS\ServiceProfiles\'+$sid)
    $journalPath=Join-Path $journalRoot 'atom-all.json'
    $rows=@(Get-AtomPlan $catalog);$snapshot=Get-AtomSnapshotHash $rows
    if($Action -ne 'Get'){
        if(-not([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){throw 'Administrator rights required.'}
        $mutex=[Threading.Mutex]::new($false,'Global\BASTOS-AtomServices')
        try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Another service operation is running.'}
        $rows=@(Get-AtomPlan $catalog);$snapshot=Get-AtomSnapshotHash $rows
        if($Action -eq 'Apply' -and (-not $ExpectedSnapshotHash -or $ExpectedSnapshotHash -cne $snapshot)){throw 'Service state changed; analyze again before applying.'}
        # Restore compares each backed-up service below. Unrelated startup drift
        # must not prevent recovery of the rest of the profile.
        [IO.Directory]::CreateDirectory($journalRoot)|Out-Null
        for($cursor=[IO.Path]::GetFullPath($journalRoot);$cursor;$cursor=Split-Path -Parent $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked journal path refused.'}}
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
        foreach($identity in @('S-1-5-18','S-1-5-32-544',$sid)){$rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($identity),'FullControl','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)}
        Set-Acl -LiteralPath $journalRoot -AclObject $acl
        $journal=if(Test-Path -LiteralPath $journalPath){Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json}else{[pscustomobject]@{Schema=1;Profile=$catalog.Profile;Entries=@()}}
        if($journal.Schema -ne 1 -or $journal.Profile -ne $catalog.Profile){throw 'Invalid backup journal.'}
        $seen=@{}
        foreach($entry in $journal.Entries){
            $known=@($catalog.Names|Where-Object {$entry.Name -ieq $_ -or $entry.Name -imatch ('^'+[regex]::Escape($_)+'_[0-9a-f]+$')})
            if(-not $known.Count -or $seen.ContainsKey($entry.Name) -or $entry.OriginalMode -notin @('Auto','Manual','Disabled')){throw 'Invalid backup entry.'}
            $seen[$entry.Name]=$true
        }
        if($Action -eq 'Restore'){
            # Version 138 backed up session instances before Windows refused them.
            # Retain exact legacy entries for safe no-op restoration, never infer a new target.
            $current=@(Get-CimInstance Win32_Service -ErrorAction Stop)
            foreach($entry in $journal.Entries){
                if($entry.Restored -or $entry.Name -in @($rows.Name)){continue}
                $legacy=@($current|Where-Object Name -ieq $entry.Name)
                if($legacy.Count -eq 1 -and $entry.Name -match '_[0-9a-f]+$'){
                    $s=$legacy[0]
                    $rows+= [pscustomobject]@{Name=$s.Name;DisplayName=$s.DisplayName;Present=$true;StartMode=$s.StartMode;State=$s.State;TargetKind='LegacyInstance';InstanceCount=0;Outcome='Detected';Error=''}
                }
            }
        }
        $rows=@(Invoke-AtomChanges $Action $rows $journal $journalPath)
        # Refresh the complete preview from Windows, including partial/denied writes
        # and per-user service instances created while the operation was running.
        $outcomes=@{};foreach($row in $rows){$outcomes[$row.Name]=$row}
        $rows=@(Get-AtomPlan $catalog)
        foreach($row in $rows){if($outcomes.ContainsKey($row.Name)){$row.Outcome=$outcomes[$row.Name].Outcome;$row.Error=$outcomes[$row.Name].Error}}
        foreach($previous in $outcomes.Values){if($previous.Name -notin @($rows.Name) -and $previous.TargetKind -eq 'LegacyInstance'){$rows+=$previous}}
    }
    $failed=@($rows|Where-Object Outcome -in @('Failed','Denied','Conflict')).Count
    $changed=@($rows|Where-Object Outcome -in @('Disabled','Restored')).Count
    $report=[ordered]@{Success=($failed -eq 0);Action=$Action;SnapshotHash=(Get-AtomSnapshotHash $rows);CatalogCount=@($catalog.Names).Count;Present=@($rows|Where-Object Present).Count;Unavailable=@($rows|Where-Object {-not $_.Present}).Count;Disabled=@($rows|Where-Object {$_.Present -and $_.StartMode -eq 'Disabled'}).Count;Failed=$failed;Denied=@($rows|Where-Object Outcome -eq 'Denied').Count;Conflicts=@($rows|Where-Object Outcome -eq 'Conflict').Count;Errors=@($rows|Where-Object Outcome -eq 'Failed').Count;Rows=@($rows);RestartRequired=($Action -ne 'Get' -and $changed -gt 0);Error=''}
    Write-AtomDocument $ResultPath $report
}catch{
    Write-AtomDocument $ResultPath ([ordered]@{Success=$false;Action=$Action;SnapshotHash='';CatalogCount=0;Present=0;Unavailable=0;Disabled=0;Failed=1;Rows=@();RestartRequired=$false;Error=$_.Exception.Message})
    exit 1
}finally{if($mutex){if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}}
