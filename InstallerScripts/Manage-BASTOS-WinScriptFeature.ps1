[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Option,
    [Parameter(Mandatory)][ValidateSet('Status','Apply','Restore','Preview','RefreshShell')][string]$Action,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$definitionPath=Join-Path $PSScriptRoot 'WinScript-Feature-Definitions.ps1'
if(-not(Test-Path -LiteralPath $definitionPath -PathType Leaf)){throw 'Les définitions WinScript BASTOS sont introuvables.'}
. $definitionPath
$definitions=@(Get-BastosWinScriptFeatureDefinitions)
$backupRoot=Join-Path $env:ProgramData 'BASTOS\Backups\WinScriptFeatures'

function Test-BastosAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    [Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Send-BastosSettingsChanged {
    if(-not ('BastosSettingsBroadcast' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BastosSettingsBroadcast {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
}
'@
    }
    $result=[IntPtr]::Zero
    [void][BastosSettingsBroadcast]::SendMessageTimeout([IntPtr]0xffff,0x1A,[IntPtr]::Zero,'ImmersiveColorSet',2,1000,[ref]$result)
    [void][BastosSettingsBroadcast]::SendMessageTimeout([IntPtr]0xffff,0x1A,[IntPtr]::Zero,'Environment',2,1000,[ref]$result)
    [BastosSettingsBroadcast]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
}

function Set-BastosDarkTheme {
    $current=[string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -Name CurrentTheme -ErrorAction Stop).CurrentTheme
    if(-not(Test-Path -LiteralPath $current -PathType Leaf)){throw 'Thème Windows courant introuvable.'}
    $encoding=[Text.Encoding]::GetEncoding(1252)
    $theme=[IO.File]::ReadAllText($current,$encoding)
    if($theme -match '(?m)^SystemMode=Dark\s*$' -and $theme -match '(?m)^AppMode=Dark\s*$'){return}
    if($theme -notmatch '(?m)^SystemMode=(Light|Dark)\s*$' -or $theme -notmatch '(?m)^AppMode=(Light|Dark)\s*$'){throw 'Le thème courant ne contient pas les modes clair/sombre attendus.'}
    $theme=$theme -replace '(?m)^SystemMode=Light\s*$','SystemMode=Dark' -replace '(?m)^AppMode=Light\s*$','AppMode=Dark'
    $folder=Join-Path $env:LOCALAPPDATA 'BASTOS\Themes'
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $destination=Join-Path $folder 'Bastos-Dark.theme'
    [IO.File]::WriteAllText($destination,$theme,$encoding)
    Start-Process -FilePath $destination -ErrorAction Stop
    $limit=(Get-Date).AddSeconds(15)
    do{
        Start-Sleep -Milliseconds 500
        $applied=[string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -Name CurrentTheme -ErrorAction Stop).CurrentTheme
    }until($applied -like '*Bastos-Dark.theme' -or (Get-Date) -ge $limit)
    if($applied -notlike '*Bastos-Dark.theme'){throw 'Windows n a pas confirmé le thème sombre.'}
}

function Restart-BastosExplorer {
    $shell=@(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq (Get-Process -Id $PID).SessionId})
    foreach($process in $shell){Stop-Process -Id $process.Id -Force -ErrorAction Stop}
    Start-Sleep -Milliseconds 800
    if(-not(Get-Process -Name explorer -ErrorAction SilentlyContinue)){Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ErrorAction Stop}
}

function Save-BastosJson([string]$Path,$Value){
    $parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}

function Get-BastosRegistrySnapshot($Target){
    $path=[string]$Target.Path;$name=[string]$Target.Name
    if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{Path=$path;Name=$name;Exists=$false;Kind=$null;Value=$null}}
    $key=Get-Item -LiteralPath $path -ErrorAction Stop
    if($key.GetValueNames() -notcontains $name){return [pscustomobject]@{Path=$path;Name=$name;Exists=$false;Kind=$null;Value=$null}}
    [pscustomobject]@{Path=$path;Name=$name;Exists=$true;Kind=[string]$key.GetValueKind($name);Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
}

function Get-BastosRegistryBaseAndSubKey([string]$Path){
    $parts=$Path -split ':\\',2
    if($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])){throw "Chemin de registre BASTOS invalide : $Path"}
    $baseKey=switch($parts[0].ToUpperInvariant()){
        'HKCU'{[Microsoft.Win32.Registry]::CurrentUser}
        'HKLM'{[Microsoft.Win32.Registry]::LocalMachine}
        default{throw "Ruche de registre BASTOS non prise en charge : $($parts[0])"}
    }
    [pscustomobject]@{BaseKey=$baseKey;SubKey=$parts[1]}
}

