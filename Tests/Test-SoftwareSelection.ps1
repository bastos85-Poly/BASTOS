param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$worker=Join-Path $SourceRoot 'InstallerScripts\Install-BASTOS-SoftwareSelection.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Get-BastosPublisherDefinition','Test-BastosKnownAdminPackage','Get-BastosInstallerPrivilegeEvidence','ConvertTo-BastosInstallerArgument','Invoke-BastosElevatedSoftwareItem')){
    $definition=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
    . ([scriptblock]::Create($definition.Extent.Text))
}
$count=0
function Check([bool]$ok,[string]$name){if(-not $ok){throw $name};$script:count++;Write-Output "OK : $name"}
Check (Test-BastosKnownAdminPackage 'Open-Shell.Open-Shell-Menu' winget winget) 'Open-Shell demande un administrateur avant son MSI'
Check (-not(Test-BastosKnownAdminPackage 'Spotify.Spotify' winget winget)) 'Les logiciels utilisateur ne sont pas tous eleves'
Check (Test-BastosKnownAdminPackage 'Vendor.App' chocolatey winget) 'Chocolatey utilise son contexte administrateur'
Check ((ConvertTo-BastosInstallerArgument 'C:\folder with spaces\file.json') -eq '"C:\folder with spaces\file.json"') 'Chemin avec espaces transmis comme un argument'
$refused=$false;try{ConvertTo-BastosInstallerArgument 'file" -Command bad'|Out-Null}catch{$refused=$true};Check $refused 'Guillemets injectes refuses'
$temporary=Join-Path $env:TEMP ('Bastos-SoftwareTests-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temporary|Out-Null
$oldTrace=$env:BASTOS_TEST_MANAGER_TRACE;$oldMode=$env:BASTOS_TEST_MANAGER_MODE
try{
    $log=Join-Path $temporary 'WinGet-Vendor.Privilege.1.0-test.log';[IO.File]::WriteAllText($log,'MSI Error 1925. Insufficient privileges.')
    Check (Get-BastosInstallerPrivilegeEvidence 1603 '' 'Vendor.Privilege' ([datetime]::UtcNow.AddSeconds(-1)) $temporary).Required 'MSI 1925 recent du bon logiciel autorise une reprise ciblee'
    Check (-not(Get-BastosInstallerPrivilegeEvidence 1603 '' 'Vendor.Other' ([datetime]::UtcNow.AddSeconds(-1)) $temporary).Required) 'Journal d un autre logiciel ignore'
    [IO.File]::SetLastWriteTimeUtc($log,[datetime]::UtcNow.AddDays(-1))
    Check (-not(Get-BastosInstallerPrivilegeEvidence 1603 '' 'Vendor.Privilege' ([datetime]::UtcNow) $temporary).Required) 'Ancien journal ignore'
    Check (-not(Get-BastosInstallerPrivilegeEvidence 1603 'Installer failed with exit code: 1603' 'Vendor.Other' ([datetime]::UtcNow) $temporary).Required) 'Erreur 1603 seule ne declenche pas une elevation'
    Check (Get-BastosInstallerPrivilegeEvidence 740 '' 'Vendor.Other' ([datetime]::UtcNow) $temporary).Required 'Code Windows elevation requise reconnu'
    Check (Get-BastosInstallerPrivilegeEvidence 1603 'Erreur 1925. Droits insuffisants.' 'Vendor.Other' ([datetime]::UtcNow) $temporary).Required 'Diagnostic MSI francais reconnu'
    $fakeManager=Join-Path $temporary 'Fake Manager.cmd'
    @'
@echo off
echo %*>>"%BASTOS_TEST_MANAGER_TRACE%"
if "%~1"=="--version" (echo 2.3.0&exit /b 0)
if "%~1"=="list" goto list
if "%~3"=="Vendor.Fail" (echo Installer failed with exit code: 1603&exit /b 1603)
if "%~3"=="Vendor.Privilege" (echo Error 1925. Insufficient privileges&exit /b 1603)
if "%~3"=="Vendor.Cancel" (echo Error 1925. Insufficient privileges&exit /b 1603)
if "%~3"=="Vendor.Already" (echo Already installed&exit /b -1978335189)
if "%~3"=="Vendor.Restart" (echo Restart required&exit /b 3010)
echo Simulated install
exit /b 0
:list
if "%BASTOS_TEST_MANAGER_MODE%"=="missing-proof" (echo No installed package&exit /b 1)
if "%~3"=="Vendor.NoProof" (echo No installed package&exit /b 1)
if "%BASTOS_TEST_MANAGER_MODE%"=="chocolatey" (echo %~3^|1.0&exit /b 0)
echo %~3 1.0 winget
exit /b 0
'@ | Set-Content -LiteralPath $fakeManager -Encoding ASCII
    $text=[IO.File]::ReadAllText($worker)
    $stub=@'
function Invoke-BastosElevatedSoftwareItem($Item,[string]$ManagerExe) {
    [IO.File]::AppendAllText($env:BASTOS_TEST_MANAGER_TRACE,"ADMIN "+$Item.Id+"`r`n")
    $ok=$Item.Id -ne 'Vendor.Cancel'
    return [pscustomobject]@{Name=$Item.Name;Id=$Item.Id;Source='winget';Manager=$Manager;Success=$ok;Verified=$ok;Status=$(if($ok){'Installed'}else{'Failed'});ExitCode=$(if($ok){0}else{1223});ErrorCode=$(if($ok){''}else{'ADMIN_CANCELLED'});Detail='Simulated UAC; no real installer launched'}
}
'@
    $functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -in @('Test-BastosInstallerAdmin','Invoke-BastosElevatedSoftwareItem','Invoke-BastosPublisherInstall')|Sort-Object {$_.Extent.StartOffset} -Descending)
    foreach($function in $functions){$replacement=if($function.Name -eq 'Test-BastosInstallerAdmin'){'function Test-BastosInstallerAdmin { return $false }'}elseif($function.Name -eq 'Invoke-BastosPublisherInstall'){'function Invoke-BastosPublisherInstall($Definition) { [IO.File]::AppendAllText($env:BASTOS_TEST_MANAGER_TRACE,"PUBLISHER "+$Definition.File+"`r`n"); return [pscustomobject]@{ExitCode=0;Output="Simulated publisher installer"} }'}else{$stub};$text=$text.Remove($function.Extent.StartOffset,$function.Extent.EndOffset-$function.Extent.StartOffset).Insert($function.Extent.StartOffset,$replacement)}
    $fixture=Join-Path $temporary 'Worker.ps1';[IO.File]::WriteAllText($fixture,$text,[Text.UTF8Encoding]::new($true))
    $adminFixture=Join-Path $temporary 'WorkerAdmin.ps1';[IO.File]::WriteAllText($adminFixture,$text.Replace('function Test-BastosInstallerAdmin { return $false }','function Test-BastosInstallerAdmin { return $true }'),[Text.UTF8Encoding]::new($true))
    function Scenario([string]$name,[string[]]$ids,[bool]$success,[string]$manager='winget',[string]$sid='', [switch]$RequireAdmin,[switch]$AsAdmin,[switch]$MissingProof){
        $directory=Join-Path $temporary $name;New-Item -ItemType Directory $directory|Out-Null
        $selection=Join-Path $directory 'Selection.json';@($ids|ForEach-Object {[pscustomobject]@{Name=$_;Id=$_;Source='winget'}})|ConvertTo-Json|Set-Content $selection -Encoding UTF8
        $env:BASTOS_TEST_MANAGER_TRACE=Join-Path $directory 'trace.txt';$env:BASTOS_TEST_MANAGER_MODE=if($MissingProof){'missing-proof'}else{$manager}
        $script=if($manager -eq 'chocolatey' -or $AsAdmin){$adminFixture}else{$fixture}
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-SelectionPath',$selection,'-ProgressPath',(Join-Path $directory 'Progress.txt'),'-ResultPath',(Join-Path $directory 'Result.json'),'-Manager',$manager,'-ManagerPath',$fakeManager)
        if($sid){$arguments+=@('-ExpectedUserSid',$sid)};if($RequireAdmin){$arguments+='-ElevatedRetry'}
        & powershell.exe @arguments *> (Join-Path $directory 'console.log')
        $code=$LASTEXITCODE;$result=Get-Content (Join-Path $directory 'Result.json') -Raw|ConvertFrom-Json
        Check ($result.Success -eq $success -and ($code -eq 0) -eq $success) ('Worker complet : '+$name) | Out-Host
        $trace=if(Test-Path $env:BASTOS_TEST_MANAGER_TRACE){[IO.File]::ReadAllText($env:BASTOS_TEST_MANAGER_TRACE)}else{''}
        return [pscustomobject]@{Result=$result;Trace=$trace}
    }
    $r=Scenario good @('Vendor.Good') $true;Check ($r.Result.Items[0].Verified) 'Presence du logiciel verifiee apres installation'
    $r=Scenario noProof @('Vendor.NoProof') $false;Check (-not $r.Result.Items[0].Verified) 'Code zero sans presence ne devient pas un succes'
    $r=Scenario already @('Vendor.Already') $true;Check ($r.Result.Items[0].Status -eq 'AlreadyPresent') 'Logiciel deja present confirme'
    $r=Scenario restart @('Vendor.Restart') $true;Check ($r.Result.Items[0].RestartRequired) 'Demande de redemarrage enregistree sans redemarrer'
    $r=Scenario openshell @('Open-Shell.Open-Shell-Menu') $true;Check ($r.Trace.Trim() -eq 'ADMIN Open-Shell.Open-Shell-Menu') 'Open-Shell passe directement par la demande administrateur'
    $r=Scenario privilege @('Vendor.Privilege') $true;Check ($r.Trace.Contains('ADMIN Vendor.Privilege')) 'Autre logiciel avec preuve de droits repris seul'
    $r=Scenario generic @('Vendor.Fail') $false;Check (-not $r.Trace.Contains('ADMIN')) 'Pas de reprise administrateur aveugle pour 1603'
    $r=Scenario cancelled @('Vendor.Cancel') $false;Check ($r.Result.Items[0].ErrorCode -eq 'ADMIN_CANCELLED') 'Annulation conservee sans nouvelle demande UAC'
    $r=Scenario mixed @('Vendor.Good','Open-Shell.Open-Shell-Menu','Vendor.Fail') $false;Check ($r.Result.Installed -eq 2 -and $r.Result.Failed -eq 1 -and ([regex]::Matches($r.Trace,'ADMIN ')).Count -eq 1) 'Lot mixte : utilisateur, administrateur cible et echec distinct'
    $r=Scenario wrongUser @('Vendor.Good') $false -sid 'S-1-5-21-0-0-0-9999';Check ($r.Trace -eq '') 'Autre compte refuse avant tout lancement logiciel'
    $r=Scenario adminDenied @('Vendor.Good') $false -RequireAdmin;Check ($r.Trace -eq '') 'Reprise sans droits refusee sans boucle'
    $r=Scenario chocolatey2 @('Open-Shell.Open-Shell-Menu') $true -manager chocolatey;Check (-not $r.Trace.Contains('--local-only')) 'Chocolatey 2 utilise list sans option supprimee'
    foreach($id in @('AIMP.AIMP','REALiX.HWiNFO','Piriform.CCleaner','Resplendence.LatencyMon')){
        $r=Scenario ('publisher-'+$id) @($id) $true -AsAdmin
        Check ($r.Result.Items[0].Verified -and $r.Trace.Contains('PUBLISHER ') -and -not $r.Trace.Contains('install --id')) ('Source editeur ciblee et presence verifiee : '+$id)
    }
    $r=Scenario publisherNoProof @('AIMP.AIMP') $false -AsAdmin -MissingProof
    Check (-not $r.Result.Items[0].Verified) 'Installation editeur code zero sans presence refusee'
    # Keep the real elevation/report code, replacing only the OS process launch.
    $ResultPath=Join-Path $temporary 'ParentResult.json';$Manager='winget'
    $script:adminTestItem=[pscustomobject]@{Name='Open-Shell';Id='Open-Shell.Open-Shell-Menu';Source='winget'}
    function Start-Process {
        [CmdletBinding()]param($FilePath,$ArgumentList,$Verb,[switch]$PassThru,$WindowStyle)
        if($script:adminMode -eq 'cancel'){throw [ComponentModel.Win32Exception]::new(1223)}
        $arguments=@([regex]::Matches($ArgumentList,'"([^"]*)"')|ForEach-Object {$_.Groups[1].Value})
        if($arguments[[array]::IndexOf($arguments,'-ManagerPath')+1] -ne $fakeManager){throw 'Manager path split incorrectly'}
        $reportPath=$arguments[[array]::IndexOf($arguments,'-ResultPath')+1]
        $sid=$arguments[[array]::IndexOf($arguments,'-ExpectedUserSid')+1]
        if($script:adminMode -eq 'wrong-user'){$sid='another-user'}
        [IO.File]::WriteAllText($reportPath,([ordered]@{Schema=2;Requested=1;Success=$true;UserSid=$sid;Items=@([pscustomobject]@{Name='Open-Shell';Id='Open-Shell.Open-Shell-Menu';Success=$true;Verified=$true;Status='Installed';ExitCode=0})}|ConvertTo-Json -Depth 5))
        $process=[pscustomobject]@{ExitCode=$(if($script:adminMode -eq 'contradictory'){1}else{0})}
        $process|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($milliseconds) return $script:adminMode -ne 'timeout'}
        return $process
    }
    $script:adminMode='success';$item=Invoke-BastosElevatedSoftwareItem $script:adminTestItem $fakeManager;Check $item.Success 'Rapport administrateur du bon compte et argument avec espaces acceptes'
    $script:adminMode='cancel';$item=Invoke-BastosElevatedSoftwareItem $script:adminTestItem $fakeManager;Check ($item.ErrorCode -eq 'ADMIN_CANCELLED') 'Vraie branche erreur Windows 1223 reconnue sans boucle'
    $script:adminMode='timeout';$item=Invoke-BastosElevatedSoftwareItem $script:adminTestItem $fakeManager;Check ($item.ErrorCode -eq 'INSTALLATION_UNCONFIRMED') 'Processus toujours actif ne donne pas une reussite'
    foreach($mode in @('wrong-user','contradictory')){$script:adminMode=$mode;$refused=$false;try{Invoke-BastosElevatedSoftwareItem $script:adminTestItem $fakeManager|Out-Null}catch{$refused=$true};Check $refused ('Rapport administrateur refuse : '+$mode)}
}finally{
    $env:BASTOS_TEST_MANAGER_TRACE=$oldTrace;$env:BASTOS_TEST_MANAGER_MODE=$oldMode
    $resolved=[IO.Path]::GetFullPath($temporary);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture hors TEMP refusee'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count controles installation logiciels ; gestionnaires et UAC simules, aucun logiciel reel installe."
