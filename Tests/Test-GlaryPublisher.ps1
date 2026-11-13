param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$OfficialInstaller)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'InstallerScripts/Install-BASTOS-SoftwareSelection.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Test-BastosGlaryPublisherFallback','Test-BastosGlaryPublisherSignature','Invoke-BastosGlaryPublisherInstall')){$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);. ([scriptblock]::Create($node.Extent.Text))}
$count=0;function Check($ok,$text){if(-not $ok){throw $text};$script:count++;Write-Output "OK : $text"}
Check (Test-BastosGlaryPublisherFallback 'Glarysoft.GlaryUtilities' winget winget -1978335215) 'Glary : reprise ciblee sur empreinte WinGet obsolete'
foreach($id in @('Vendor.Other','Glarysoft.GlaryUtilities.Pro')){Check (-not(Test-BastosGlaryPublisherFallback $id winget winget -1978335215)) 'Aucun autre logiciel concerne'}
foreach($code in @(0,1603,3010,-1,1223)){Check (-not(Test-BastosGlaryPublisherFallback 'Glarysoft.GlaryUtilities' winget winget $code)) ('Pas de reprise sur autre code : '+$code)}
Check (-not(Test-BastosGlaryPublisherFallback 'Glarysoft.GlaryUtilities' chocolatey winget -1978335215)) 'Chocolatey conserve son parcours'
Check (-not(Test-BastosGlaryPublisherFallback 'Glarysoft.GlaryUtilities' winget msstore -1978335215)) 'Source Store exclue'
$cert=[pscustomobject]@{Name='Glarysoft Ltd'};$cert|Add-Member ScriptMethod GetNameInfo {param($type,$issuer);return $this.Name}
foreach($status in @('NotSigned','HashMismatch','NotTrusted','UnknownError')){Check (-not(Test-BastosGlaryPublisherSignature ([pscustomobject]@{Status=$status;SignerCertificate=$cert}))) ('Signature refusee : '+$status)}
$cert.Name='Other publisher';Check (-not(Test-BastosGlaryPublisherSignature ([pscustomobject]@{Status='Valid';SignerCertificate=$cert}))) 'Autre editeur refuse meme signe'
Check (-not(Test-BastosGlaryPublisherSignature ([pscustomobject]@{Status='Valid';SignerCertificate=$null}))) 'Certificat absent refuse'
if($OfficialInstaller){
 $real=Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $OfficialInstaller
 Check (Test-BastosGlaryPublisherSignature $real) 'Installateur officiel reel : signature Glarysoft valide'
 $temp=Join-Path $env:TEMP ('GlaryTests-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp|Out-Null
 try{
  $ResultPath=Join-Path $temp 'result.json';$script:fixtureInstaller=$OfficialInstaller;$script:launched=0
  function Invoke-WebRequest{[CmdletBinding()]param($Uri,[switch]$UseBasicParsing,$MaximumRedirection,$OutFile,$TimeoutSec);if($Uri -ne 'https://download.glarysoft.com/gusetup.exe' -or $MaximumRedirection -ne 0){throw 'Source non borne'};Copy-Item $script:fixtureInstaller $OutFile}
  function Start-Process{[CmdletBinding()]param($FilePath,$ArgumentList,[switch]$PassThru);if($ArgumentList -ne '/S'){throw 'Mode silencieux incorrect'};$script:launched++;$p=[pscustomobject]@{ExitCode=0};$p|Add-Member ScriptMethod WaitForExit {param($ms);return $true};$p|Add-Member ScriptMethod Dispose {};return $p}
  $r=Invoke-BastosGlaryPublisherInstall;Check ($r.ExitCode -eq 0 -and $script:launched -eq 1 -and $r.Output -match 'signature Authenticode valide') 'Parcours officiel valide avant lancement simule'
  function Get-AuthenticodeSignature{[CmdletBinding()]param($LiteralPath);return [pscustomobject]@{Status='HashMismatch';SignerCertificate=$null}}
  $refused=$false;try{Invoke-BastosGlaryPublisherInstall|Out-Null}catch{$refused=$true};Check ($refused -and $script:launched -eq 1) 'Fichier divergent refuse avant toute execution'
 }finally{Remove-Item Function:Get-AuthenticodeSignature -ErrorAction SilentlyContinue;Remove-Item Function:Invoke-WebRequest;Remove-Item Function:Start-Process;$resolved=[IO.Path]::GetFullPath($temp);if(-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture hors TEMP'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output "PASS : $count controles Glary ; aucun logiciel installe par les fixtures."