function Set-BastosRegistryTarget($Target){
    $path=[string]$Target.Path;$name=[string]$Target.Name
    $location=Get-BastosRegistryBaseAndSubKey $path
    $kind=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Target.Kind,$true)
    $key=$location.BaseKey.CreateSubKey($location.SubKey,$true)
    if(-not $key){throw "Impossible d ouvrir la clé de registre en écriture : $path"}
    try{$key.SetValue($name,$Target.Value,$kind)}finally{$key.Dispose()}
}

function Restore-BastosRegistrySnapshot($Snapshot){
    $path=[string]$Snapshot.Path;$name=[string]$Snapshot.Name
    $location=Get-BastosRegistryBaseAndSubKey $path
    if([bool]$Snapshot.Exists){
        $kind=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Snapshot.Kind,$true)
        $key=$location.BaseKey.CreateSubKey($location.SubKey,$true)
        if(-not $key){throw "Impossible d ouvrir la clé de registre en restauration : $path"}
        try{$key.SetValue($name,$Snapshot.Value,$kind)}finally{$key.Dispose()}
    }else{
        $key=$location.BaseKey.OpenSubKey($location.SubKey,$true)
        if($key){try{$key.DeleteValue($name,$false)}finally{$key.Dispose()}}
    }
}

function Get-BastosServiceSnapshot($Target){
    $service=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f ([string]$Target.Name).Replace("'","''")) -ErrorAction SilentlyContinue
    if(-not $service){return [pscustomobject]@{Name=[string]$Target.Name;Exists=$false;StartMode=$null;State=$null}}
    [pscustomobject]@{Name=[string]$service.Name;Exists=$true;StartMode=[string]$service.StartMode;State=[string]$service.State}
}

function Set-BastosServiceTarget($Target){
    $service=Get-Service -Name ([string]$Target.Name) -ErrorAction SilentlyContinue
    if(-not $service){return}
    if([bool]$Target.Stop -and $service.Status -ne 'Stopped'){Stop-Service -Name $service.Name -Force -ErrorAction Stop}
    Set-Service -Name $service.Name -StartupType ([string]$Target.Startup) -ErrorAction Stop
}

function Restore-BastosServiceSnapshot($Snapshot){
    if(-not [bool]$Snapshot.Exists){return}
    $startup=switch([string]$Snapshot.StartMode){'Auto'{'Automatic'};'Automatic'{'Automatic'};'Manual'{'Manual'};'Disabled'{'Disabled'};default{'Manual'}}
    Set-Service -Name ([string]$Snapshot.Name) -StartupType $startup -ErrorAction Stop
    if([string]$Snapshot.State -eq 'Running'){Start-Service -Name ([string]$Snapshot.Name) -ErrorAction SilentlyContinue}
}

function Get-BastosTaskSnapshot($Target){
    $fullName=[string]$Target.TaskName
    $task=Get-ScheduledTask -TaskName $fullName -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $task){return [pscustomobject]@{TaskName=$fullName;Exists=$false;State=$null}}
    [pscustomobject]@{TaskName=$fullName;Exists=$true;State=[string]$task.State}
}

function Set-BastosTaskTarget($Target){
    $fullName=[string]$Target.TaskName
    $task=Get-ScheduledTask -TaskName $fullName -ErrorAction SilentlyContinue | Select-Object -First 1
    if($task){$task | Disable-ScheduledTask -ErrorAction Stop | Out-Null}
}

function Restore-BastosTaskSnapshot($Snapshot){
    if(-not [bool]$Snapshot.Exists){return}
    $task=Get-ScheduledTask -TaskName ([string]$Snapshot.TaskName) -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $task){return}
    if([string]$Snapshot.State -eq 'Disabled'){$task | Disable-ScheduledTask -ErrorAction Stop | Out-Null}
    else{$task | Enable-ScheduledTask -ErrorAction Stop | Out-Null}
}

