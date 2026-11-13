[CmdletBinding()]
param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][ValidateSet('Enable','Restore','Get')][string]$Action,[string]$ResultPath='', [string]$ExpectedUserSid='')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function New-RegSetting($h,$p,$n,$v,$k='DWord'){[pscustomobject]@{Hive=$h;Path=$p;Name=$n;Value=$v;Kind=$k}}
# PowerShell fournit déjà l'alias global `r` pour Invoke-History. Sans cet alias
# local, les définitions ci-dessous appellent l'historique au lieu de construire un réglage.
Set-Alias -Name R -Value New-RegSetting -Scope Script -Option AllScope -Force
$lm='HKLM';$cu='HKCU'
$script:WidgetsPolicy='Feeds'
$build=[Environment]::OSVersion.Version.Build
if($build-ge 22000){
 $script:WidgetsPolicy='AllowNewsAndInterests'
 $admx=Join-Path $env:windir 'PolicyDefinitions\NewsAndInterests.admx'
 if((Test-Path -LiteralPath $admx)-and([IO.File]::ReadAllText($admx).Contains('name="DisableWidgetsBoard"'))){$script:WidgetsPolicy='DisableWidgetsBoard'}
}

$defs=@{
 telemetry=@(
  R $lm 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowCommercialDataPipeline' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'MicrosoftEdgeDataOptIn' 0;R $cu 'SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0;R $cu 'Software\Policies\Microsoft\Windows\EdgeUI' 'DisableMFUTracking' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0;R $cu 'SOFTWARE\Policies\Microsoft\Assistance\Client\1.0' 'NoExplicitFeedback' 1;R $lm 'SOFTWARE\Policies\Microsoft\Assistance\Client\1.0' 'NoActiveHelp' 1;R $cu 'SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0;R $cu 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0)
 'error-reporting'=@(R $lm 'SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1)
 advertising=@(R $lm 'SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1;R $cu 'SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1;R $cu 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0;R $cu 'SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1;R $cu 'SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1;R $cu 'SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0;R $cu 'Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1)
 news=@(if($script:WidgetsPolicy-eq'DisableWidgetsBoard'){R $lm 'SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsBoard' 1}elseif($script:WidgetsPolicy-eq'AllowNewsAndInterests'){R $lm 'SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0}else{R $lm 'SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0})
 'meet-now'=@(R $cu 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1)
 'activity-history'=@(R $lm 'SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivitiesOnUserConsent' 0;R $lm 'SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0)
 location=@(R $lm 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1;R $lm 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableSensors' 1;R $lm 'SYSTEM\Maps' 'AutoUpdateEnabled' 0;R $cu 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Permissions\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' 0;R $cu 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String';R $lm 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String';R $cu 'Software\Microsoft\Windows\CurrentVersion\Geolocation' 'Status' 0;R $lm 'SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' 'Status' 0;R $lm 'Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value' 0;R $lm 'Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value' 0)
 autologger=@(@('AppModel','Cellcore','CloudExperienceHostOobe','DataMarket','DiagLog','Diagtrack-Listener','LwtNetLog','SQMLogger','WdiContextLog','WiFiSession')|ForEach-Object{R $lm "SYSTEM\CurrentControlSet\Control\WMI\Autologger\$_" 'Start' 0})
 cortana=@(@('AllowCortana','AllowCloudSearch','AllowCortanaAboveLock','AllowSearchToUseLocation','ConnectedSearchUseWeb')|ForEach-Object{R $lm 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' $_ 0})+@(R $cu 'Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0;R $cu 'Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent2' 0)
 copilot=@(R $lm 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1;R $cu 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1;R $cu 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0;R $lm 'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' '' 'String')
 'content-delivery'=@(@('ContentDeliveryAllowed','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled','SystemPaneSuggestionsEnabled')|ForEach-Object{R $cu 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $_ 0})
 'find-device'=@(R $lm 'SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0)
 'delivery-optimization'=@(R $lm 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0)
}
$taskDefs=@{
 telemetry=@('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Application Experience\MareBackup','\Microsoft\Windows\Application Experience\StartupAppTask','\Microsoft\Windows\Application Experience\PcaPatchDbTask','\Microsoft\Windows\Autochk\Proxy','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Feedback\Siuf\DmClient','\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload')
 'error-reporting'=@('\Microsoft\Windows\Windows Error Reporting\QueueReporting','\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector','\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver','\Microsoft\Windows\Diagnosis\Scheduled')
 location=@('\Microsoft\Windows\Maps\MapsUpdateTask')
}
function Base($h){if($h-eq'HKLM'){'Registry::HKEY_LOCAL_MACHINE'}else{'Registry::HKEY_USERS\'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}}
function SettingsFor($key){$result=@($defs[$key]);if($key-eq'telemetry'){$result+=@(@('DiagTrack','dmwappushservice','DcpSvc','diagnosticshub.standardcollector.service')|ForEach-Object{R $lm "SYSTEM\CurrentControlSet\Services\$_" 'Start' 4})};if($key-eq'error-reporting'){$result+=@(@('WerSvc','PcaSvc')|ForEach-Object{R $lm "SYSTEM\CurrentControlSet\Services\$_" 'Start' 4})};$result}
function Write-DurableText($path,$text){
 $dir=Split-Path $path -Parent;[IO.Directory]::CreateDirectory($dir)|Out-Null
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text);$stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()};if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,($path+'.previous'))}else{[IO.File]::Move($tmp,$path)}}finally{if(Test-Path -LiteralPath $tmp){[IO.File]::Delete($tmp)}}
}
function ReadRegistryTarget($i){
 $full=((Base $i.Hive)+'\'+$i.Path).Replace('Registry::','')
 $parts=$full -split '\\',2;$hive=switch($parts[0]){'HKEY_LOCAL_MACHINE'{[Microsoft.Win32.RegistryHive]::LocalMachine};'HKEY_USERS'{[Microsoft.Win32.RegistryHive]::Users};'HKEY_CURRENT_USER'{[Microsoft.Win32.RegistryHive]::CurrentUser};default{throw 'Ruche inconnue'}}
 $root=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,[Microsoft.Win32.RegistryView]::Registry64);$key=$null
 try{$key=$root.OpenSubKey($parts[1],$false);$exists=$null-ne$key -and $key.GetValueNames()-contains$i.Name;[pscustomobject]@{Exists=$exists;Value=if($exists){$key.GetValue($i.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null};Kind=if($exists){$key.GetValueKind($i.Name).ToString()}else{''}}}finally{if($key){$key.Dispose()};$root.Dispose()}
}
function ReadState($key){
 $matched=0;$total=0;$readable=$true;$details=@()
 foreach($i in @(SettingsFor $key)){
  $total++;try{
   $actual=ReadRegistryTarget $i
   if($actual.Exists -and "$($actual.Value)"-eq"$($i.Value)" -and $actual.Kind-eq$i.Kind){$matched++}else{$details+=($i.Hive+'\'+$i.Path+'\'+$i.Name+' : valeur absente ou différente')}
  }catch{$readable=$false;$details+=($i.Name+' : lecture impossible — '+$_.Exception.Message)}
 }
 if($taskDefs.ContainsKey($key)){
  try{
   $available=@(Get-ScheduledTask -ErrorAction Stop)
   foreach($t in @($taskDefs[$key])){$name=Split-Path $t -Leaf;$path=$t.Substring(0,$t.Length-$name.Length);$task=@($available|Where-Object {$_.TaskPath-eq$path -and $_.TaskName-eq$name});if($task.Count){$total++;if($task[0].State-eq'Disabled'){$matched++}else{$details+=('Tâche encore activée : '+$t)}}}
  }catch{$readable=$false;$details+=('Lecture des tâches impossible — '+$_.Exception.Message)}
 }
 $applied=$readable -and $matched-eq$total
 $label=if(-not $readable){'État indisponible'}elseif($applied){'Appliqué et vérifié'}elseif($matched-gt 0){'Partiellement appliqué'}else{'Non appliqué'}
 [pscustomobject]@{Applied=$applied;Readable=$readable;Matched=$matched;Total=$total;Message=($label+' — '+$matched+'/'+$total+' contrôles conformes');Details=$details}
}
if($Action-eq'Get'){$states=[ordered]@{};$readable=[ordered]@{};$checks=[ordered]@{};foreach($key in @($defs.Keys)){$state=ReadState $key;$states[$key]=[bool]$state.Applied;$readable[$key]=[bool]$state.Readable;$checks[$key]=$state};$result=[pscustomobject]@{Success=$true;Message='Etat reel de Windows lu.';States=$states;Readable=$readable;Checks=$checks;Context=[pscustomobject]@{UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;RegistryView='Registry64';Process64=[Environment]::Is64BitProcess;WidgetsPolicy=$script:WidgetsPolicy}};if($ResultPath){[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))};$result;exit 0}
if($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid){throw 'Compte administrateur différent du compte utilisateur : aucun réglage modifié.'}
if(-not $defs.ContainsKey($Id)){throw "Module inconnu: $Id"};$items=@(SettingsFor $Id);$tasks=@();if($taskDefs.ContainsKey($Id)){$tasks=@($taskDefs[$Id])};$stateDir=Join-Path $env:ProgramData 'BASTOS-ISO\State';$backup=Join-Path $stateDir "SecurityPrivacy-$Id.json";$taskBackup=Join-Path $stateDir "SecurityPrivacy-$Id-tasks.json";$appliedMarker=Join-Path $stateDir "SecurityPrivacy-$Id.applied"
try{
if($Action-eq'Enable'){
 New-Item -ItemType Directory -Force -Path $stateDir|Out-Null
 if(-not(Test-Path -LiteralPath $backup)){$saved=@($items|ForEach-Object{$p=(Base $_.Hive)+'\'+$_.Path;$x=Get-ItemProperty -LiteralPath $p -Name $_.Name -ErrorAction SilentlyContinue;$exists=$null-ne$x -and $null-ne$x.PSObject.Properties[$_.Name];[pscustomobject]@{Hive=$_.Hive;Path=$_.Path;Name=$_.Name;Exists=$exists;Value=if($exists){$x.($_.Name)}else{$null};Kind=if($exists){(Get-Item -LiteralPath $p -ErrorAction Stop).GetValueKind($_.Name).ToString()}else{$_.Kind}}});Write-DurableText $backup ($saved|ConvertTo-Json -Depth 5)}
 if($Id-eq'news'){
  $records=Get-Content -LiteralPath $backup -Raw|ConvertFrom-Json
  $savedRecords=@($records);$added=$false
  foreach($i in $items){if(-not @($savedRecords|Where-Object {$_.Hive-eq$i.Hive -and $_.Path-eq$i.Path -and $_.Name-eq$i.Name}).Count){$actual=ReadRegistryTarget $i;$savedRecords+=@([pscustomobject]@{Hive=$i.Hive;Path=$i.Path;Name=$i.Name;Exists=$actual.Exists;Value=$actual.Value;Kind=if($actual.Exists){$actual.Kind}else{$i.Kind}});$added=$true}}
  if($added){Write-DurableText $backup ($savedRecords|ConvertTo-Json -Depth 5)}
 }
 foreach($i in $items){$p=(Base $i.Hive)+'\'+$i.Path;if(-not(Test-Path -LiteralPath $p)){New-Item -Path $p -Force|Out-Null};$existing=Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue;$property=if($null-ne$existing){$existing.PSObject.Properties[$i.Name]}else{$null};$current=if($null-ne$property){$property.Value}else{$null};if($null-eq$current-or"$current"-ne"$($i.Value)"-or(Get-Item -LiteralPath $p).GetValueKind($i.Name).ToString()-ne$i.Kind){New-ItemProperty -LiteralPath $p -Name $i.Name -Value $i.Value -PropertyType $i.Kind -Force|Out-Null}}
 if($tasks.Count -gt 0){if(-not(Test-Path -LiteralPath $taskBackup)){$states=@($tasks|ForEach-Object{$name=Split-Path $_ -Leaf;$path=$_.Substring(0,$_.Length-$name.Length);$task=Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue;[pscustomobject]@{Path=$path;Name=$name;Enabled=($null-ne$task-and$task.State-ne'Disabled')}});Write-DurableText $taskBackup ($states|ConvertTo-Json)};foreach($t in $tasks){$name=Split-Path $t -Leaf;$path=$t.Substring(0,$t.Length-$name.Length);Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue|Out-Null}}
 $verified=ReadState $Id;$ok=[bool]$verified.Applied;$msg=$verified.Message
 if($ok){Write-DurableText $appliedMarker ((Get-Date).ToString('O'))}else{$msg+=' ; activation non confirmée. Sauvegarde conservée.'}

}else{
 if(Test-Path -LiteralPath $backup){ $restoreRecords=Get-Content -LiteralPath $backup -Raw|ConvertFrom-Json;foreach($i in $restoreRecords){ $p=(Base $i.Hive)+'\'+$i.Path;if(-not(Test-Path -LiteralPath $p)){New-Item -Path $p -Force|Out-Null};if($i.Exists){New-ItemProperty -LiteralPath $p -Name $i.Name -Value $i.Value -PropertyType $i.Kind -Force|Out-Null}else{Remove-ItemProperty -LiteralPath $p -Name $i.Name -ErrorAction SilentlyContinue}};Remove-Item -LiteralPath $backup -Force;$msg='Valeurs précédentes restaurées.'}else{$msg='Aucune sauvegarde BASTOS; état actuel conservé.'};if(Test-Path -LiteralPath $taskBackup){$restoreTasks=Get-Content -LiteralPath $taskBackup -Raw|ConvertFrom-Json;foreach($t in $restoreTasks){if($t.Enabled){Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue|Out-Null}};Remove-Item -LiteralPath $taskBackup -Force};Remove-Item -LiteralPath $appliedMarker -Force -ErrorAction SilentlyContinue;$ok=$true
}
}catch{$ok=$false;$verified=ReadState $Id;$msg='Activation ou restauration refusée : '+$_.Exception.Message}
$result=[pscustomobject]@{Success=$ok;Message=$msg;Id=$Id;State=if($Action-eq'Enable'){$verified}else{$null}};if($ResultPath){[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$result

if(-not $ok){exit 1}
