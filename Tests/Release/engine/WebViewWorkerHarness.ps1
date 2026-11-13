param([string]$WorkerPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
$global:BastosFixtureScenario=$env:BASTOS_WEBVIEW_SCENARIO
if($global:BastosFixtureScenario -notin @('AlreadyInstalled','InvalidUri','ExistingActive','Installed','ExitFailure','InvalidSignature')){throw 'Unknown fixture scenario.'}
if(-not $env:BASTOS_WEBVIEW_CAPTURE -or -not $env:LOCALAPPDATA){throw 'Fixture paths required.'}
$global:BastosFixtureInstalled=$global:BastosFixtureScenario -eq 'AlreadyInstalled'
function global:Get-ItemProperty {
 param([string]$LiteralPath,[string]$Name,[string]$ErrorAction)
 if($LiteralPath -notmatch 'EdgeUpdate\\Clients\\' -or $Name -ne 'pv'){throw 'Unexpected registry access in fixture.'}
 if($global:BastosFixtureInstalled){return [pscustomobject]@{pv='150.0.1.2'}}
 throw 'Fixture: runtime absent.'
}
function global:Get-Process {
 param([string]$Name,[string]$ErrorAction)
 if($Name -ne 'MicrosoftEdgeWebview2Setup'){throw 'Unexpected process inventory in fixture.'}
 if($global:BastosFixtureScenario -eq 'ExistingActive'){return [pscustomobject]@{Id=424242}}
 return @()
}
function global:Start-Process {
 param([string]$FilePath,[string[]]$ArgumentList,[switch]$PassThru,[string]$WindowStyle)
 if([IO.Path]::GetFileName($FilePath) -ne 'MicrosoftEdgeWebview2Setup.exe' -or ($ArgumentList -join ' ') -ne '/silent /install'){throw 'Unexpected fixture launch.'}
 Add-Content -LiteralPath $env:BASTOS_WEBVIEW_CAPTURE -Value 'simulated-bootstrapper-launch'
 if($global:BastosFixtureScenario -eq 'Installed'){$global:BastosFixtureInstalled=$true}
 $mock=[pscustomobject]@{Id=424243;HasExited=$true;ExitCode=if($global:BastosFixtureScenario -eq 'ExitFailure'){1603}else{0}}
 $mock|Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
 return $mock
}
if($global:BastosFixtureScenario -eq 'InvalidSignature'){
 function global:Get-AuthenticodeSignature {param([string]$LiteralPath);return [pscustomobject]@{Status='NotSigned';SignerCertificate=$null}}
}
# The real worker downloads and verifies the official Microsoft bootstrapper;
# Start-Process above never executes it and registry/process reads are fixtures.
& $WorkerPath @args
exit $LASTEXITCODE