function Test-BastosFeatureAvailable($Definition){
    if($Definition.DetectPaths.Count -gt 0 -and @($Definition.DetectPaths|Where-Object{Test-Path -LiteralPath $_}).Count -eq 0){return $false}
    if($Definition.DetectServices.Count -gt 0 -and @($Definition.DetectServices|Where-Object{Get-Service -Name $_ -ErrorAction SilentlyContinue}).Count -eq 0){return $false}
    return $true
}

function Test-BastosFeatureActive($Definition){
    if(-not(Test-BastosFeatureAvailable $Definition)){return $false}
    # CurrentTheme describes a saved theme, not necessarily the user's current
    # choices. Read the effective personalization values, just like Settings.
    foreach($target in @($Definition.Registry)){
        $snapshot=Get-BastosRegistrySnapshot $target
        if(-not $snapshot.Exists -or [string]$snapshot.Value -ne [string]$target.Value){return $false}
    }
    foreach($target in @($Definition.Services)){
        $snapshot=Get-BastosServiceSnapshot $target
        if(-not $snapshot.Exists -or [string]$snapshot.StartMode -ne [string]$target.Startup){return $false}
        if([bool]$target.Stop -and [string]$snapshot.State -ne 'Stopped'){return $false}
    }
    $existingTaskCount=0
    foreach($target in @($Definition.Tasks)){
        $snapshot=Get-BastosTaskSnapshot $target
        if(-not [bool]$snapshot.Exists){continue}
        $existingTaskCount++
        if([string]$snapshot.State -ne 'Disabled'){return $false}
    }
    if($Definition.Registry.Count -eq 0 -and $Definition.Services.Count -eq 0 -and $Definition.Tasks.Count -gt 0 -and $existingTaskCount -eq 0){return $false}
    return ($Definition.Registry.Count+$Definition.Services.Count+$Definition.Tasks.Count) -gt 0
}

function Get-BastosAppearanceDetection($Definition){
    $evidence=New-Object Collections.Generic.List[object]
    foreach($target in @($Definition.Registry)){
        try{
            $snapshot=Get-BastosRegistrySnapshot $target
            $known=[bool]$snapshot.Exists
            $matches=$known -and $snapshot.Kind -eq [string]$target.Kind -and [string]$snapshot.Value -eq [string]$target.Value
            [void]$evidence.Add([pscustomobject]@{Name=$target.Name;Known=$known;Matches=[bool]$matches;Expected=$target.Value;Actual=$snapshot.Value;Kind=$snapshot.Kind;Error=''})
        }catch{
            [void]$evidence.Add([pscustomobject]@{Name=$target.Name;Known=$false;Matches=$false;Expected=$target.Value;Actual=$null;Kind=$null;Error=$_.Exception.Message})
        }
    }
    $unknown=@($evidence|Where-Object {-not $_.Known}).Count
    $matched=@($evidence|Where-Object Matches).Count
    $state=if($evidence.Count -eq 0 -or $unknown -gt 0){'Unavailable'}elseif($matched -eq $evidence.Count){'Applied'}elseif($matched -gt 0){'Partial'}else{'NotApplied'}
    $label=switch($state){'Applied'{'Appliqué'};'Partial'{'Partiellement appliqué'};'NotApplied'{'Non appliqué'};default{'Non vérifié'}}
    if($state -eq 'Applied' -and $Definition.Key -eq 'ClassicContextMenu'){$label='Configuré — affichage à vérifier'}
    $detail=switch($state){
        'Applied'{'Toutes les valeurs demandées ont été relues avec leur type attendu.'}
        'Partial'{'Seule une partie des valeurs demandées correspond au réglage.'}
        'NotApplied'{'Les valeurs présentes ne correspondent pas au réglage demandé.'}
        default{'Une valeur est absente ou illisible ; cela ne prouve pas que le réglage est désactivé.'}
    }
    if($Definition.Key -eq 'DarkMode'){$detail+=' Applications et interface Windows vérifiées séparément ; le fichier de thème sauvegardé ne remplace pas les préférences actuelles.'}
    if($Definition.Key -in @('ClassicContextMenu','TaskbarLeft','ShowFileExtensions','ShowHiddenFiles','EndTaskMenu','MouseMenuDelay')){$detail+=' Le rendu peut nécessiter une nouvelle fenêtre ou une reconnexion ; ce contrôle ne constitue pas une preuve visuelle.'}
    [pscustomobject]@{Active=($state -eq 'Applied');DetectionState=$state;StateLabel=$label;Detail=$detail;Evidence=$evidence.ToArray()}
}

