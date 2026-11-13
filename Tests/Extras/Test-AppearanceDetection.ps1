param([string]$SourceRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$path=Join-Path $SourceRoot 'InstallerScripts/Manage-BASTOS-WinScriptFeature.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
# Load only the real detection functions, never the script's action dispatcher.
foreach($name in @('Get-BastosAppearanceDetection')){
 $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($node.Extent.Text))
}
. (Join-Path $SourceRoot 'InstallerScripts/WinScript-Feature-Definitions.ps1')
$definitions=@(Get-BastosWinScriptFeatureDefinitions|Where-Object {$_.Key -in @('DarkMode','Transparency','MouseMenuDelay','ShowFileExtensions','ShowHiddenFiles','ClassicContextMenu','TaskbarLeft','EndTaskMenu')})
$script:fixtures=@{};$count=0
function Check($condition,$message){if(-not $condition){throw $message};$script:count++;Write-Output ('OK : '+$message)}
function Get-BastosRegistrySnapshot($target){$v=$script:fixtures[$target.Name];if($v -is [Exception]){throw $v};return $v}
function Seed($definition){$script:fixtures=@{};foreach($t in $definition.Registry){$script:fixtures[$t.Name]=[pscustomobject]@{Exists=$true;Kind=$t.Kind;Value=$t.Value}}}
foreach($d in $definitions){
 Seed $d;$r=Get-BastosAppearanceDetection $d;Check ($r.Active -and $r.DetectionState -eq 'Applied') ($d.Key+': valeurs conformes')
 foreach($t in $d.Registry){
  Seed $d;$script:fixtures[$t.Name].Value='DIFFERENT';$r=Get-BastosAppearanceDetection $d;Check (-not $r.Active -and $r.DetectionState -eq $(if($d.Registry.Count -gt 1){'Partial'}else{'NotApplied'})) ($d.Key+': ecart '+$t.Name)
  Seed $d;$script:fixtures[$t.Name].Kind=if($t.Kind -eq 'DWord'){'String'}else{'DWord'};$r=Get-BastosAppearanceDetection $d;Check (-not $r.Active) ($d.Key+': type incorrect '+$t.Name)
  Seed $d;$script:fixtures[$t.Name].Exists=$false;$r=Get-BastosAppearanceDetection $d;Check (-not $r.Active -and $r.DetectionState -eq 'Unavailable') ($d.Key+': valeur absente '+$t.Name)
  Seed $d;$script:fixtures[$t.Name]=[UnauthorizedAccessException]::new('Fixture lecture interdite');$r=Get-BastosAppearanceDetection $d;Check (-not $r.Active -and $r.DetectionState -eq 'Unavailable') ($d.Key+': lecture refusee '+$t.Name)
 }
 Seed $d;foreach($t in $d.Registry){$script:fixtures[$t.Name].Value='DIFFERENT'};$r=Get-BastosAppearanceDetection $d;Check ($r.DetectionState -eq 'NotApplied') ($d.Key+': aucun point conforme')
}
Check ($definitions.Count -eq 8) 'Huit reglages couverts'
$dark=$definitions|Where-Object Key -eq 'DarkMode';Seed $dark
# The saved .theme is intentionally irrelevant: no file read occurs here.
Check ((Get-BastosAppearanceDetection $dark).Active) 'Mode sombre actif independamment du theme sauvegarde (CRLF, LF, absent ou ancien)'
$classic=$definitions|Where-Object Key -eq 'ClassicContextMenu';Seed $classic
Check ((Get-BastosAppearanceDetection $classic).StateLabel -match 'affichage') 'Menu classique : configuration distincte de la preuve visuelle'
Write-Output "PASS : $count controles detection apparence ; aucune ecriture registre."
