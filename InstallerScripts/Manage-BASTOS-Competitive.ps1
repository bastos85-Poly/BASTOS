[CmdletBinding()]
param(
 [ValidateSet('Get','Apply','Restore')][string]$Action='Get',
 [ValidateSet('all','audio-game','audio-power','udp-fastpath','mouse-queue','frame-timers','steam-gpu','sdl3')][string]$Id='all',
 [string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$root=Join-Path $env:ProgramData ('BASTOS\CompetitiveTuning\'+$sid)
$script:journal=$null
$script:journalPath=''
function Save-Document($path,$doc) {
 $dir=Split-Path $path -Parent;[IO.Directory]::CreateDirectory($dir)|Out-Null
 $tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($doc|ConvertTo-Json -Depth 30))
  $f=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
  if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,($path+'.previous'))}else{[IO.File]::Move($tmp,$path)}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
function Equal($a,$b){($a|ConvertTo-Json -Depth 15 -Compress) -eq ($b|ConvertTo-Json -Depth 15 -Compress)}
function Read-Registry($path,$name) {
 $key=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
 if($null -eq $key -or $key.GetValueNames() -notcontains $name){return [pscustomobject]@{Exists=$false;Kind='';Value=$null}}
 [pscustomobject]@{Exists=$true;Kind=$key.GetValueKind($name).ToString();Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
}
function RegTarget($path,$name,$value,$kind='DWord'){
 [pscustomobject]@{Key=($path+'\'+$name);Type='Registry';Path=$path;Name=$name;Desired=[pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}}
}
function Read-Bcd {
 $lines=& "$env:windir\System32\bcdedit.exe" /enum '{current}' 2>&1
 if($LASTEXITCODE -ne 0){throw 'Configuration des timers de demarrage inaccessible.'}
 $line=@($lines|Where-Object {$_ -match '^disabledynamictick\s+'})
 if(-not $line.Count){return [pscustomobject]@{Exists=$false;Value=''}}
 $v=([string]$line[0] -replace '^disabledynamictick\s+','').Trim()
 if($v -match '^(Yes|Oui|Ja|Si|True|1)$'){$v='yes'}elseif($v -match '^(No|Non|Nein|False|0)$'){$v='no'}else{throw 'Valeur BCD non reconnue; aucune modification.'}
 [pscustomobject]@{Exists=$true;Value=$v}
}
function Read-Target($t) {
 switch($t.Type){
  Registry {return Read-Registry $t.Path $t.Name}
  Bcd {return Read-Bcd}
  Shortcut {
   if(-not(Test-Path -LiteralPath $t.Path)){return [pscustomobject]@{Exists=$false;Target='';Value=''}}
   $s=(New-Object -ComObject WScript.Shell).CreateShortcut($t.Path)
   return [pscustomobject]@{Exists=$true;Target=$s.TargetPath;Value=$s.Arguments}
  }
  Audio {$a=[BastosCompetitiveAudio]::Read($t.Path);return [string]$a.($t.Name)}
 }
}
function Write-Target($t,$value) {
 switch($t.Type){
  Registry {
   if(-not $value.Exists){if(Test-Path -LiteralPath $t.Path){Remove-ItemProperty -LiteralPath $t.Path -Name $t.Name -ErrorAction Stop};return}
   if(-not(Test-Path -LiteralPath $t.Path)){New-Item -Path $t.Path -Force|Out-Null}
   $data=$value.Value;if($value.Kind -eq 'Binary'){$data=[byte[]]$data}
   New-ItemProperty -LiteralPath $t.Path -Name $t.Name -PropertyType $value.Kind -Value $data -Force|Out-Null
  }
  Bcd {
   if($value.Exists){$answer=& "$env:windir\System32\bcdedit.exe" /set '{current}' disabledynamictick $value.Value 2>&1}
   else{$answer=& "$env:windir\System32\bcdedit.exe" /deletevalue '{current}' disabledynamictick 2>&1}
   if($LASTEXITCODE -ne 0){throw ('BCD : '+($answer -join ' '))}
  }
  Shortcut {
   $s=(New-Object -ComObject WScript.Shell).CreateShortcut($t.Path)
   if($s.TargetPath -ne $value.Target){throw 'Cible du raccourci changee; aucune modification.'}
   $s.Arguments=$value.Value;$s.Save()
  }
  Audio {[BastosCompetitiveAudio]::Set($t.Path,$t.Name,[string]$value)}
 }
}
function Get-Targets($option) {
 $targets=[Collections.Generic.List[object]]::new();$warnings=[Collections.Generic.List[string]]::new()
 switch($option){
  'udp-fastpath' {
   $targets.Add((RegTarget 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters' 'FastSendDatagramThreshold' 1500))
   $targets.Add((RegTarget 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters' 'FastCopyReceiveThreshold' 1500))
  }
  'mouse-queue' {$targets.Add((RegTarget 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize' 1024))}
  'frame-timers' {
   $targets.Add((RegTarget 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1))
   $targets.Add([pscustomobject]@{Key='BCD:disabledynamictick';Type='Bcd';Path='';Name='';Desired=[pscustomobject]@{Exists=$true;Value='yes'}})
  }
  'sdl3' {
   foreach($name in @('SDL_WINDOWS_RAW_KEYBOARD','SDL_WINDOWS_RAW_MOUSE_NOLEGACY','SDL_WINDOWS_CLOSE_ON_ALT_F4')){$targets.Add((RegTarget 'HKCU:\Environment' $name '1' 'String'))}
  }
  'audio-power' {
   $class='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}'
   foreach($driver in @(Get-ChildItem -LiteralPath $class -ErrorAction SilentlyContinue | Where-Object PSChildName -match '^\d{4}$')){
    foreach($name in @('ConservationIdleTime','PerformanceIdleTime','IdlePowerState')){$targets.Add((RegTarget ($driver.PSPath+'\PowerSettings') $name ([byte[]](0,0,0,0)) 'Binary'))}
   }
  }
  'steam-gpu' {
   # Steam's Interface preference persists independently of the launch command.
   $steamExe=(Read-Registry 'HKCU:\Software\Valve\Steam' 'SteamExe').Value
   if($steamExe -and (Test-Path -LiteralPath ([string]$steamExe))){
    $targets.Add((RegTarget 'HKCU:\Software\Valve\Steam' 'GPUAccelWebViewsV3' 0))
   }
   foreach($path in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
    $v=Read-Registry $path 'Steam'
    if($v.Exists -and [string]$v.Value -match '(?i)steam\.exe' -and $v.Kind -in @('String','ExpandString')){
     $args=[string]$v.Value;if($args -notmatch '(?i)(^|\s)-cef-disable-gpu(\s|$)'){$args+=' -cef-disable-gpu'}
     $targets.Add((RegTarget $path 'Steam' $args $v.Kind))
    }
   }
   $folders=@('Desktop','CommonDesktopDirectory','Programs','CommonPrograms','Startup','CommonStartup')|ForEach-Object {[Environment]::GetFolderPath($_)}|Where-Object {$_ -and (Test-Path -LiteralPath $_)}|Select-Object -Unique
   $seen=@{};$shell=New-Object -ComObject WScript.Shell
   foreach($folder in $folders){foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter 'Steam*.lnk' -File -Recurse -ErrorAction SilentlyContinue)){
    if($seen.ContainsKey($file.FullName)){continue};$seen[$file.FullName]=$true
    $s=$shell.CreateShortcut($file.FullName)
    if([IO.Path]::GetFileName($s.TargetPath) -ine 'steam.exe' -or -not(Test-Path -LiteralPath $s.TargetPath)){continue}
    $args=$s.Arguments;if($args -notmatch '(?i)(^|\s)-cef-disable-gpu(\s|$)'){$args=($args+' -cef-disable-gpu').Trim()}
    $targets.Add([pscustomobject]@{Key=('Shortcut:'+ $file.FullName);Type='Shortcut';Path=$file.FullName;Name='';Desired=[pscustomobject]@{Exists=$true;Target=$s.TargetPath;Value=$args}})
   }}
  }
  'audio-game' {
   Import-Module (Join-Path $PSScriptRoot 'Bastos.CompetitiveAudio.psm1') -Force
   foreach($deviceId in [BastosCompetitiveAudio]::Ids()){
    try {
     $a=[BastosCompetitiveAudio]::Read($deviceId)
     try {
      $format=[BastosCompetitiveAudio]::DesiredFormat($deviceId)
      $bytes=[Convert]::FromBase64String($format)
      $bits=if($bytes.Length -ge 20 -and [BitConverter]::ToUInt16($bytes,0) -eq 65534){[BitConverter]::ToUInt16($bytes,18)}else{[BitConverter]::ToUInt16($bytes,14)}
      $spatial=if($null -eq $a.Spatial){'; son spatial non expose par ce peripherique'}else{''}
      $warnings.Add($a.Name+' : cible 48 kHz / '+$bits+' bits'+$spatial+'.')
      $targets.Add([pscustomobject]@{Key=($deviceId+':Format');Type='Audio';Path=$deviceId;Name='Format';Desired=$format})
     }catch{$warnings.Add($a.Name+': format 48 kHz compatible non expose; format actuel conserve.')}
     $targets.Add([pscustomobject]@{Key=($deviceId+':Effects');Type='Audio';Path=$deviceId;Name='Effects';Desired='1'})
     if($null -ne $a.Spatial){$targets.Add([pscustomobject]@{Key=($deviceId+':Spatial');Type='Audio';Path=$deviceId;Name='Spatial';Desired='0'})}

    }catch{$warnings.Add('Un peripherique audio est inaccessible; aucune modification sur ce peripherique.')}
   }
  }
 }
 [pscustomobject]@{Targets=@($targets.ToArray());Warnings=@($warnings.ToArray())}
}
function Read-Journal($path){
 if(Test-Path -LiteralPath $path){$doc=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;if($doc.Version -ne 1 -or $doc.User -ne $sid){throw 'Sauvegarde incompatible.'};return $doc}
 [pscustomobject]@{Version=1;User=$sid;Items=@()}
}
function Run-Option($option){
 $script:journalPath=Join-Path $root ($option+'.json');$script:journal=Read-Journal $script:journalPath
 $messages=[Collections.Generic.List[string]]::new();$technical=[Collections.Generic.List[string]]::new();$failures=0;$applied=0;$total=0
 if($Action -eq 'Restore'){
  if(-not @($script:journal.Items).Count){return [pscustomobject]@{Id=$option;Success=$true;Applied=$false;Message='Aucune modification BASTOS sauvegardee pour cette option; aucune valeur changee.';Details=@();Pending=0}}
  if($option -eq 'audio-game'){Import-Module (Join-Path $PSScriptRoot 'Bastos.CompetitiveAudio.psm1') -Force}
  $restoreCurrent=@{};$restoreErrors=@{}
  foreach($t in @($script:journal.Items)){try{$restoreCurrent[$t.Key]=Read-Target $t}catch{$restoreErrors[$t.Key]=$_.Exception.Message}}
  foreach($t in @($script:journal.Items)){
   try{
    if($restoreErrors.ContainsKey($t.Key)){throw $restoreErrors[$t.Key]}
    $current=$restoreCurrent[$t.Key]
    if(Equal $current $t.Desired){Write-Target $t $t.Original;if(-not(Equal (Read-Target $t) $t.Original)){throw 'Restauration non confirmee'}}
    elseif(-not(Equal $current $t.Original)){$messages.Add($t.Key+': changement externe conserve')}
    $script:journal.Items=@($script:journal.Items|Where-Object Key -ne $t.Key);Save-Document $script:journalPath $script:journal
   }catch{
    $failures++
    if($t.Type -eq 'Audio'){
     $label='Peripherique audio';try{$label=[BastosCompetitiveAudio]::Read($t.Path).Name}catch{}
     $field=switch($t.Name){Format{'format 48 kHz'};Effects{'ameliorations audio'};Spatial{'son spatial'};Period{'periode audio'};default{$t.Name}}
     $messages.Add($label+' : '+$field+' refuse par Windows ou le pilote; valeur non confirmee.')
    }else{$messages.Add($t.Key+': '+$_.Exception.Message)}
   }
  }
  return [pscustomobject]@{Id=$option;Success=($failures -eq 0);Applied=$false;Message=$(if($failures){'Restauration partielle; sauvegarde conservee.'}else{'Valeurs precedentes restaurees; changements externes conserves.'});Details=@($messages.ToArray());TechnicalDetails=@($technical.ToArray());Pending=@($script:journal.Items).Count}
 }
 $plan=Get-Targets $option
 foreach($warning in $plan.Warnings){$messages.Add($warning)}
 $capturedNow=@{};$snapshotFailed=@{}
 if($Action -eq 'Apply'){
  # An audio format write may reset effects and periods. Capture all fields first.
  foreach($t in $plan.Targets){
   if(@($script:journal.Items|Where-Object Key -eq $t.Key).Count){continue}
   try{
    $original=Read-Target $t
    if($t.Type -eq 'Audio' -or -not(Equal $original $t.Desired)){
     $t|Add-Member -NotePropertyName Original -NotePropertyValue $original
     $script:journal.Items=@($script:journal.Items)+@($t);$capturedNow[$t.Key]=$true
    }
   }catch{$snapshotFailed[$t.Key]=$_.Exception.Message}
  }
  Save-Document $script:journalPath $script:journal
 }
 foreach($t in $plan.Targets){
  $total++
  try{
   if($snapshotFailed.ContainsKey($t.Key)){throw ('Sauvegarde impossible : '+$snapshotFailed[$t.Key])}
   $current=Read-Target $t
   $isDesired=Equal $current $t.Desired
   if($Action -eq 'Apply'){
    $saved=@($script:journal.Items|Where-Object Key -eq $t.Key)
    if($saved.Count -and -not(Equal $saved[0].Desired $t.Desired)){
     if(-not(Equal $current $saved[0].Desired) -and -not(Equal $current $saved[0].Original)){throw 'Changement externe detecte; restaurer avant de reappliquer.'}
     $saved[0].Desired=$t.Desired;Save-Document $script:journalPath $script:journal
    }
   }
   if($Action -eq 'Apply' -and -not $isDesired){
    $previous=@($script:journal.Items|Where-Object Key -eq $t.Key)
    if($previous.Count){if(-not $capturedNow.ContainsKey($t.Key) -and -not(Equal $current $previous[0].Desired) -and -not(Equal $current $previous[0].Original)){throw 'Changement externe detecte; restaurer avant de reappliquer.'}}
    else{$t|Add-Member -NotePropertyName Original -NotePropertyValue $current;$script:journal.Items=@($script:journal.Items)+@($t);Save-Document $script:journalPath $script:journal}
    Write-Target $t $t.Desired
    if(-not(Equal (Read-Target $t) $t.Desired)){throw 'Valeur appliquee non confirmee'}
    $isDesired=$true
   }
   if($isDesired){$applied++}
  }catch{
    $failures++
    if($t.Type -eq 'Audio'){
     $label='Peripherique audio';try{$label=[BastosCompetitiveAudio]::Read($t.Path).Name}catch{}
     $field=switch($t.Name){Format{'format 48 kHz'};Effects{'ameliorations audio'};Spatial{'son spatial'};Period{'periode audio'};default{$t.Name}}
     $messages.Add($label+' : '+$field+' refuse par Windows ou le pilote; valeur non confirmee.')
    }else{$messages.Add($t.Key+': '+$_.Exception.Message)}
   }
 }
 $complete=$total -gt 0 -and $applied -eq $total -and $failures -eq 0
 $message=if(-not $total){'Aucune cible compatible detectee.'}elseif($complete){"Applique et verifie : $applied/$total reglage(s) compatibles."}elseif($Action -eq 'Get'){"Etat actuel : $applied/$total reglage(s) conformes."}else{"Application partielle : $applied/$total. Consulter les details."}
 $restart=switch($option){'steam-gpu'{'Si Steam est ouvert, le relancer une fois. Preference conservee apres redemarrage du PC, y compris lors du lancement par un jeu.'};'sdl3'{'Fermer puis relancer les jeux; une nouvelle session Windows peut etre necessaire.'};'audio-game'{'Relancer les applications audio. La periode audio reste geree par Windows et les applications.'};default{'Redemarrage Windows recommande.'}}
 [pscustomobject]@{Id=$option;Success=($Action -eq 'Get' -or $complete);Applied=$complete;Message=($message+' '+$restart);Details=@($messages.ToArray());TechnicalDetails=@($technical.ToArray());Pending=@($script:journal.Items).Count}
}
$mutex=[Threading.Mutex]::new($false,'Global\BASTOS-CompetitiveTuning');$owned=$false;$exitCode=0
try{
 try{$owned=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$owned=$true}
 if(-not $owned){throw 'Une autre modification de ces reglages est en cours.'}
 $ids=if($Id -eq 'all'){@('audio-game','audio-power','udp-fastpath','mouse-queue','frame-timers','steam-gpu','sdl3')}else{@($Id)}
 if($Action -ne 'Get' -and $Id -eq 'all'){throw 'Choisir une option individuelle; application globale non proposee.'}
 $results=@(foreach($option in $ids){try{Run-Option $option}catch{[pscustomobject]@{Id=$option;Success=$false;Applied=$false;Message=$_.Exception.Message;Details=@()}}})
 $success=@($results|Where-Object {-not $_.Success}).Count -eq 0
 $doc=[pscustomobject]@{Success=$success;Results=$results;Message=($results.Message -join "`n");UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
 if(-not $success){$exitCode=1}
}catch{$doc=[pscustomobject]@{Success=$false;Message=$_.Exception.Message;Results=@()};$exitCode=1}
finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
if($ResultPath){Save-Document $ResultPath $doc}else{$doc|ConvertTo-Json -Depth 30}
exit $exitCode