function Get-BastosStatusResult($Definition){
    $appearance=$Definition.Key -in @('DarkMode','Transparency','MouseMenuDelay','ShowFileExtensions','ShowHiddenFiles','ClassicContextMenu','TaskbarLeft','EndTaskMenu')
    if($appearance){
        $detection=Get-BastosAppearanceDetection $Definition
        $backupPath=Join-Path $backupRoot ("{0}.json" -f $Definition.Key)
        return [pscustomobject]@{
            Option=$Definition.Key;Title=$Definition.Title;Category=$Definition.Category;Available=$true;Active=$detection.Active
            Risk=$Definition.Risk;Restart=$Definition.Restart;BackupAvailable=(Test-Path -LiteralPath $backupPath -PathType Leaf)
            DefaultAvailable=($Definition.Key -eq 'ClassicContextMenu' -and (Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'))
            DetectionState=$detection.DetectionState;StateLabel=$detection.StateLabel;Detail=$detection.Detail;Evidence=$detection.Evidence
        }
    }
    $available=Test-BastosFeatureAvailable $Definition
    $active=if($available){Test-BastosFeatureActive $Definition}else{$false}
    $backupPath=Join-Path $backupRoot ("{0}.json" -f $Definition.Key)
    [pscustomobject]@{
        Option=$Definition.Key;Title=$Definition.Title;Category=$Definition.Category;Available=$available;Active=$active
        Risk=$Definition.Risk;Restart=$Definition.Restart;BackupAvailable=(Test-Path -LiteralPath $backupPath -PathType Leaf)
        DefaultAvailable=($Definition.Key -eq 'ClassicContextMenu' -and (Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'))
        Detail=if(-not $available){'Non installé ou non applicable'}elseif($active){'Réglage BASTOS appliqué'}else{'Configuration d origine ou partielle'}
    }
}

$selected=@(
    if($Option -eq 'All'){
        $definitions
    }elseif($Option -eq 'Appearance'){
        $definitions|Where-Object {$_.Key -in @('DarkMode','Transparency','MouseMenuDelay','ShowFileExtensions','ShowHiddenFiles','ClassicContextMenu','TaskbarLeft','EndTaskMenu')}
    }elseif($Option -like 'Category:*'){
        $category=$Option.Substring('Category:'.Length)
        $definitions|Where-Object Category -eq $category
    }else{
        $definitions|Where-Object Key -eq $Option
    }
)
$items=New-Object Collections.Generic.List[object]
$success=$true;$errorMessage=''
try{
    if($selected.Count -eq 0){throw "Option WinScript BASTOS inconnue : $Option"}
    if($Action -eq 'RefreshShell'){
        Restart-BastosExplorer
        [void]$items.Add([pscustomobject]@{Option='Explorer';Active=$true;BackupAvailable=$false})
        Save-BastosJson $ResultPath ([pscustomobject]@{Success=$true;Action=$Action;Error='';Items=$items.ToArray();GeneratedUtc=[datetime]::UtcNow.ToString('o')})
        exit 0
    }
    $needsAdministrator=@($selected|Where-Object { @($_.Registry|Where-Object { [string]$_.Path -like 'HKLM:*' }).Count -gt 0 -or @($_.Services).Count -gt 0 -or @($_.Tasks).Count -gt 0 }).Count -gt 0
    if($Action -in @('Apply','Restore') -and $needsAdministrator -and -not(Test-BastosAdministrator)){throw 'Cette modification requiert les droits administrateur.'}
    if($Action -in @('Apply','Restore') -and @($selected|Where-Object {$_.Key -ne 'ClassicContextMenu'}).Count -gt 0){New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null}
    foreach($definition in $selected){
        $backupPath=Join-Path $backupRoot ("{0}.json" -f $definition.Key)
        if($Action -eq 'Status') {[void]$items.Add((Get-BastosStatusResult $definition));continue}
        if($Action -eq 'Preview'){
            [void]$items.Add([pscustomobject]@{Option=$definition.Key;Title=$definition.Title;Category=$definition.Category;Available=(Test-BastosFeatureAvailable $definition);Risk=$definition.Risk;Restart=$definition.Restart;Registry=@($definition.Registry|ForEach-Object{"$($_.Path) -> $($_.Name) = $($_.Value)"});Services=@($definition.Services|ForEach-Object{"$($_.Name) -> $($_.Startup)"});Tasks=@($definition.Tasks|ForEach-Object{"$($_.TaskName) -> Disabled"})})
            continue
        }
        if($Action -eq 'Apply'){
            if(-not(Test-BastosFeatureAvailable $definition)){[void]$items.Add((Get-BastosStatusResult $definition));continue}
            if($definition.Key -ne 'ClassicContextMenu' -and -not(Test-Path -LiteralPath $backupPath -PathType Leaf)){
                $snapshot=[pscustomobject]@{Option=$definition.Key;CreatedUtc=[datetime]::UtcNow.ToString('o');WindowsBuild=[Environment]::OSVersion.Version.Build;Registry=@($definition.Registry|ForEach-Object{Get-BastosRegistrySnapshot $_});Services=@($definition.Services|ForEach-Object{Get-BastosServiceSnapshot $_});Tasks=@($definition.Tasks|ForEach-Object{Get-BastosTaskSnapshot $_});ThemePath=if($definition.Key -eq 'DarkMode'){[string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -Name CurrentTheme).CurrentTheme}else{$null}}
                Save-BastosJson $backupPath $snapshot
            }
            foreach($target in @($definition.Registry)){Set-BastosRegistryTarget $target}
            foreach($target in @($definition.Services)){Set-BastosServiceTarget $target}
            foreach($target in @($definition.Tasks)){Set-BastosTaskTarget $target}
            if($definition.Key -eq 'DarkMode'){Set-BastosDarkTheme}
        }elseif($definition.Key -eq 'ClassicContextMenu'){
            # Explicitly restore the Windows 11 default, even if the classic key
            # was created outside BASTOS or already existed before its backup.
            $contextKey='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
            if(Test-Path -LiteralPath $contextKey){Remove-Item -LiteralPath $contextKey -Recurse -Force -ErrorAction Stop}
            if(Test-Path -LiteralPath $contextKey){throw 'Windows ne confirme pas la suppression de la clé du menu classique.'}
        }else{
            if(-not(Test-Path -LiteralPath $backupPath -PathType Leaf)){throw "Aucune sauvegarde BASTOS n est disponible pour $($definition.Title)."}
            $snapshot=Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8|ConvertFrom-Json
            if($definition.Key -eq 'DarkMode' -and $snapshot.PSObject.Properties['ThemePath'] -and $snapshot.ThemePath -and (Test-Path -LiteralPath $snapshot.ThemePath -PathType Leaf)){
                Start-Process -FilePath ([string]$snapshot.ThemePath) -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            foreach($entry in @($snapshot.Registry)){Restore-BastosRegistrySnapshot $entry}
            foreach($entry in @($snapshot.Services)){Restore-BastosServiceSnapshot $entry}
            if($snapshot.PSObject.Properties['Tasks']){foreach($entry in @($snapshot.Tasks)){Restore-BastosTaskSnapshot $entry}}
            $archive=Join-Path $backupRoot ("{0}-restaure-{1}.json" -f $definition.Key,(Get-Date -Format 'yyyyMMdd-HHmmss'))
            Move-Item -LiteralPath $backupPath -Destination $archive -Force
        }
        if(@($definition.Registry|Where-Object { [string]$_.Path -like 'HKCU:*' }).Count -gt 0){Send-BastosSettingsChanged}
        $status=Get-BastosStatusResult $definition
        if($definition.Key -eq 'ClassicContextMenu' -and $Action -eq 'Apply' -and -not $status.Active){throw 'Windows ne confirme pas la clé du menu classique.'}
        [void]$items.Add($status)
    }
}catch{$success=$false;$errorMessage=$_.Exception.Message}

Save-BastosJson $ResultPath ([pscustomobject]@{Success=$success;Action=$Action;Error=$errorMessage;Items=$items.ToArray();GeneratedUtc=[datetime]::UtcNow.ToString('o')})
if(-not $success){Write-Error $errorMessage;exit 1}
exit 0
