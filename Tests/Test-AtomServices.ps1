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
    $script:journal=[pscustomobject]@{Schema=1;Profile='atom-0.0.8-all';Entries=@()}
}
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$Filter)
    if($ClassName -ne 'Win32_Service'){throw 'Unexpected provider.'}
    if($Filter){$name=$Filter.Substring(6,$Filter.Length-7);return $script:fixtures[$name]}
    return @($script:fixtures.Values)
}
function Get-AtomDelayedStart($name){if($script:delayed.ContainsKey($name)){return $script:delayed[$name]};[pscustomobject]@{Exists=$false;Value=0}}
function Write-AtomDocument($path,$document){if($script:saveFails){throw 'Fixture disk full'};$script:saves+=($document|ConvertTo-Json -Depth 12 -Compress)}
function Set-Service {
    [CmdletBinding()]param($Name,$StartupType)
    Check ($script:saves.Count -gt 0) 'Backup persisted before service write'
    if($Name -eq $script:refused){throw 'Fixture protected service'}
    $script:writes+=$Name
    $script:fixtures[$Name].StartMode=switch($StartupType){'Automatic'{'Auto'} 'Manual'{'Manual'} 'Disabled'{'Disabled'} default{throw 'Unexpected mode'}}
}
# Override registry adapter only; test the real startup writer and read-back.
function New-ItemProperty {[CmdletBinding()]param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force);$service=Split-Path $LiteralPath -Leaf;$script:delayed[$service]=[pscustomobject]@{Exists=$true;Value=$Value}}
function Remove-ItemProperty {[CmdletBinding()]param($LiteralPath,$Name);$service=Split-Path $LiteralPath -Leaf;[void]$script:delayed.Remove($service)}
$catalog=Import-PowerShellDataFile (Join-Path $SourceRoot 'InstallerScripts/Bastos.AtomServices.psd1')
Check ($catalog.Names.Count -eq 152 -and @($catalog.Names|Sort-Object -Unique).Count -eq 152) 'Complete deduplicated Atom catalog'
Reset-Fixture
$plan=@(Get-AtomPlan $catalog)
Check ($script:writes.Count -eq 0 -and $script:saves.Count -eq 0) 'Analysis has no side effects'
Check (@($plan|Where-Object Name -eq 'WpnUserService_ab12').Count -eq 1) 'User service instances are resolved'
Check (@($plan|Where-Object {$_.Name -eq 'WdBoot' -and -not $_.Present}).Count -eq 1) 'Kernel driver is never treated as a Win32 service'
$hash=Get-AtomSnapshotHash $plan
$script:fixtures.DiagTrack.State='Stopped'
Check ((Get-AtomSnapshotHash @(Get-AtomPlan $catalog)) -eq $hash) 'Runtime state does not invalidate startup preview'
$script:fixtures.DiagTrack.StartMode='Manual'
Check ((Get-AtomSnapshotHash @(Get-AtomPlan $catalog)) -ne $hash) 'Startup drift invalidates preview'
Reset-Fixture
$script:delayed.DiagTrack=[pscustomobject]@{Exists=$true;Value=1}
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:writes.Count -eq 3 -and $script:journal.Entries.Count -eq 3) 'Only present services requiring changes are written'
Check ($script:fixtures.DiagTrack.State -eq 'Running') 'Running services are never stopped'
Check ($script:journal.Entries[0].OriginalMode -in @('Auto','Manual')) 'Original startup settings are preserved'
$saved=$script:journal|ConvertTo-Json -Depth 12 -Compress
$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check (($script:journal|ConvertTo-Json -Depth 12 -Compress) -eq $saved) 'Repeated application preserves the original backup'
$null=Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check ($script:fixtures.DiagTrack.StartMode -eq 'Auto' -and $script:fixtures.BITS.StartMode -eq 'Manual' -and $script:delayed.DiagTrack.Value -eq 1) 'Exact startup and delayed-auto values restored'
Check ($script:fixtures.Spooler.StartMode -eq 'Disabled') 'Previously disabled service remains disabled'
Reset-Fixture;$script:saveFails=$true
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check ($script:writes.Count -eq 0 -and @($result|Where-Object Outcome -eq 'Failed').Count -eq 3) 'Backup failure prevents writes and is reported'
Reset-Fixture;$script:refused='BITS'
$result=@(Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'BITS' -and $_.Outcome -eq 'Failed'}).Count -eq 1 -and $script:fixtures.BITS.StartMode -eq 'Manual') 'Protected service refusal remains visible'
$script:refused='';$null=Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
Check (@($script:journal.Entries|Where-Object {-not $_.Restored}).Count -eq 0) 'No-op failed writes can be restored cleanly'
Reset-Fixture;$null=Invoke-AtomChanges 'Apply' @(Get-AtomPlan $catalog) $script:journal 'fixture.json'
$script:fixtures.DiagTrack.StartMode='Manual';$before=$script:writes.Count
$result=@(Invoke-AtomChanges 'Restore' @(Get-AtomPlan $catalog) $script:journal 'fixture.json')
Check (@($result|Where-Object {$_.Name -eq 'DiagTrack' -and $_.Outcome -eq 'Failed'}).Count -eq 1 -and $script:fixtures.DiagTrack.StartMode -eq 'Manual') 'External changes are preserved and reported'
Write-Output ('PASS: '+$script:checks+' isolated service-profile checks; no host service modified.')
