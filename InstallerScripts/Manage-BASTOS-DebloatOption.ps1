[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('All','MicrosoftStore','StoreAppUpdates','OneDrive','ConsumerFeatures','HyperV','InternetExplorer','FaxAndScan','WindowsMediaPlayer','CopilotExplorerButton','AiPackages','Copilot','Recall','NotepadAI','AiFiles')][string]$Option,
    [Parameter(Mandatory)][ValidateSet('Status','Apply','Restore')][string]$Action,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$backupRoot=Join-Path $env:ProgramData 'BASTOS\Backups\DebloatOptions'
if(-not(Test-Path -LiteralPath $backupRoot)){New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null}
$allOptions=@('MicrosoftStore','StoreAppUpdates','OneDrive','ConsumerFeatures','HyperV','InternetExplorer','FaxAndScan','WindowsMediaPlayer','CopilotExplorerButton','AiPackages','Copilot','Recall','NotepadAI','AiFiles')
$aiNames=@('Microsoft.Windows.Ai.Copilot.Provider','Microsoft.Copilot','Microsoft.CoPilot','Microsoft.WindowsAiFoundation','Microsoft.Windows.Recall')

function Get-RegSnapshot([string]$Path,[string]$Name){
    $exists=Test-Path -LiteralPath $Path
    $valueExists=$false;$value=$null;$kind='DWord'
    if($exists){try{$key=Get-Item -LiteralPath $Path -ErrorAction Stop;$value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);$valueExists=$null -ne $value;if($valueExists){$kind=[string]$key.GetValueKind($Name)}}catch{}}
    [pscustomobject]@{Path=$Path;Name=$Name;KeyExists=$exists;ValueExists=$valueExists;Value=$value;Kind=$kind}
}
function Set-RegDword([string]$Path,[string]$Name,[int]$Value){if(-not(Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force|Out-Null};New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force|Out-Null}
function Set-RegString([string]$Path,[string]$Name,[string]$Value){if(-not(Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force|Out-Null};New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force|Out-Null}
function Get-RegValue([string]$Path,[string]$Name){try{(Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name}catch{$null}}
function Restore-RegSnapshot($Snapshot){
    if($Snapshot.ValueExists){if(-not(Test-Path -LiteralPath ([string]$Snapshot.Path))){New-Item -Path ([string]$Snapshot.Path) -Force|Out-Null};New-ItemProperty -Path ([string]$Snapshot.Path) -Name ([string]$Snapshot.Name) -Value $Snapshot.Value -PropertyType ([string]$Snapshot.Kind) -Force|Out-Null}
    elseif(Test-Path -LiteralPath ([string]$Snapshot.Path)){Remove-ItemProperty -Path ([string]$Snapshot.Path) -Name ([string]$Snapshot.Name) -ErrorAction SilentlyContinue}
}
function Get-Feature([string[]]$Names){foreach($name in $Names){try{$feature=Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop;if($feature){return $feature}}catch{}};return $null}
function Test-FeatureDisabled($Feature){$Feature -and [string]$Feature.State -match 'Disabled|DisablePending'}
function Get-AiPackages {
    $installed=@(Get-AppxPackage -ErrorAction SilentlyContinue|Where-Object{[string]$_.Name -in $aiNames})
    @($installed)
}
function Get-StorePackages {
    @(Get-AppxPackage -Name '*Microsoft.WindowsStore*' -ErrorAction SilentlyContinue)
}
function Test-OneDriveInstalled {
    foreach($path in @((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),$(if(${env:ProgramFiles(x86)}){Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe'}))|Where-Object{$_}){if(Test-Path -LiteralPath $path -PathType Leaf){return $true}}
    return $false
}
function Get-AiResidualPaths {
    $root=Join-Path $env:LOCALAPPDATA 'Packages';if(-not(Test-Path -LiteralPath $root)){return @()}
    $installedNames=@(Get-AppxPackage -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name)
    @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue|Where-Object{$directoryName=[string]$_.Name;$matchingName=@($aiNames|Where-Object{$directoryName -like "$_*"}|Select-Object -First 1);$matchingName.Count -gt 0 -and [string]$matchingName[0] -notin $installedNames}|Select-Object -ExpandProperty FullName)
}
function Get-OptionStatus([string]$Name){
    $active=$false;$available=$true;$detail='';$restorable=Test-Path -LiteralPath (Join-Path $backupRoot ($Name+'.json'))
    switch($Name){
        'MicrosoftStore'{$count=@(Get-StorePackages).Count;$active=$count -eq 0;$detail=if($active){'Microsoft Store supprimé'}else{"Microsoft Store installé ($count package(s))"}}
        'StoreAppUpdates'{$value=Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload';$active=$value -eq 2;$detail=if($active){'Mises à jour automatiques des applications désactivées'}else{'Mises à jour gérées par Microsoft Store'}}
        'OneDrive'{$installed=Test-OneDriveInstalled;$active=-not $installed;$detail=if($installed){'OneDrive installé'}else{'OneDrive supprimé'}}
        'ConsumerFeatures'{$p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';$active=(Get-RegValue $p 'DisableWindowsConsumerFeatures') -eq 1;$detail=if($active){'Fonctionnalités grand public désactivées'}else{'Paramètre Windows par défaut'}}
        'HyperV'{$f=Get-Feature @('Microsoft-Hyper-V-All');$available=[bool]$f;$active=Test-FeatureDisabled $f;$detail=if($f){"État Windows : $($f.State)"}else{'Fonctionnalité absente de cette édition'}}
        'InternetExplorer'{$f=Get-Feature @('Internet-Explorer-Optional-amd64','Internet-Explorer-Optional-x86');$available=[bool]$f;$active=Test-FeatureDisabled $f;$detail=if($f){"État Windows : $($f.State)"}else{'Fonctionnalité absente de cette version'}}
        'FaxAndScan'{$f=Get-Feature @('FaxServicesClientPackage');$available=[bool]$f;$active=Test-FeatureDisabled $f;$detail=if($f){"État Windows : $($f.State)"}else{'Fonctionnalité absente de cette version'}}
        'WindowsMediaPlayer'{$f=Get-Feature @('WindowsMediaPlayer','WindowsMediaPlayerLegacy');$available=[bool]$f;$active=Test-FeatureDisabled $f;$detail=if($f){"État Windows : $($f.State)"}else{'Fonctionnalité absente de cette version'}}
        'CopilotExplorerButton'{$p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';$active=(Get-RegValue $p 'ShowCopilotButton') -eq 0;$detail=if($active){'Bouton Copilot masqué'}else{'Bouton géré par Windows'}}
        'AiPackages'{$count=@(Get-AiPackages).Count;$active=$count -eq 0;$detail="$count package(s) IA installé(s)"}
        'Copilot'{$machine=Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot';$count=@(Get-AiPackages|Where-Object{[string]$_.Name -match '(?i)Copilot'}).Count;$active=$machine -eq 1 -and $count -eq 0;$detail="$count package(s) Copilot ; stratégie : $(if($machine -eq 1){'désactivé'}else{'Windows'})"}
        'Recall'{$f=Get-Feature @('Recall');$policy=Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis';$available=[bool]$f -or $null -ne $policy;$active=($null -eq $f -or (Test-FeatureDisabled $f)) -and $policy -eq 1;$detail=if($f){"Recall : $($f.State) ; politique : $policy"}else{"Fonctionnalité Recall absente ; politique : $policy"}}
        'NotepadAI'{$p=Get-RegValue 'HKLM:\Software\Policies\WindowsNotepad' 'DisableAIFeatures';$active=$p -eq 1;$detail=if($active){'Fonctions IA du Bloc-notes désactivées'}else{'Fonctions gérées par Windows'}}
        'AiFiles'{$count=@(Get-AiResidualPaths).Count;$active=$count -eq 0;$detail="$count dossier(s) utilisateur IA résiduel(s) ; WindowsApps et SystemApps protégés";$restorable=$false}
    }
    [pscustomobject]@{Option=$Name;Active=[bool]$active;Available=[bool]$available;Restorable=[bool]$restorable;Detail=$detail}
}
function Save-Backup([string]$Name,[object]$Data){$path=Join-Path $backupRoot ($Name+'.json');if(-not(Test-Path -LiteralPath $path)){[IO.File]::WriteAllText($path,($Data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$path}
function Load-Backup([string]$Name){$path=Join-Path $backupRoot ($Name+'.json');if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}}
function Set-FeatureDisabled([string[]]$Names,[bool]$Disabled){$f=Get-Feature $Names;if(-not $f){return};if($Disabled){Disable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -NoRestart -ErrorAction Stop|Out-Null}else{Enable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -All -NoRestart -ErrorAction Stop|Out-Null}}
function Remove-AiPackages([string]$NamePattern='') {
    $packages=@(Get-AiPackages);if($NamePattern){$packages=@($packages|Where-Object{[string]$_.Name -match $NamePattern})}
    $removed=@();foreach($pkg in $packages){try{Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop;$removed+=[string]$pkg.Name}catch{try{Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop;$removed+=[string]$pkg.Name}catch{}}};@($removed)
}
function Apply-Option([string]$Name){
    switch($Name){
        'MicrosoftStore'{$packages=@(Get-StorePackages|Select-Object Name,PackageFullName,InstallLocation);Save-Backup $Name @{Packages=$packages}|Out-Null;foreach($pkg in @(Get-StorePackages)){try{Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop}catch{Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue}}}
        'StoreAppUpdates'{$s=Get-RegSnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload';Save-Backup $Name @{Registry=$s}|Out-Null;Set-RegDword $s.Path $s.Name 2}
        'OneDrive'{$marker=[pscustomobject]@{Installed=Test-OneDriveInstalled;SavedAt=(Get-Date).ToString('o')};Save-Backup $Name $marker|Out-Null;$worker=Join-Path $PSScriptRoot 'Remove-BASTOS-OneDrive.ps1';if(-not(Test-Path -LiteralPath $worker -PathType Leaf)){throw 'Module OneDrive BASTOS introuvable.'};$oneDriveResult=Join-Path $env:TEMP ("BASTOS-OneDrive-{0}.json" -f [guid]::NewGuid().ToString('N'));try{$oneDriveReport=& $worker -Scope Both -ResultPath $oneDriveResult;if(-not $oneDriveReport -or -not [bool]$oneDriveReport.Success){$detail=if(Test-Path $oneDriveResult){(Get-Content $oneDriveResult -Raw -Encoding UTF8)}else{'Aucun rapport'};throw "Suppression OneDrive incomplète : $detail"}}finally{Remove-Item -LiteralPath $oneDriveResult -Force -ErrorAction SilentlyContinue}}
        'ConsumerFeatures'{$s=Get-RegSnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures';Save-Backup $Name @{Registry=$s}|Out-Null;Set-RegDword $s.Path $s.Name 1}
        'HyperV'{$f=Get-Feature @('Microsoft-Hyper-V-All');Save-Backup $Name @{FeatureName=if($f){$f.FeatureName}else{''};State=if($f){[string]$f.State}else{'Absent'}}|Out-Null;Set-FeatureDisabled @('Microsoft-Hyper-V-All') $true}
        'InternetExplorer'{$f=Get-Feature @('Internet-Explorer-Optional-amd64','Internet-Explorer-Optional-x86');Save-Backup $Name @{FeatureName=if($f){$f.FeatureName}else{''};State=if($f){[string]$f.State}else{'Absent'}}|Out-Null;Set-FeatureDisabled @('Internet-Explorer-Optional-amd64','Internet-Explorer-Optional-x86') $true}
        'FaxAndScan'{$f=Get-Feature @('FaxServicesClientPackage');Save-Backup $Name @{FeatureName=if($f){$f.FeatureName}else{''};State=if($f){[string]$f.State}else{'Absent'}}|Out-Null;Set-FeatureDisabled @('FaxServicesClientPackage') $true}
        'WindowsMediaPlayer'{$f=Get-Feature @('WindowsMediaPlayer','WindowsMediaPlayerLegacy');Save-Backup $Name @{FeatureName=if($f){$f.FeatureName}else{''};State=if($f){[string]$f.State}else{'Absent'}}|Out-Null;Set-FeatureDisabled @('WindowsMediaPlayer','WindowsMediaPlayerLegacy') $true}
        'CopilotExplorerButton'{$s=Get-RegSnapshot 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton';Save-Backup $Name @{Registry=$s}|Out-Null;Set-RegDword $s.Path $s.Name 0}
        'AiPackages'{$packages=@(Get-AiPackages|Select-Object Name,PackageFullName,InstallLocation);Save-Backup $Name @{Packages=$packages}|Out-Null;[void](Remove-AiPackages)}
        'Copilot'{$regs=@(Get-RegSnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot';Get-RegSnapshot 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot';Get-RegSnapshot 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton';Get-RegSnapshot 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot' 'AllowCopilotRuntime');$packages=@(Get-AiPackages|Where-Object{[string]$_.Name -match '(?i)Copilot'}|Select-Object Name,PackageFullName,InstallLocation);Save-Backup $Name @{Registry=$regs;Packages=$packages}|Out-Null;Set-RegDword $regs[0].Path $regs[0].Name 1;Set-RegDword $regs[1].Path $regs[1].Name 1;Set-RegDword $regs[2].Path $regs[2].Name 0;Set-RegDword $regs[3].Path $regs[3].Name 0;[void](Remove-AiPackages '(?i)Copilot')}
        'Recall'{$f=Get-Feature @('Recall');$reg=Get-RegSnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis';$tasks=@(Get-ScheduledTask -ErrorAction SilentlyContinue|Where-Object{$_.TaskPath -like '\Microsoft\Windows\WindowsAI\*' -or $_.TaskPath -like '\Microsoft\Windows\Recall\*'}|Select-Object TaskName,TaskPath,State);Save-Backup $Name @{FeatureName=if($f){$f.FeatureName}else{''};State=if($f){[string]$f.State}else{'Absent'};Registry=$reg;Tasks=$tasks}|Out-Null;Set-FeatureDisabled @('Recall') $true;Set-RegDword $reg.Path $reg.Name 1;foreach($task in $tasks){Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue|Out-Null}}
        'NotepadAI'{$regs=@(Get-RegSnapshot 'HKLM:\Software\Policies\WindowsNotepad' 'DisableAIFeatures';Get-RegSnapshot 'HKCU:\Software\Microsoft\Notepad' 'ShowRewriteButton');Save-Backup $Name @{Registry=$regs}|Out-Null;Set-RegDword $regs[0].Path $regs[0].Name 1;Set-RegDword $regs[1].Path $regs[1].Name 0}
        'AiFiles'{$root=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Packages')).TrimEnd('\')+'\';foreach($path in @(Get-AiResidualPaths)){$resolved=[IO.Path]::GetFullPath($path);if($resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop}}}
    }
}
function Restore-Option([string]$Name){
    $backup=Load-Backup $Name;if(-not $backup){throw 'Aucune sauvegarde BASTOS antérieure pour cette option.'}
    switch($Name){
        'MicrosoftStore'{foreach($pkg in @($backup.Packages)){if($pkg.InstallLocation){$manifest=Join-Path ([string]$pkg.InstallLocation) 'AppxManifest.xml';if(Test-Path -LiteralPath $manifest){Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue}}}}
        'StoreAppUpdates'{Restore-RegSnapshot $backup.Registry}
        'OneDrive'{$setup=@((Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),(Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'))|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1;if(-not $setup){throw 'Programme officiel OneDriveSetup.exe introuvable.'};$process=Start-Process -FilePath $setup -ArgumentList '/install' -Wait -PassThru -WindowStyle Hidden;if($process.ExitCode -notin @(0,1641,3010)){throw "Réinstallation OneDrive échouée (code $($process.ExitCode))."}}
        'ConsumerFeatures'{Restore-RegSnapshot $backup.Registry}
        'HyperV'{if([string]$backup.State -match '^Enabled'){Set-FeatureDisabled @([string]$backup.FeatureName) $false}else{Set-FeatureDisabled @([string]$backup.FeatureName) $true}}
        'InternetExplorer'{if([string]$backup.State -match '^Enabled'){Set-FeatureDisabled @([string]$backup.FeatureName) $false}else{Set-FeatureDisabled @([string]$backup.FeatureName) $true}}
        'FaxAndScan'{if([string]$backup.State -match '^Enabled'){Set-FeatureDisabled @([string]$backup.FeatureName) $false}else{Set-FeatureDisabled @([string]$backup.FeatureName) $true}}
        'WindowsMediaPlayer'{if([string]$backup.State -match '^Enabled'){Set-FeatureDisabled @([string]$backup.FeatureName) $false}else{Set-FeatureDisabled @([string]$backup.FeatureName) $true}}
        'CopilotExplorerButton'{Restore-RegSnapshot $backup.Registry}
        'AiPackages'{foreach($pkg in @($backup.Packages)){if($pkg.InstallLocation){$manifest=Join-Path ([string]$pkg.InstallLocation) 'AppxManifest.xml';if(Test-Path -LiteralPath $manifest){Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue}}}}
        'Copilot'{foreach($reg in @($backup.Registry)){Restore-RegSnapshot $reg};foreach($pkg in @($backup.Packages)){if($pkg.InstallLocation){$manifest=Join-Path ([string]$pkg.InstallLocation) 'AppxManifest.xml';if(Test-Path -LiteralPath $manifest){Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue}}}}
        'Recall'{Restore-RegSnapshot $backup.Registry;if([string]$backup.State -match '^Enabled'){Set-FeatureDisabled @([string]$backup.FeatureName) $false};foreach($task in @($backup.Tasks)){if([string]$task.State -ne 'Disabled'){Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue|Out-Null}}}
        'NotepadAI'{foreach($reg in @($backup.Registry)){Restore-RegSnapshot $reg}}
        'AiFiles'{throw 'Le nettoyage des dossiers résiduels utilisateur ne peut pas être annulé.'}
    }
    Remove-Item -LiteralPath (Join-Path $backupRoot ($Name+'.json')) -Force -ErrorAction SilentlyContinue
}

$result=[ordered]@{Success=$false;Option=$Option;Action=$Action;Items=@();Error=''}
try{
    if($Action -eq 'Status'){$names=if($Option -eq 'All'){$allOptions}else{@($Option)};$result.Items=@($names|ForEach-Object{Get-OptionStatus $_})}
    elseif($Option -eq 'All'){throw 'Les modifications groupées ne sont pas autorisées.'}
    elseif($Action -eq 'Apply'){Apply-Option $Option;$result.Items=@(Get-OptionStatus $Option)}
    else{Restore-Option $Option;$result.Items=@(Get-OptionStatus $Option)}
    $result.Success=$true
}catch{$result.Error=$_.Exception.Message}
finally{[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))}
if($result.Success){exit 0}else{exit 1}
