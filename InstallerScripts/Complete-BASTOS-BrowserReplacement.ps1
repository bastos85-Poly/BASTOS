[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('chrome','firefox','librewolf','brave','opera','helium','ungoogled-chromium','thorium-avx2')][string]$SelectedBrowser,
 [Parameter(Mandatory)][string]$Browsers,
 [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$reports=@()
$failures=@()
$warnings=@()
$verificationIncomplete=$false
try {
 $relative=switch($SelectedBrowser){
  'chrome' {'Google\Chrome\Application\chrome.exe'}
  'firefox' {'Mozilla Firefox\firefox.exe'}
  'librewolf' {'LibreWolf\librewolf.exe'}
  'brave' {'BraveSoftware\Brave-Browser\Application\brave.exe'}
  'opera' {'Programs\Opera\opera.exe'}
  'helium' {'imput\Helium\Application\chrome.exe'}
 }
 $pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
 $candidates=@()
 if($relative){foreach($root in @($env:ProgramFiles,$pf86,$env:LOCALAPPDATA)|Where-Object {$_}){$candidates+=Join-Path $root $relative}}
 if($SelectedBrowser -eq 'opera'){foreach($root in @($env:ProgramFiles,$pf86)|Where-Object {$_}){$candidates+=Join-Path $root 'Opera\launcher.exe'}}
 if($SelectedBrowser -in @('ungoogled-chromium','thorium-avx2')){foreach($name in @('chrome.exe','thorium.exe')){$candidates+=Join-Path $env:USERPROFILE "scoop\apps\$SelectedBrowser\current\$name"}}
 if(-not @($candidates|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}).Count){throw 'Le navigateur choisi est absent : aucun ancien navigateur ne sera supprime.'}
 $requested=@($Browsers.Split(',')|Select-Object -Unique)
 foreach($browser in $requested){if($browser -notin @('chrome','firefox','librewolf','brave','opera','helium','edge') -or $browser -eq $SelectedBrowser){throw "Suppression refusee : $browser"}}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Le nettoyage exige les droits administrateur. Accepte la demande Windows pour reprendre.'}
 foreach($browser in $requested){
  $childResult=Join-Path (Split-Path -Parent $ResultPath) ("Browser-Cleanup-$browser-"+[guid]::NewGuid().ToString('N')+'.json')
  try {
   if($browser -eq 'edge'){& (Join-Path $PSScriptRoot 'Remove-BASTOS-Edge.ps1') -ForceWithoutBrowser -ResultPath $childResult|Out-Null}
   else {& (Join-Path $PSScriptRoot 'Uninstall-BASTOS-Browser.ps1') -Browser $browser -ResultPath $childResult|Out-Null}
   if(-not(Test-Path -LiteralPath $childResult)){throw 'Rapport de suppression absent.'}
   $report=Get-Content -LiteralPath $childResult -Raw|ConvertFrom-Json
   $reports+=$report
   if(-not $report.Success){$failures+="$browser : suppression incomplete (voir $childResult)."}
   if($report.PSObject.Properties['Errors'] -and @($report.Errors).Count -gt 0){$failures+="$browser : $(@($report.Errors) -join ' ; ')"}
   if($report.PSObject.Properties['Warnings']){$warnings+=@($report.Warnings)}
   if($report.PSObject.Properties['ProvisionedInventoryVerified'] -and -not $report.ProvisionedInventoryVerified){$verificationIncomplete=$true}
  }catch{$failures+="$browser : $($_.Exception.Message)"}
 }
}catch{$failures+=$_.Exception.Message}
$success=$failures.Count -eq 0
$message=if($success){if($verificationIncomplete){'Navigateurs nettoyes; controle des paquets Windows destines aux futurs comptes indisponible.'}else{'Nettoyage groupe termine et verifie.'}}else{$failures -join ' | '}
$parent=Split-Path -Parent $ResultPath
if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
[IO.File]::WriteAllText($ResultPath,([ordered]@{Success=$success;SelectedBrowser=$SelectedBrowser;Message=$message;Reports=$reports;Errors=$failures;Warnings=$warnings;VerificationIncomplete=$verificationIncomplete;CheckedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
if(-not $success){exit 1}
exit 0
