param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$FixtureRoot,[switch]$LiveDownloads)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function LoadFunctions($path,$names){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors);if($errors.Count){throw $errors[0]};foreach($name in $names){$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);if(-not $node){throw "Fonction absente $name"};[pscustomobject]@{Name=$name;Code=$node.Extent.Text}}}
$functions=@(LoadFunctions (Join-Path $SourceRoot 'InstallerScripts/Install-BASTOS-SoftwareSelection.ps1') @('Get-BastosPublisherDefinition','Assert-BastosPublisherFile','Invoke-BastosPublisherInstall'))+@(LoadFunctions (Join-Path $SourceRoot 'InstallerScripts/Manage-BASTOS-SpecialSoftware.ps1') @('Get-BastosSourceForgeFileUrl','Invoke-VerifiedDownload','Assert-BastosMicrosoftTool'))
foreach($f in $functions){. ([scriptblock]::Create($f.Code))}
$count=0;function Check($ok,$text){if(-not $ok){throw $text};$script:count++;Write-Output "OK : $text"};function Refuse($code,$text){$no=$false;try{& $code|Out-Null}catch{$no=$true};Check $no $text}
Check ($null -eq (Get-BastosPublisherDefinition 'Vendor.Other')) 'Autres logiciels exclus des parcours specifiques'
$url=Get-BastosSourceForgeFileUrl '<a href="https://downloads.sourceforge.net/project/eq/test.exe?ts=abc&amp;use_mirror=x">' '/project/eq/test.exe'
Check ($url -eq 'https://downloads.sourceforge.net/project/eq/test.exe?ts=abc&use_mirror=x') 'Lien temporaire SourceForge exact et entites HTML decodees'
Refuse {Get-BastosSourceForgeFileUrl 'https://evil.test/project/eq/test.exe?ts=abc' '/project/eq/test.exe'} 'Hote SourceForge usurpe refuse'
Refuse {Get-BastosSourceForgeFileUrl 'https://downloads.sourceforge.net/project/other/test.exe?ts=abc' '/project/eq/test.exe'} 'Autre projet SourceForge refuse'
Refuse {Get-BastosSourceForgeFileUrl 'https://downloads.sourceforge.net/project/eq/other.exe?ts=abc' '/project/eq/test.exe'} 'Autre fichier SourceForge refuse'
Refuse {Get-BastosSourceForgeFileUrl '<html>Pas de lien</html>' '/project/eq/test.exe'} 'Page sans fichier refusee'
$files=@{'AIMP.AIMP'='aimp.bin';'REALiX.HWiNFO'='hwinfo-sac.exe';'Piriform.CCleaner'='../software-audit/Piriform.CCleaner.retest.bin';'Resplendence.LatencyMon'='../software-audit/Resplendence.LatencyMon.retest.bin'}
foreach($id in $files.Keys){$d=Get-BastosPublisherDefinition $id;$path=Join-Path $FixtureRoot $files[$id];Check ((Assert-BastosPublisherFile $path $d).Length -eq 64) ($id+': fichier officiel reel authentifie');$bad=$d.Clone();$bad.Signer='Autre editeur';Refuse {Assert-BastosPublisherFile $path $bad} ($id+': autre editeur refuse');$bad=$d.Clone();$bad.Product='^AUTRE PRODUIT$';Refuse {Assert-BastosPublisherFile $path $bad} ($id+': autre produit refuse');$bad=$d.Clone();$bad.Hash=('0'*64);Refuse {Assert-BastosPublisherFile $path $bad} ($id+': empreinte imposee divergente refusee')}
foreach($name in @('procexp.exe','procexp64.exe','procexp64a.exe')){Assert-BastosMicrosoftTool (Join-Path $FixtureRoot "ProcessExplorer/$name");Check $true ('Process Explorer : signature Microsoft '+$name)}
Refuse {Assert-BastosMicrosoftTool (Join-Path $FixtureRoot 'aimp.bin')} 'Process Explorer : autre editeur pourtant signe refuse'
$catalog=Get-Content (Join-Path $SourceRoot 'Software-Catalog.json') -Raw|ConvertFrom-Json
Check (@($catalog|Where-Object Id -eq 'RealVNC.VNCConnect.Viewer').Count -eq 1) 'Identifiant actuel RealVNC Viewer reconnu'
Check (@($catalog|Where-Object Id -eq 'RealVNC.VNCViewer').Count -eq 0) 'Ancien paquet RealVNC retire du catalogue'
Check (($catalog|Where-Object Id -eq 'Microsoft.Sysinternals.ProcessExplorer').CustomAction -eq 'OfficialTool:ProcessExplorer') 'Process Explorer : installation et desinstallation portables explicites'
if($LiveDownloads){
 $downloadRoot=Join-Path $FixtureRoot 'LiveTests';New-Item -ItemType Directory $downloadRoot -Force|Out-Null
 foreach($id in $files.Keys){$d=Get-BastosPublisherDefinition $id;$path=Join-Path $downloadRoot $d.File;Invoke-WebRequest $d.Uri -OutFile $path -UseBasicParsing -TimeoutSec 90;Assert-BastosPublisherFile $path $d|Out-Null;Check $true ($id+': nouveau telechargement integral valide')}
 foreach($case in @(@{Name='Equalizer';Url='https://sourceforge.net/projects/equalizerapo/files/1.4.2/EqualizerAPO-x64-1.4.2.exe/download?use_mirror=master';Hash='7403BE7427BBE1936A40DDED082829B6E217FC4F5990FEE5CBA501F0AE055AFA'},@{Name='Peace';Url='https://sourceforge.net/projects/peace-equalizer-apo-extension/files/PeaceSetup.exe/download?use_mirror=master';Hash='D007A5EFCBE361EFBE5EC88EEA8EFF6191D0188E8C7111354CBB063FBAC26F2C'})){
  $path=Join-Path $downloadRoot ($case.Name+'.exe');Invoke-VerifiedDownload $case.Url $path $case.Hash;Check ((Get-FileHash $path).Hash -eq $case.Hash) ($case.Name+': page SourceForge resolue puis empreinte originale conforme')
 }
 $path=Join-Path $downloadRoot 'RealVNC.zip';Invoke-WebRequest 'https://downloads.realvnc.com/download/file/realvnc-connect-viewer/RealVNC-Connect-Viewer-8.6.1-Windows.msi.zip' -OutFile $path -TimeoutSec 90
 Check ((Get-FileHash $path).Hash -eq '1340493E4BC58C78A7D132516CBB2B08FCF56D4F06347B2230FC7963975376AC') 'RealVNC actuel : archive conforme au manifeste WinGet'
}
Write-Output "PASS : $count controles des huit anomalies ; aucun installateur execute."
