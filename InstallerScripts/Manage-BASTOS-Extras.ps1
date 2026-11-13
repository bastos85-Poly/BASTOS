[CmdletBinding()]
param(
 [ValidateSet('Get','Measure','Apply','Restore')][string]$Action='Get',
 [ValidateSet('apps','chrome','firefox','discord','usb','mtu','power')][string]$Option='apps',
 [string]$Target='', [string]$Destination='1.1.1.1',
 [ValidateRange(0,100)][int]$AcValue=0,[ValidateRange(0,100)][int]$DcValue=0,
 [string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$stateRoot=Join-Path $env:ProgramData ('BASTOS\Extras\'+$sid)
function Save($path,$doc){
 [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($doc|ConvertTo-Json -Depth 30))
  $stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,($path+'.previous'))}else{[IO.File]::Move($tmp,$path)}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
function Same($a,$b){($a|ConvertTo-Json -Depth 15 -Compress) -ceq ($b|ConvertTo-Json -Depth 15 -Compress)}
function RegRead($path,$name){
 $k=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
 if(-not $k -or $k.GetValueNames() -notcontains $name){return [pscustomobject]@{Exists=$false;Kind='';Value=$null}}
 [pscustomobject]@{Exists=$true;Kind=$k.GetValueKind($name).ToString();Value=$k.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
}
function RegTarget($path,$name,$value){[pscustomobject]@{Key=($path+'\'+$name);Type='Registry';Path=$path;Name=$name;Desired=[pscustomobject]@{Exists=$true;Kind='DWord';Value=$value}}}
function HashName($s){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)))).Replace('-','')}finally{$sha.Dispose()}}
function JournalPath($name){Join-Path $stateRoot ((HashName $name)+'.json')}
function ReadJournal($path){
 if(Test-Path -LiteralPath $path){$j=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;if($j.User -ne $sid -or $j.Version -ne 1){throw 'Sauvegarde incompatible.'};return $j}
 [pscustomobject]@{Version=1;User=$sid;Items=@()}
}
function HasBackup($name){try{@((ReadJournal (JournalPath $name)).Items).Count -gt 0}catch{$false}}
function DiscordRunning { @(Get-Process -Name Discord,DiscordCanary,DiscordPTB -ErrorAction SilentlyContinue).Count -gt 0 }
function AppInventory {
 $chromePaths=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe","$env:USERPROFILE\scoop\apps\googlechrome\current\chrome.exe")
 $firefoxPaths=@("$env:ProgramFiles\Mozilla Firefox\firefox.exe","${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe","$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe","$env:USERPROFILE\scoop\apps\firefox\current\firefox.exe")
 foreach($app in @(@{Id='chrome';Name='Google Chrome';Paths=$chromePaths;Policy='HKCU:\Software\Policies\Google\Chrome';Value='HardwareAccelerationModeEnabled'},@{Id='firefox';Name='Mozilla Firefox';Paths=$firefoxPaths;Policy='HKCU:\Software\Policies\Mozilla\Firefox';Value='HardwareAcceleration'})){
  $paths=@($app.Paths)
  foreach($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\')){
   $exe=if($app.Id -eq 'chrome'){'chrome.exe'}else{'firefox.exe'};$reg=Get-Item -LiteralPath ($base+$exe) -ErrorAction SilentlyContinue
   if($reg){$paths+=@([string]$reg.GetValue(''))}
  }
  $installed=@($paths|Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}).Count -gt 0
  $v=RegRead $app.Policy $app.Value
  $machine=RegRead ($app.Policy.Replace('HKCU:','HKLM:')) $app.Value
  $effective=if($machine.Exists){$machine}else{$v}
  [pscustomobject]@{Id=$app.Id;Name=$app.Name;Installed=$installed;Applied=($effective.Exists -and $effective.Value -eq 0);CanRestore=(HasBackup $app.Id);State=$(if(-not $installed){'Application non detectee.'}elseif($machine.Exists -and $machine.Value -ne 0){'Strategie machine prioritaire : le rendu GPU ne peut pas etre desactive ici.'}elseif($effective.Exists -and $effective.Value -eq 0){'Preference permanente configuree; relancer le navigateur si ouvert.'}else{'Rendu GPU non desactive par cette preference.'})}
 }
 $file=Join-Path $env:APPDATA 'discord\settings.json';$applied=$false
 $invalid=$false
 if(Test-Path -LiteralPath $file){try{$d=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json;if($d.PSObject.Properties['enableHardwareAcceleration']){$applied=$d.enableHardwareAcceleration -eq $false}}catch{$invalid=$true}}
 [pscustomobject]@{Id='discord';Name='Discord';Installed=((Test-Path -LiteralPath $file) -and -not $invalid);Applied=$applied;CanRestore=(HasBackup 'discord');State=$(if($invalid){'Preferences Discord illisibles; aucune modification possible.'}elseif(-not(Test-Path -LiteralPath $file)){'Profil Discord non detecte.'}elseif($applied){'Preference permanente configuree; relancer Discord si ouvert.'}else{'Rendu GPU non desactive par cette preference.'})}
}
function UsbInventory {
 $base='HKLM:\SYSTEM\CurrentControlSet\Enum\USB'
 foreach($group in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)){
  foreach($device in @(Get-ChildItem -LiteralPath $group.PSPath -ErrorAction SilentlyContinue)){
   $path=$device.PSPath+'\Device Parameters\WDF';$v=RegRead $path 'IdleInWorkingState'
   if(-not $v.Exists -or $v.Kind -ne 'DWord' -or $v.Value -notin @(0,1)){continue}
   $prop=Get-ItemProperty -LiteralPath $device.PSPath
   $name=if($prop.PSObject.Properties['FriendlyName']){[string]$prop.FriendlyName}else{([string]$prop.DeviceDesc -split ';')[-1]}
   $id=$group.PSChildName+'\'+$device.PSChildName
   [pscustomobject]@{Id=$id;Name=($name+' - '+$id);Path=$path;Current=[int]$v.Value;State=$(if($v.Value -eq 0){'Veille pilote desactivee'}else{'Veille pilote autorisee'});CanRestore=(HasBackup ('usb:'+ $id))}
  }
 }
}
function AdapterInventory {
 foreach($a in @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)){
  $i=Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue|Select-Object -First 1
  if($i){[pscustomobject]@{Id=$a.InterfaceGuid.ToString();Name=($a.Name+' - '+$a.InterfaceDescription+' ('+$a.Status+')');Index=[int]$a.ifIndex;Current=[int]$i.NlMtu;CanRestore=(HasBackup ('mtu:'+ $a.InterfaceGuid.ToString()))}}
 }
}
$powerDefs=@(
 @{Id='cpu-min';Name='Processeur : etat minimal (%)';Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='893dee8e-2bef-41e0-89c6-b55d0929964c'},
 @{Id='cpu-max';Name='Processeur : etat maximal (%)';Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='bc5038f7-23e0-4960-96da-33abaf5935ec'}
)
function ActivePlan {
 $lines=& "$env:windir\System32\powercfg.exe" /getactivescheme
 if($LASTEXITCODE -ne 0 -or ($lines -join '') -notmatch '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'){throw 'Plan actif inaccessible.'}
 $Matches[0].ToLowerInvariant()
}
function PowerRead($plan,$sub,$setting){
 $lines=& "$env:windir\System32\powercfg.exe" /qh $plan $sub $setting 2>&1
 if($LASTEXITCODE -ne 0){throw 'Option non exposee par le plan.'}
 $indexes=@($lines|ForEach-Object {if([string]$_ -match '0x([0-9a-fA-F]{8})\s*$'){[Convert]::ToInt32($Matches[1],16)}})
 if($indexes.Count -lt 2){throw 'Valeurs secteur/batterie non lisibles.'}
 [pscustomobject]@{Ac=$indexes[-2];Dc=$indexes[-1]}
}
function PowerInventory {
 $plan=ActivePlan
 $planName='Plan selectionne'
 foreach($line in @(& "$env:windir\System32\powercfg.exe" /list)){if([string]$line -match ([regex]::Escape($plan)+'.*?\((.*)\)')){$planName=$Matches[1];break}}
 foreach($d in $powerDefs){try{$v=PowerRead $plan $d.Sub $d.Setting;[pscustomobject]@{Id=($plan+':'+$d.Id);Name=$d.Name;Plan=$plan;PlanName=$planName;Sub=$d.Sub;Setting=$d.Setting;Ac=$v.Ac;Dc=$v.Dc;CanRestore=(HasBackup ('power:'+ $plan+':'+$d.Id))}}catch{}}
}
function ReadTarget($t){
 switch($t.Type){
  Registry {return RegRead $t.Path $t.Name}
  Discord {
   if(-not(Test-Path -LiteralPath $t.Path)){throw 'Profil Discord supprime; sauvegarde conservee.'}
   $d=Get-Content -LiteralPath $t.Path -Raw|ConvertFrom-Json
   if($d.PSObject.Properties[$t.Name]){return [pscustomobject]@{Exists=$true;Value=$d.($t.Name)}}
   return [pscustomobject]@{Exists=$false;Value=$null}
  }
  Mtu {
   $adapter=Get-NetAdapter -IncludeHidden|Where-Object {$_.InterfaceGuid.ToString() -eq $t.Path}|Select-Object -First 1
   if(-not $adapter){throw 'Carte reseau absente; sauvegarde conservee.'}
   $v=Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -PolicyStore $t.Name -ErrorAction Stop|Select-Object -First 1
   if(-not $v){throw 'Configuration IPv4 absente; sauvegarde conservee.'};return [int]$v.NlMtu
  }
  Power {$parts=$t.Path.Split('|');return PowerRead $parts[0] $parts[1] $parts[2]}
 }
}
function WriteTarget($t,$v){
 switch($t.Type){
  Registry {
   if($v.Exists){if(-not(Test-Path -LiteralPath $t.Path)){New-Item -Path $t.Path -Force|Out-Null};New-ItemProperty -LiteralPath $t.Path -Name $t.Name -Value $v.Value -PropertyType $v.Kind -Force|Out-Null}
   elseif(Test-Path -LiteralPath $t.Path){Remove-ItemProperty -LiteralPath $t.Path -Name $t.Name -ErrorAction Stop}
  }
  Discord {
   if(DiscordRunning){throw 'Fermez Discord avant de modifier son fichier de preferences.'}
   $d=Get-Content -LiteralPath $t.Path -Raw|ConvertFrom-Json
   if($v.Exists){$d|Add-Member -NotePropertyName $t.Name -NotePropertyValue $v.Value -Force}else{$d.PSObject.Properties.Remove($t.Name)}
   Save $t.Path $d
  }
  Mtu {
   $adapter=Get-NetAdapter -IncludeHidden|Where-Object {$_.InterfaceGuid.ToString() -eq $t.Path}|Select-Object -First 1
   if(-not $adapter){throw 'Carte reseau absente.'}
   Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -PolicyStore $t.Name -NlMtu ([uint32]$v) -Confirm:$false -ErrorAction Stop
  }
  Power {
   $parts=$t.Path.Split('|')
   foreach($mode in @('ac','dc')){$value=if($mode -eq 'ac'){$v.Ac}else{$v.Dc};$null=& "$env:windir\System32\powercfg.exe" ('/set'+$mode+'valueindex') $parts[0] $parts[1] $parts[2] ([string]$value);if($LASTEXITCODE -ne 0){throw 'Modification du plan refusee.'}}
   if((ActivePlan) -eq $parts[0]){$null=& "$env:windir\System32\powercfg.exe" /setactive $parts[0];if($LASTEXITCODE -ne 0){throw 'Reactivation du plan refusee.'}}
  }
 }
}
function ValidateSavedTarget($key,$t){
 # A restoration journal is data, never authority to write an arbitrary path.
 $valid=$false
 switch -Regex ($key){
  '^chrome$' {$valid=$t.Type -eq 'Registry' -and $t.Path -eq 'HKCU:\Software\Policies\Google\Chrome' -and $t.Name -eq 'HardwareAccelerationModeEnabled'}
  '^firefox$' {$valid=$t.Type -eq 'Registry' -and $t.Path -eq 'HKCU:\Software\Policies\Mozilla\Firefox' -and $t.Name -eq 'HardwareAcceleration'}
  '^discord$' {$valid=$t.Type -eq 'Discord' -and $t.Path -eq (Join-Path $env:APPDATA 'discord\settings.json') -and $t.Name -eq 'enableHardwareAcceleration'}
  '^usb:(.+)$' {
   $id=$Matches[1]
   $expected='HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\'+$id+'\Device Parameters\WDF'
   $actual=([string]$t.Path -replace '^.*Registry::','')
   $segments=$id.Split('\');$valid=$segments.Count -eq 2 -and @($segments|Where-Object {$_ -notmatch '^[a-zA-Z0-9_&.{}-]+$'}).Count -eq 0 -and $t.Type -eq 'Registry' -and $actual -eq $expected -and $t.Name -eq 'IdleInWorkingState'
  }
  '^mtu:(.+)$' {$id=$Matches[1];$guid=[guid]::Empty;$valid=[guid]::TryParse($id,[ref]$guid) -and $t.Type -eq 'Mtu' -and $t.Path -eq $id -and $t.Name -in @('ActiveStore','PersistentStore')}
  '^power:([^:]+):(cpu-min|cpu-max)$' {
   $plan=$Matches[1];$settingId=$Matches[2];$guid=[guid]::Empty;$d=@($powerDefs|Where-Object Id -eq $settingId)
   $valid=[guid]::TryParse($plan,[ref]$guid) -and $d.Count -eq 1 -and $t.Type -eq 'Power' -and $t.Path -eq ($plan+'|'+$d[0].Sub+'|'+$d[0].Setting)
  }
 }
 if(-not $valid){throw 'Cible de sauvegarde incompatible; aucune ecriture autorisee.'}
 if($t.Type -eq 'Registry' -and $t.Original.Exists -and $t.Original.Kind -notin @('DWord','String','ExpandString','QWord','Binary','MultiString')){throw 'Type de sauvegarde incompatible.'}
 if($t.Type -eq 'Mtu' -and ([long]$t.Original -lt 576 -or [long]$t.Original -gt 65535)){throw 'MTU sauvegardee invalide.'}
 if($t.Type -eq 'Power' -and ($t.Original.Ac -lt 0 -or $t.Original.Ac -gt 100 -or $t.Original.Dc -lt 0 -or $t.Original.Dc -gt 100)){throw 'Valeurs du plan sauvegarde invalides.'}
}
function ApplyTargets($key,$targets){
 $path=JournalPath $key;$j=ReadJournal $path
 foreach($t in $targets){
  $current=ReadTarget $t;$old=@($j.Items|Where-Object Key -eq $t.Key)
  if($old.Count){ValidateSavedTarget $key $old[0];if(-not(Same $current $old[0].Original) -and -not(Same $current $old[0].Desired)){throw 'Modification externe detectee; restaurez avant de reappliquer.'};$old[0].Desired=$t.Desired}
  else{$t|Add-Member -NotePropertyName Original -NotePropertyValue $current;$j.Items=@($j.Items)+@($t)}
 }
 Save $path $j
 foreach($t in $targets){if(-not(Same (ReadTarget $t) $t.Desired)){WriteTarget $t $t.Desired};if(-not(Same (ReadTarget $t) $t.Desired)){throw 'Valeur appliquee non confirmee; sauvegarde conservee.'}}
}
function RestoreTargets($key){
 $path=JournalPath $key;$j=ReadJournal $path
 if(-not @($j.Items).Count){throw 'Aucune sauvegarde pour cette option.'}
 $external=$false
 foreach($t in @($j.Items)){ValidateSavedTarget $key $t}
 foreach($t in @($j.Items)){
  $current=ReadTarget $t
  if(Same $current $t.Desired){WriteTarget $t $t.Original;if(-not(Same (ReadTarget $t) $t.Original)){throw 'Restauration non confirmee; sauvegarde conservee.'}}
  elseif(-not(Same $current $t.Original)){$external=$true}
  $j.Items=@($j.Items|Where-Object Key -ne $t.Key);Save $path $j
 }
 if($external){return 'Restauration terminee; les changements externes ont ete conserves.'};return 'Valeurs precedentes restaurees et verifiees.'
}
function RouteCheck($address,$index){
 $route=@(Find-NetRoute -RemoteIPAddress $address -ErrorAction Stop|Where-Object {$_.PSObject.Properties['InterfaceIndex']})
 if(-not @($route|Where-Object InterfaceIndex -eq $index).Count -or @($route|Where-Object InterfaceIndex -ne $index).Count){throw 'Le trajet vers cette destination utilise une autre carte. Selectionnez la carte utilisee par Windows.'}
}
function Probe($address,$size){
 $ping=[Net.NetworkInformation.Ping]::new()
 try{for($n=0;$n -lt 2;$n++){$r=$ping.Send($address,900,[byte[]]::new($size),[Net.NetworkInformation.PingOptions]::new(64,$true));if($r.Status -eq 'Success'){return 'Ok'};if($r.Status -eq 'PacketTooBig'){return 'TooBig'}};return 'Unknown'}finally{$ping.Dispose()}
}
function MeasureMtu($adapter){
 $ips=@([Net.Dns]::GetHostAddresses($Destination)|Where-Object AddressFamily -eq InterNetwork)
 if(-not $ips.Count){throw 'Destination IPv4 introuvable.'};$ip=$ips[0].ToString();RouteCheck $ip $adapter.Index
 if((Probe $ip 548) -ne 'Ok'){throw 'Mesure indeterminee : la destination ne confirme pas les sondes minimales. Aucun reglage modifie.'}
 $low=576;$high=[Math]::Min([int]$adapter.Current,9000)
 while($low -lt $high){$mid=[int][Math]::Ceiling(($low+$high+1)/2);$r=Probe $ip ($mid-28);if($r -eq 'Ok'){$low=$mid}elseif($r -eq 'TooBig'){$high=$mid-1}else{throw 'Mesure indeterminee : sondes sans reponse. Aucun reglage modifie.'}}
 RouteCheck $ip $adapter.Index
 $m=[pscustomobject]@{Adapter=$adapter.Id;Address=$ip;Mtu=$low;Current=$adapter.Current;Utc=[DateTime]::UtcNow.ToString('o')}
 Save (Join-Path $stateRoot ('mtu-measure-'+(HashName $adapter.Id)+'.json')) $m
 return $m
}
$mutex=[Threading.Mutex]::new($false,('Local\BASTOS-Extras-'+$sid));$owned=$false;$code=0
try{
 try{$owned=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$owned=$true}
 if(-not $owned){throw 'Une autre operation est en cours.'}
 $items=@();$message='';$measurement=$null
 if($Option -in @('apps','chrome','firefox','discord')){
  $apps=@(AppInventory)
  if($Action -ne 'Get'){
   if($Option -eq 'apps'){throw 'Choisir une application.'}
   if($Action -eq 'Measure'){throw 'Action incompatible.'}
   if($Action -eq 'Restore'){$message=RestoreTargets $Option}
   else{
    if(-not ($apps|Where-Object Id -eq $Option).Installed){throw 'Application ou profil non detecte.'}
    if($Option -in @('chrome','firefox')){
     $machinePath=if($Option -eq 'chrome'){'HKLM:\Software\Policies\Google\Chrome'}else{'HKLM:\Software\Policies\Mozilla\Firefox'}
     $machineName=if($Option -eq 'chrome'){'HardwareAccelerationModeEnabled'}else{'HardwareAcceleration'}
     $machine=RegRead $machinePath $machineName
     if($machine.Exists -and $machine.Value -ne 0){throw 'Une strategie machine impose le rendu GPU; aucune preference utilisateur modifiee.'}
    }
    $targetRecord=switch($Option){
     chrome {RegTarget 'HKCU:\Software\Policies\Google\Chrome' 'HardwareAccelerationModeEnabled' 0}
     firefox {RegTarget 'HKCU:\Software\Policies\Mozilla\Firefox' 'HardwareAcceleration' 0}
     discord {if(DiscordRunning){throw 'Fermez Discord avant application.'};[pscustomobject]@{Key='discord:enableHardwareAcceleration';Type='Discord';Path=(Join-Path $env:APPDATA 'discord\settings.json');Name='enableHardwareAcceleration';Desired=[pscustomobject]@{Exists=$true;Value=$false}}}
    }
    ApplyTargets $Option @($targetRecord);$message='Preference permanente appliquee et relue. Relancez cette application si elle est ouverte.'
   };$apps=@(AppInventory)
  }
  $items=@($apps|Where-Object {$Option -eq 'apps' -or $_.Id -eq $Option})
 }elseif($Option -eq 'usb'){
  if($Action -ne 'Get'){
   if($Action -eq 'Restore'){$message=RestoreTargets ('usb:'+ $Target)}
   elseif($Action -eq 'Apply'){$d=@(UsbInventory|Where-Object Id -ceq $Target);if($d.Count -ne 1){throw 'Selection USB absente ou propriete non exposee.'};ApplyTargets ('usb:'+ $Target) @((RegTarget $d[0].Path 'IdleInWorkingState' 0));$message='Preference pilote sauvegardee et relue. Une reconnexion du peripherique ou un redemarrage peut etre necessaire.'}
   else{throw 'Action incompatible.'}
  };$items=@(UsbInventory)
 }elseif($Option -eq 'mtu'){
  $adapters=@(AdapterInventory)
  if($Action -eq 'Restore'){$message=RestoreTargets ('mtu:'+ $Target)}
  elseif($Action -ne 'Get'){
   $a=@($adapters|Where-Object Id -eq $Target);if($a.Count -ne 1){throw 'Choisir une carte active.'}
   if($Action -eq 'Measure'){$measurement=MeasureMtu $a[0];$message='MTU observee vers '+$measurement.Address+' : '+$measurement.Mtu+' octets. Resultat propre a ce trajet; aucun gain de ping garanti.'}
   else{
    $file=Join-Path $stateRoot ('mtu-measure-'+(HashName $Target)+'.json')
    if(-not(Test-Path -LiteralPath $file)){throw 'Lancez un diagnostic avant application.'}
    $m=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
    if($m.Adapter -ne $Target -or ([DateTime]::UtcNow-[DateTime]::Parse($m.Utc).ToUniversalTime()).TotalMinutes -gt 10 -or $m.Mtu -lt 576 -or $m.Mtu -gt 9000 -or $a[0].Current -ne $m.Current){throw 'Mesure perimee ou configuration modifiee; relancez le diagnostic.'}
    RouteCheck $m.Address $a[0].Index
    $targets=@(foreach($store in @('PersistentStore','ActiveStore')){[pscustomobject]@{Key=('mtu:'+ $Target+':'+$store);Type='Mtu';Path=$Target;Name=$store;Desired=[int]$m.Mtu}})
    ApplyTargets ('mtu:'+ $Target) $targets;$message='MTU appliquee et relue sur cette carte uniquement (active et persistante).'
   }
  };$items=@(AdapterInventory)
 }elseif($Option -eq 'power'){
  if($Action -eq 'Restore'){$message=RestoreTargets ('power:'+ $Target)}
  elseif($Action -eq 'Apply'){
   $p=@(PowerInventory|Where-Object Id -eq $Target);if($p.Count -ne 1){throw 'Le plan actif a change; actualisez la selection.'}
   $otherId=if($Target.EndsWith(':cpu-min')){'cpu-max'}else{'cpu-min'};$other=PowerInventory|Where-Object {$_.Id.EndsWith(':'+ $otherId)}
   if(-not $other){throw 'Bornes processeur non disponibles.'}
   if(($otherId -eq 'cpu-max' -and ($AcValue -gt $other.Ac -or $DcValue -gt $other.Dc)) -or ($otherId -eq 'cpu-min' -and ($AcValue -lt $other.Ac -or $DcValue -lt $other.Dc))){throw 'Le minimum doit rester inferieur ou egal au maximum, sur secteur et batterie.'}
   $t=[pscustomobject]@{Key=('power:'+ $Target);Type='Power';Path=($p[0].Plan+'|'+$p[0].Sub+'|'+$p[0].Setting);Name='Indexes';Desired=[pscustomobject]@{Ac=$AcValue;Dc=$DcValue}}
   ApplyTargets ('power:'+ $Target) @($t);$message='Valeurs secteur/batterie du plan selectionne appliquees et relues.'
  }elseif($Action -ne 'Get'){throw 'Action incompatible.'};$items=@(PowerInventory)
 }
 $doc=[pscustomobject]@{Success=$true;Message=$message;Items=$items;Measurement=$measurement}
}catch{$code=1;$doc=[pscustomobject]@{Success=$false;Message=$_.Exception.Message;Items=@();Measurement=$null}}
finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
if($ResultPath){Save $ResultPath $doc}else{$doc|ConvertTo-Json -Depth 30}
exit $code
