$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'InstallerScripts\Invoke-BASTOS-GraphicsOptimization.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw "Script graphique invalide : $($errors[0].Message)"}
foreach($name in @('Test-BastosImportBackupStale','Get-BastosImportIdentity','Invoke-BastosSettingsImport')){
 $function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(-not $function){throw "Fonction $name introuvable."}
 Invoke-Expression $function.Extent.Text
}
$targets=@('HKLM|Graphics\0000|VSyncControl|String','HKCU|Software\AMD|Profile|String')
$legacy=[pscustomobject]@{Schema=1;Values=@(1,2)}
if(-not (Test-BastosImportBackupStale $legacy $targets)){throw 'Une sauvegarde v1 doit être archivée.'}
$current=[pscustomobject]@{Schema=2;Targets=$targets}
if(Test-BastosImportBackupStale $current $targets){throw 'Une sauvegarde v2 compatible ne doit pas être archivée.'}
$changed=[pscustomobject]@{Schema=2;Targets=@('HKLM|Graphics\0001|VSyncControl|String')}
if(-not (Test-BastosImportBackupStale $changed $targets)){throw 'Un pilote modifié doit invalider la sauvegarde.'}
foreach($invalid in @([pscustomobject]@{Schema=2},[pscustomobject]@{Schema=3})){
 $rejected=$false
 try{[void](Test-BastosImportBackupStale $invalid $targets)}catch{$rejected=$true}
 if(-not $rejected){throw 'Une sauvegarde invalide a été acceptée.'}
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('BastosGraphicsBackupTest-'+[guid]::NewGuid().ToString('N'))
$script:fixtureBackup=Join-Path $fixture 'GraphicsSettings-AMD-test.json'
$script:writes=0
$script:targetNames=@('Current')
New-Item -ItemType Directory -Path $fixture|Out-Null
$userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$oldBackup=[ordered]@{Schema=1;Vendor='AMD';UserSid=$userSid;Values=@([ordered]@{Hive='HKCU';Path='Test';Name='Old';Exists=$false})}
[IO.File]::WriteAllText($script:fixtureBackup,($oldBackup|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$oldHash=(Get-FileHash -LiteralPath $script:fixtureBackup).Hash
function Get-BastosImportBackupPath([string]$SelectedVendor){return $script:fixtureBackup}
function Get-BastosImportTargets([string]$SelectedVendor){return @($script:targetNames|ForEach-Object {[pscustomobject]@{Hive='HKCU';Path='Test';Name=$_;Kind='String';Value='1'}})}
function Test-BastosAdministrator {return $true}
function Get-BastosImportSnapshot([object]$item){return [pscustomobject]@{Hive=$item.Hive;Path=$item.Path;Name=$item.Name;Exists=$false}}
function Set-BastosImportValue([object]$item){$script:writes++}
function Test-BastosImportTargets([array]$items){return @()}
$result=Invoke-BastosSettingsImport 'AMD' 'ApplyImport'
if(-not $result.Success -or $script:writes -ne 1){throw 'Migration v1 : import simulé incorrect.'}
$archived=@(Get-ChildItem -LiteralPath $fixture -Filter '*-ancien-*.json')
if($archived.Count -ne 1 -or (Get-FileHash -LiteralPath $archived[0].FullName).Hash -ne $oldHash){throw 'La sauvegarde v1 a été perdue.'}
$newBackup=Get-Content -LiteralPath $script:fixtureBackup -Raw|ConvertFrom-Json
if($newBackup.Schema -ne 2 -or @($newBackup.Targets).Count -ne 1){throw 'La sauvegarde v2 n’a pas été créée.'}
$result=Invoke-BastosSettingsImport 'AMD' 'ApplyImport'
if(-not $result.Success -or $script:writes -ne 2 -or @(Get-ChildItem -LiteralPath $fixture -Filter '*-ancien-*.json').Count -ne 1){throw 'La réimportation v2 a modifié la sauvegarde.'}
$script:targetNames=@('Current','Extra')
$result=Invoke-BastosSettingsImport 'AMD' 'ApplyImport'
$expanded=Get-Content -LiteralPath $script:fixtureBackup -Raw|ConvertFrom-Json
if(-not $result.Success -or $script:writes -ne 4 -or @($expanded.Targets).Count -ne 2 -or @($expanded.Values).Count -ne 2 -or @(Get-ChildItem -LiteralPath $fixture -Filter '*-ancien-*.json').Count -ne 1){throw 'Une nouvelle cible n’a pas été ajoutée à la sauvegarde.'}
'Compatibilité des sauvegardes graphiques v1/v2 : OK'
