[CmdletBinding()]
param([string]$SourceRoot='')
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path -Parent $PSScriptRoot}
$worker=Join-Path $SourceRoot 'InstallerScripts/Manage-BASTOS-Services.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Service worker parse error.'}
# Load only definitions, never the privileged entry point.
foreach($function in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($function.Extent.Text))
}
$script:checks=0
function Check($ok,$name){if(-not $ok){throw $name};$script:checks++;Write-Host ('PASS: '+$name)}
$fixtureFile=Join-Path $env:TEMP ('BASTOS-ServiceJournal-'+[guid]::NewGuid().ToString('N')+'.json')
try {
    Write-AtomDocument $fixtureFile @{Value=1}
    Write-AtomDocument $fixtureFile @{Value=2}
    Check ((Get-Content $fixtureFile -Raw|ConvertFrom-Json).Value -eq 2 -and (Get-Content ($fixtureFile+'.previous') -Raw|ConvertFrom-Json).Value -eq 1) 'Atomic journal replacement on the actual PowerShell runtime'
}finally{foreach($p in @($fixtureFile,($fixtureFile+'.previous'))){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}}
function Reset-Fixture {
    $script:fixtures=@{
        DiagTrack=[pscustomobject]@{Name='DiagTrack';DisplayName='Fixture diagnostics';StartMode='Auto';State='Running'}
        BITS=[pscustomobject]@{Name='BITS';DisplayName='Fixture transfer';StartMode='Manual';State='Stopped'}
        WpnUserService_ab12=[pscustomobject]@{Name='WpnUserService_ab12';DisplayName='Fixture user service';StartMode='Manual';State='Running'}
        Spooler=[pscustomobject]@{Name='Spooler';DisplayName='Fixture printing';StartMode='Disabled';State='Stopped'}
    }
    $script:writes=@();$script:saves=@();$script:saveFails=$false;$script:refused='';$script:delayed=@{}
    $script:templates=@{WpnUserService=[pscustomobject]@{Name='WpnUserService';Type=0x60;StartMode='Manual'}}
    $script:templateWrites=@()
    $script:journal=[pscustomobject]@{Schema=1;Profile='atom-0.0.8-all';Entries=@()}
}
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$Filter)
    if($ClassName -ne 'Win32_Service'){throw 'Unexpected provider.'}
    if($Filter){$name=$Filter.Substring(6,$Filter.Length-7);return $script:fixtures[$name]}
    return @($script:fixtures.Values)
}
function Get-AtomDelayedStart($name){if($script:delayed.ContainsKey($name)){return $script:delayed[$name]};[pscustomobject]@{Exists=$false;Value=0}}
function Get-AtomTemplate($name){return $script:templates[$name]}
function Write-AtomDocument($path,$document){if($script:saveFails){throw 'Fixture disk full'};$script:saves+=($document|ConvertTo-Json -Depth 12 -Compress)}
function Set-Service {
    [CmdletBinding()]param($Name,$StartupType)
    Check ($script:saves.Count -gt 0) 'Backup persisted before service write'
    if($Name -eq $script:refused){throw 'Fixture protected service'}
    $script:writes+=$Name
    $script:fixtures[$Name].StartMode=switch($StartupType){'Automatic'{'Auto'} 'Manual'{'Manual'} 'Disabled'{'Disabled'} default{throw 'Unexpected mode'}}
}
# Override registry adapter only; test the real startup writer and read-back.
function New-ItemProperty {
    [CmdletBinding()]param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force)
    $service=Split-Path $LiteralPath -Leaf
    if($Name -eq 'Start'){
        Check ($script:saves.Count -gt 0) 'Backup persisted before template write'
        if($service -eq $script:refused){throw [UnauthorizedAccessException]::new('Fixture template access denied')}
        $script:templates[$service].StartMode=switch($Value){2{'Auto'} 3{'Manual'} 4{'Disabled'} default{throw 'Unexpected template mode'}}
        $script:templateWrites+=$service
    }else{$script:delayed[$service]=[pscustomobject]@{Exists=$true;Value=$Value}}
}
function Remove-ItemProperty {[CmdletBinding()]param($LiteralPath,$Name);$service=Split-Path $LiteralPath -Leaf;[void]$script:delayed.Remove($service)}
$catalog=Import-PowerShellDataFile (Join-Path $SourceRoot 'InstallerScripts/Bastos.AtomServices.psd1')
Check ($catalog.Names.Count -eq 152 -and @($catalog.Names|Sort-Object -Unique).Count -eq 152) 'Complete deduplicated Atom catalog'
Reset-Fixture
$plan=@(Get-AtomPlan $catalog)
Check ($script:writes.Count -eq 0 -and $script:saves.Count -eq 0) 'Analysis has no side effects'
Check (@($plan|Where-Object {$_.Name -eq 'WpnUserService' -and $_.TargetKind -eq 'UserTemplate' -and $_.InstanceCount -eq 1}).Count -eq 1) 'User instances resolve to their verified template'
Check (@($plan|Where-Object {$_.Name -eq 'WdBoot' -and -not $_.Present}).Count -eq 1) 'Kernel driver is never treated as a Win32 service'
$hash=Get-AtomSnapshotHash $plan
$script:fixtures.DiagTrack.State='Stopped'
Check ((Get-AtomSnapshotHash @(Get-AtomPlan $catalog)) -eq $hash) 'Runtime state does not invalidate startup preview'
$script:fixtures.DiagTrack.StartMode='Manual'
Check ((Get-AtomSnapshotHash @(Get-AtomPlan $catalog)) -ne $hash) 'Startup drift invalidates preview'
Reset-Fixture
$script:delayed.DiagTrack=[pscustomobject]@{Exists=$true;Value=1}
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:writes.Count -eq 2 -and $script:templateWrites.Count -eq 1 -and $script:journal.Entries.Count -eq 3) 'Only present services and verified templates requiring changes are written'
Check ($script:fixtures.WpnUserService_ab12.StartMode -eq 'Manual' -and $script:templates.WpnUserService.StartMode -eq 'Disabled') 'Template disabled without modifying an active session instance'
Check ($script:fixtures.DiagTrack.State -eq 'Running') 'Running services are never stopped'
Check ($script:journal.Entries[0].OriginalMode -in @('Auto','Manual')) 'Original startup settings are preserved'
$saved=$script:journal|ConvertTo-Json -Depth 12 -Compress
$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check (($script:journal|ConvertTo-Json -Depth 12 -Compress) -eq $saved) 'Repeated application preserves the original backup'
$null=Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check ($script:fixtures.DiagTrack.StartMode -eq 'Auto' -and $script:fixtures.BITS.StartMode -eq 'Manual' -and $script:delayed.DiagTrack.Value -eq 1 -and $script:templates.WpnUserService.StartMode -eq 'Manual') 'Exact service, template and delayed-auto values restored'
Check ($script:fixtures.Spooler.StartMode -eq 'Disabled') 'Previously disabled service remains disabled'
Reset-Fixture;$script:saveFails=$true
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:writes.Count -eq 0 -and $script:templateWrites.Count -eq 0 -and @($result|Where-Object Outcome -eq 'Failed').Count -eq 3) 'Backup failure prevents service and template writes'
Reset-Fixture;$script:refused='BITS'
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'BITS' -and $_.Outcome -eq 'Failed'}).Count -eq 1 -and $script:fixtures.BITS.StartMode -eq 'Manual') 'Protected service refusal remains visible'
$script:refused='';$null=Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check (@($script:journal.Entries|Where-Object {-not $_.Restored}).Count -eq 0) 'No-op failed writes can be restored cleanly'
Reset-Fixture;$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
$script:fixtures.DiagTrack.StartMode='Manual';$before=$script:writes.Count
$result=@(Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'DiagTrack' -and $_.Outcome -eq 'Conflict'}).Count -eq 1 -and $script:fixtures.DiagTrack.StartMode -eq 'Manual') 'External changes are preserved and classified separately'
Reset-Fixture;$script:refused='BITS'
$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
$saved=@($script:journal.Entries|Where-Object Name -eq BITS)[0]
Check ($saved.WriteState -eq 'Unchanged') 'Refused unchanged write is recorded accurately'
$original=$saved.OriginalMode;$script:refused=''
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'BITS' -and $_.Outcome -eq 'Disabled'}).Count -eq 1 -and $saved.OriginalMode -eq $original -and $saved.WriteState -eq 'Applied') 'Retry succeeds without replacing the original backup'
Reset-Fixture
$legacy=[pscustomobject]@{Name='BITS';OriginalMode='Manual';Delayed=[pscustomobject]@{Exists=$false;Value=0};Restored=$false}
$script:journal.Entries=@($legacy)
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:fixtures.BITS.StartMode -eq 'Disabled' -and $legacy.OriginalMode -eq 'Manual') 'Version 138 unchanged backup migrates on retry'
Reset-Fixture;$script:refused='BITS'
$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
$script:fixtures.BITS.StartMode='Auto';$script:refused=''
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'BITS' -and $_.Outcome -eq 'Conflict'}).Count -eq 1 -and $script:fixtures.BITS.StartMode -eq 'Auto') 'Retry preserves a genuine external change after a refusal'
Reset-Fixture;$script:refused='WpnUserService'
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'WpnUserService' -and $_.Outcome -eq 'Denied'}).Count -eq 1 -and $script:templates.WpnUserService.StartMode -eq 'Manual') 'Template access refusal is explicit without protection bypass'
Reset-Fixture;$script:templates=@{}
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:fixtures.WpnUserService_ab12.StartMode -eq 'Manual' -and 'WpnUserService_ab12' -notin $script:writes) 'Missing template never falls back to writing a session instance'
Check ((Test-AtomTemplateType 0x60) -and (Test-AtomTemplateType 0x50) -and -not(Test-AtomTemplateType 0xe0) -and -not(Test-AtomTemplateType 0x41) -and -not(Test-AtomTemplateType 0x20)) 'Only Win32 user templates qualify; instances and drivers are rejected'
Reset-Fixture
$base=@(Get-AtomPlan $catalog);$hash=Get-AtomSnapshotHash $base
$legacyRow=[pscustomobject]@{Name='WpnUserService_ab12';DisplayName='Legacy fixture';Present=$true;StartMode='Manual';State='Running';TargetKind='LegacyInstance';InstanceCount=0;Outcome='Detected';Error=''}
$entry=[pscustomobject]@{Name=$legacyRow.Name;OriginalMode='Manual';Delayed=[pscustomobject]@{Exists=$false;Value=0};Restored=$false}
$script:journal.Entries=@($entry)
$result=@(Invoke-AtomChanges 'Restore' @($legacyRow) $script:journal 'fixture.json')
Check ($entry.Restored -and $result[0].Outcome -eq 'Restored' -and $script:writes.Count -eq 0 -and $script:templateWrites.Count -eq 0) 'Legacy refused session backup is restored as a verified no-op'
Check ((Get-AtomSnapshotHash @($base+$legacyRow)) -eq $hash) 'Legacy display rows do not invalidate the next application snapshot'
Write-Output ('PASS: '+$script:checks+' isolated service-profile checks; no host service modified.')
