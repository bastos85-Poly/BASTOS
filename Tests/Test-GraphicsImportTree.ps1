$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'InstallerScripts\Invoke-BASTOS-GraphicsOptimization.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw "Script graphique invalide : $($errors[0].Message)"}
foreach($name in @('Get-BastosImportKey','Get-BastosImportTree','Reset-BastosImportTree','Get-BastosImportSnapshot','Test-BastosImportTargets','Set-BastosImportValue','Restore-BastosImportValues')){
 $function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(-not $function){throw "Fonction $name introuvable."}
 Invoke-Expression $function.Extent.Text
}
$root='Software\BASTOS-GraphicsTreeTest-'+[guid]::NewGuid().ToString('N')
$item=[pscustomobject]@{Hive='HKCU';Path="$root\Notification";Name='*';Kind='Tree';Value='Reset'}
try{
 $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($item.Path)
 try{$key.SetValue('Count',42,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Dispose()}
 $child=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$($item.Path)\History")
 try{$child.SetValue('Blob',[byte[]](1,2,3),[Microsoft.Win32.RegistryValueKind]::Binary)}finally{$child.Dispose()}
 $snapshot=Get-BastosImportSnapshot $item
 if(-not $snapshot.Exists -or @($snapshot.Tree).Count -ne 2){throw 'Sauvegarde de la sous-clé incomplète.'}
 Set-BastosImportValue $item
 $after=Get-BastosImportSnapshot $item
 if(@(Test-BastosImportTargets @($item)).Count){throw ('La sous-clé de notifications n’a pas été vidée : '+($after|ConvertTo-Json -Depth 8))}
 Restore-BastosImportValues @($snapshot)
 $restored=Get-BastosImportSnapshot $item
 if(@($restored.Tree).Count -ne 2 -or $restored.Tree[0].Values[0].Value -ne 42 -or $restored.Tree[1].Values[0].Value -ne 'AQID'){throw 'Restauration des notifications incorrecte.'}
 $missing=[pscustomobject]@{Hive='HKCU';Path=$item.Path;Name='Created';Kind='DWord';Value=1}
 $empty=Get-BastosImportSnapshot $missing
 Set-BastosImportValue $missing
 Restore-BastosImportValues @($empty)
 if((Get-BastosImportSnapshot $missing).Exists){throw 'Une valeur initialement absente n’a pas été retirée.'}
 'Sauvegarde et restauration des notifications : OK'
}finally{
 [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($root,$false)
}
