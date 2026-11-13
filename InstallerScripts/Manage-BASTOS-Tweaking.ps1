[CmdletBinding()]
param(
    [ValidateSet('Get','Enable','Disable','Apply','RestoreQuantum')][string]$Action='Get',
    [string]$Option='',
    [string]$Value='',
    [Parameter(Mandatory)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:BcdAlreadyDefault=$false

function Get-Dword([string]$Path,[string]$Name,[int]$Default=0){try{[int](Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop)}catch{$Default}}
function Set-Dword([string]$Path,[string]$Name,[int]$Data){if(-not(Test-Path $Path)){New-Item $Path -Force|Out-Null};New-ItemProperty $Path -Name $Name -PropertyType DWord -Value $Data -Force|Out-Null}
function Remove-Value([string]$Path,[string]$Name){if(Test-Path $Path){Remove-ItemProperty $Path -Name $Name -ErrorAction SilentlyContinue}}
function Get-BcdValue([string]$Name,[string]$Default){$text=& bcdedit.exe /enum '{current}' 2>$null|Out-String;if($text -match "(?im)^$([regex]::Escape($Name))\s+(\S+)"){$Matches[1]}else{$Default}}
function Has-BcdValue([string]$Name){$text=& bcdedit.exe /enum '{current}' 2>$null|Out-String;[bool]($text -match "(?im)^$([regex]::Escape($Name))\s+")}
function Invoke-BcdEdit([string[]]$Arguments){
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=Join-Path $env:SystemRoot 'System32\bcdedit.exe'
 $info.Arguments=$Arguments -join ' '
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.StandardOutputEncoding=[Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
 $info.StandardErrorEncoding=$info.StandardOutputEncoding
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 try{
  if(-not $process.Start()){throw 'Impossible de lancer BCDEdit.'}
  $outputTask=$process.StandardOutput.ReadToEndAsync()
  $errorTask=$process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Output=($outputTask.Result+"`r`n"+$errorTask.Result).Trim()}
 }finally{$process.Dispose()}
}
function Get-CheckedBcdText {
 $read=Invoke-BcdEdit -Arguments @('/enum','{current}')
 if($read.ExitCode -ne 0){throw "Lecture BCD impossible (code $($read.ExitCode)) : $($read.Output)"}
 [string]$read.Output
}
function Get-TimerBooleanChoice([string]$Name,[string]$YesLabel,[string]$NoLabel){
 $text=Get-CheckedBcdText
 $match=[regex]::Match($text,"(?im)^\s*$([regex]::Escape($Name))\s+(\S+)")
 if(-not $match.Success){return 'Défaut (supprimer le réglage)'}
 $value=$match.Groups[1].Value
 if($value -match '^(Yes|Oui|Ja|Si|True|1)$'){return $YesLabel}
 if($value -match '^(No|Non|Nein|False|0)$'){return $NoLabel}
 throw "Valeur BCD $Name non reconnue : $value"
}
function Set-CheckedTimerBoolean([string]$Name,[string]$Data){
 Set-BcdValue $Name $Data
 $actual=Get-TimerBooleanChoice $Name 'yes' 'no'
 $expected=if($Data -eq 'default'){'Défaut (supprimer le réglage)'}else{$Data}
 if($actual -ne $expected){throw "La valeur BCD $Name n’a pas été confirmée après modification."}
}
function Set-IndividualDynamicTick([string]$Data){
 # Same mutex as the competitive worker: do not overwrite a setting for which
 # Timers pour les jeux owns a pending restoration snapshot.
 $mutex=[Threading.Mutex]::new($false,'Global\BASTOS-CompetitiveTuning');$owned=$false
 try{
  try{$owned=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(-not $owned){throw 'Une autre modification de minuterie est en cours.'}
  $root=Join-Path $env:ProgramData 'BASTOS\CompetitiveTuning'
  if(Test-Path -LiteralPath $root){
   foreach($file in @(Get-ChildItem -LiteralPath $root -Filter 'frame-timers.json' -Recurse -File -ErrorAction Stop)){
    $saved=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if(@($saved.Items|Where-Object {$_.Key -eq 'BCD:disabledynamictick'}).Count){throw "Restaure d’abord « Timers pour les jeux » : cette option possède une sauvegarde du tick dynamique."}
   }
  }
  Set-CheckedTimerBoolean 'disabledynamictick' $Data
 }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Set-BcdValue {
 param(
  [ValidatePattern('^[A-Za-z][A-Za-z0-9]*$')][string]$Name,
  [ValidatePattern('^[A-Za-z][A-Za-z0-9]*$')][string]$Data
 )
 $script:BcdAlreadyDefault=$false
 $pattern="(?im)^\s*$([regex]::Escape($Name))\s+"
 if($Data -eq 'default'){
  # Une entree absente signifie deja le defaut. Une erreur de lecture ne
  # doit jamais etre assimilee a une absence (droits, magasin BCD, etc.).
  $before=Get-CheckedBcdText
  if($before -notmatch $pattern){$script:BcdAlreadyDefault=$true;return}
  $write=Invoke-BcdEdit -Arguments @('/deletevalue','{current}',$Name)
 }else{
  $write=Invoke-BcdEdit -Arguments @('/set','{current}',$Name,$Data)
 }
 if($write.ExitCode -ne 0){throw "BCD a retourne le code $($write.ExitCode) pour $Name : $($write.Output)"}
 if($Data -eq 'default'){
  $after=Get-CheckedBcdText
  if($after -match $pattern){throw "Le reglage BCD $Name est toujours present apres sa suppression."}
 }
}
function Get-NetClassKeys {Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue|Where-Object{$_.PSChildName -match '^\d{4}$'}}
function Get-DisplayKeys {Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue|Where-Object{$_.PSChildName -match '^\d{4}$'}}
function Get-BaselinePath([string]$Option){$root=Join-Path $env:ProgramData 'BASTOS\RiskyOptimizationBaselines';if(-not(Test-Path $root)){New-Item -ItemType Directory $root -Force|Out-Null};Join-Path $root ($Option+'.json')}
function Save-Baseline([string]$Option,[object]$Data){$path=Get-BaselinePath $Option;if(-not(Test-Path $path)){[IO.File]::WriteAllText($path,($Data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}}
function Read-Baseline([string]$Option){$path=Get-BaselinePath $Option;if(Test-Path $path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}else{$null}}
function Clear-Baseline([string]$Option){Remove-Item -LiteralPath (Get-BaselinePath $Option) -Force -ErrorAction SilentlyContinue}
function Get-RegValueSnapshot([string]$Path,[string]$Name){try{[pscustomobject]@{Path=$Path;Name=$Name;Exists=$true;Value=(Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop)}}catch{[pscustomobject]@{Path=$Path;Name=$Name;Exists=$false;Value=$null}}}
function Restore-RegValueSnapshot([object]$Snapshot){if([bool]$Snapshot.Exists){Set-Dword ([string]$Snapshot.Path) ([string]$Snapshot.Name) ([int]$Snapshot.Value)}else{Remove-Value ([string]$Snapshot.Path) ([string]$Snapshot.Name)}}
function Set-RiskMarker([string]$Name,[bool]$Enabled){$path='HKLM:\SOFTWARE\BASTOS\RiskyOptimizations';if($Enabled){Set-Dword $path $Name 1}else{Remove-Value $path $Name}}
function Get-RiskMarker([string]$Name){(Get-Dword 'HKLM:\SOFTWARE\BASTOS\RiskyOptimizations' $Name 0)-eq 1}
function Set-ServiceStartValue([string]$Name,[int]$Start){
 $mode=switch($Start){2{'auto'}3{'demand'}4{'disabled'}default{throw "Type de démarrage non pris en charge pour $Name : $Start"}}
 & sc.exe config $Name start= $mode 2>&1|Out-Null
 if($LASTEXITCODE -ne 0){throw "Le service $Name refuse le type de démarrage $mode (code SC $LASTEXITCODE)."}
 $actual=Get-Dword ("HKLM:\SYSTEM\CurrentControlSet\Services\$Name") 'Start' -1
 if($actual -ne $Start){throw "Le service $Name n a pas conservé le type de démarrage demandé."}
}

$mm='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$power='HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
$kernel='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
$memory='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$dwm='HKLM:\SOFTWARE\Microsoft\Windows\Dwm'
$priority='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
$graphics='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$deviceGuard='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$hvci=Join-Path $deviceGuard 'Scenarios\HypervisorEnforcedCodeIntegrity'
$ci='HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config'
$smartScreen='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$internetMachine='HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3'
$internetUser='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3'
$internetPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Security'
$result=[ordered]@{Success=$false;Message='';States=[ordered]@{};Choices=[ordered]@{};Quantum=38;UpdatedUtc=[datetime]::UtcNow.ToString('o')}
try{
 if($Action -eq 'Get'){
  $result.States.NoLazyMode=(Get-Dword $mm 'NoLazyMode' 0)-eq 1
  $result.States.DisablePowerThrottling=(Get-Dword $power 'PowerThrottlingOff' 0)-eq 1
  $result.States.ThreadDpc=(Get-Dword $kernel 'ThreadDpcEnable' 0)-eq 1
  $result.States.DisableInterruptSteering=(Get-Dword $kernel 'InterruptSteeringDisabled' 0)-eq 1
  $result.States.DisableMpo=(Get-Dword $dwm 'OverlayTestMode' 0)-eq 5
  $idle=(& powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 2>$null|Out-String);$result.States.CpuIdle=$idle -notmatch '(?im)Current AC Power Setting Index:\s+0x00000001'
  $netKeys=@(Get-NetClassKeys);$result.States.DisableNagle=[bool]($netKeys|Where-Object{(Get-Dword $_.PSPath 'TCPNoDelay' 0)-eq 1}|Select-Object -First 1)
  try{$result.States.DisablePageCombining=-not [bool](Get-MMAgent).PageCombining}catch{$result.States.DisablePageCombining=$false}
  $result.States.DisablePagingExecutive=(Get-Dword $memory 'DisablePagingExecutive' 0)-eq 1
  $result.States.ForceDirectFlip=(Get-Dword $dwm 'ForceDirectFlip' 0)-eq 1
  $result.States.ForceIndependentFlip=(Get-Dword $dwm 'ForceIndependentFlip' 0)-eq 1
  $result.States.ForceFlipTrueImmediate=(Get-Dword $dwm 'ForceFlipTrueImmediateMode' 0)-eq 1
  $result.States.NvidiaPState0=[bool](@(Get-DisplayKeys|Where-Object{(Get-Dword $_.PSPath 'DisableDynamicPstate' 0)-eq 1}).Count)
  $result.States.RiskDisableCoreSecurity=(Get-Dword $deviceGuard 'EnableVirtualizationBasedSecurity' 1)-eq 0 -and (Get-Dword $hvci 'Enabled' 1)-eq 0 -and (Get-Dword $ci 'VulnerableDriverBlocklistEnable' 1)-eq 0
  $result.States.RiskDisableSmartScreen=(Get-Dword $smartScreen 'EnableSmartScreen' 1)-eq 0
  $result.States.RiskDisableExploitProtection=Get-RiskMarker 'RiskDisableExploitProtection'
  $result.States.RiskLegacyBoot=Get-RiskMarker 'RiskLegacyBoot'
  $result.States.RiskUnsafeDownloads=(Get-Dword $internetUser '1806' 3)-eq 0 -and (Get-Dword $internetMachine '1806' 3)-eq 0
  $result.States.RiskDisableBackgroundMaintenance=Get-RiskMarker 'RiskDisableBackgroundMaintenance'
  $result.Choices.LazyModeTimeout=$(if((Get-ItemProperty $mm -Name LazyModeTimeout -ErrorAction SilentlyContinue)){"$(Get-Dword $mm 'LazyModeTimeout' 0) ms"}else{'Défaut (supprimer la valeur)'})
  $sysResp=Get-Dword $mm 'SystemResponsiveness' 20;$result.Choices.SystemResponsiveness=switch($sysResp){10{'Minimum (10)'}20{'Défaut (20)'}100{'Désactiver MMCSS (100)'}default{'Personnalisé (10 à 100)'}}
  $firstNet=$netKeys|Select-Object -First 1
  $result.Choices.ReceiveBuffers=$(if($firstNet -and (Get-ItemProperty $firstNet.PSPath -Name '*ReceiveBuffers' -ErrorAction SilentlyContinue)){"$(Get-Dword $firstNet.PSPath '*ReceiveBuffers' 0)"}else{'Défaut (supprimer la valeur)'})
  $result.Choices.TransmitBuffers=$(if($firstNet -and (Get-ItemProperty $firstNet.PSPath -Name '*TransmitBuffers' -ErrorAction SilentlyContinue)){"$(Get-Dword $firstNet.PSPath '*TransmitBuffers' 0)"}else{'Défaut (supprimer la valeur)'})
  $csrss='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions';$cpu=Get-Dword $csrss 'CpuPriorityClass' 2;$result.Choices.CsrssPriority=switch($cpu){4{'Temps réel'}3{'Haute'}6{'Supérieure à la normale'}5{'Inférieure à la normale'}default{'Normale'}}
  $ioLat=Get-Dword $memory 'IoLatencyCap' 80;$result.Choices.IoLatencyCap=switch($ioLat){0{'Désactivé (0)'}20{'20'}25{'25'}50{'50'}80{'Défaut (0x50 = 80)'}500{'500'}default{'Personnalisé (entier)'}}
  $result.Choices.IoPageLockLimit=$(if((Get-ItemProperty $memory -Name IoPageLockLimit -ErrorAction SilentlyContinue)){"$((Get-Dword $memory 'IoPageLockLimit' 0)/1MB) Mo (0x$((Get-Dword $memory 'IoPageLockLimit' 0).ToString('X8')))"}else{'Défaut (supprimer la valeur)'})
  $result.Choices.TscSyncPolicy=$(if(-not(Has-BcdValue 'tscsyncpolicy')){'Défaut Windows (supprimer le réglage)'}else{switch((Get-BcdValue 'tscsyncpolicy' 'Default').ToLowerInvariant()){'legacy'{'Héritée'}'enhanced'{'Améliorée'}default{'Défaut Windows (supprimer le réglage)'}}})
  $result.Choices.UsePlatformTick=$(if(-not(Has-BcdValue 'useplatformtick')){'Défaut (supprimer le réglage)'}elseif((Get-BcdValue 'useplatformtick' 'no') -match 'yes|true'){'Activée (RTC)'}else{'Désactivée (TSC)'})
  $result.Choices.DisableDynamicTick=Get-TimerBooleanChoice 'disabledynamictick' 'Désactivé (Yes)' 'Activé (No)'
  $result.Choices.UsePlatformClock=Get-TimerBooleanChoice 'useplatformclock' 'Forcer (Yes)' 'Ne pas forcer (No)'
  $qpl=Get-Dword $graphics 'QueuedPresentLimit' 3;$result.Choices.QueuedPresentLimit=$(if($qpl -eq 3){'Défaut (3)'}else{"$qpl"})
  $result.Quantum=Get-Dword $priority 'Win32PrioritySeparation' 38
  $result.Success=$true;$result.Message='État des réglages avancés actualisé.'
 }elseif($Action -in @('Enable','Disable')){
  $on=$Action -eq 'Enable'
  switch($Option){
   'NoLazyMode'{if($on){Set-Dword $mm 'NoLazyMode' 1}else{Remove-Value $mm 'NoLazyMode'}}
   'DisablePowerThrottling'{if($on){Set-Dword $power 'PowerThrottlingOff' 1}else{Remove-Value $power 'PowerThrottlingOff'}}
   'ThreadDpc'{if($on){Set-Dword $kernel 'ThreadDpcEnable' 1}else{Remove-Value $kernel 'ThreadDpcEnable'}}
   'DisableInterruptSteering'{if($on){Set-Dword $kernel 'InterruptSteeringDisabled' 1}else{Remove-Value $kernel 'InterruptSteeringDisabled'}}
   'DisableMpo'{if($on){Set-Dword $dwm 'OverlayTestMode' 5}else{Remove-Value $dwm 'OverlayTestMode'}}
   'CpuIdle'{$value=if($on){0}else{1};& powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE $value|Out-Null;& powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE $value|Out-Null;& powercfg.exe /setactive SCHEME_CURRENT|Out-Null}
   'DisableNagle'{foreach($key in Get-NetClassKeys){if($on){Set-Dword $key.PSPath 'TcpAckFrequency' 1;Set-Dword $key.PSPath 'TCPNoDelay' 1;Set-Dword $key.PSPath 'TcpDelAckTicks' 0}else{Remove-Value $key.PSPath 'TcpAckFrequency';Remove-Value $key.PSPath 'TCPNoDelay';Remove-Value $key.PSPath 'TcpDelAckTicks'}}}
   'DisablePageCombining'{if($on){Disable-MMAgent -PageCombining}else{Enable-MMAgent -PageCombining}}
   'DisablePagingExecutive'{if($on){Set-Dword $memory 'DisablePagingExecutive' 1}else{Remove-Value $memory 'DisablePagingExecutive'}}
   'ForceDirectFlip'{if($on){Set-Dword $dwm 'ForceDirectFlip' 1}else{Remove-Value $dwm 'ForceDirectFlip'}}
   'ForceIndependentFlip'{if($on){Set-Dword $dwm 'ForceIndependentFlip' 1}else{Remove-Value $dwm 'ForceIndependentFlip'}}
   'ForceFlipTrueImmediate'{if($on){Set-Dword $dwm 'ForceFlipTrueImmediateMode' 1}else{Remove-Value $dwm 'ForceFlipTrueImmediateMode'}}
   'NvidiaPState0'{foreach($key in Get-DisplayKeys){$desc=[string](Get-ItemPropertyValue $key.PSPath -Name DriverDesc -ErrorAction SilentlyContinue);if($desc -match 'NVIDIA'){if($on){Set-Dword $key.PSPath 'DisableDynamicPstate' 1}else{Remove-Value $key.PSPath 'DisableDynamicPstate'}}}}
   'RiskDisableCoreSecurity'{
      $snapshots=@(Get-RegValueSnapshot $deviceGuard 'EnableVirtualizationBasedSecurity';Get-RegValueSnapshot $hvci 'Enabled';Get-RegValueSnapshot $ci 'VulnerableDriverBlocklistEnable';Get-RegValueSnapshot $ci 'VerifiedAndReputablePolicyState')
      if($on){Save-Baseline $Option ([ordered]@{Registry=$snapshots;HypervisorPresent=(Has-BcdValue 'hypervisorlaunchtype');Hypervisor=(Get-BcdValue 'hypervisorlaunchtype' 'auto')});Set-Dword $deviceGuard 'EnableVirtualizationBasedSecurity' 0;Set-Dword $hvci 'Enabled' 0;Set-Dword $ci 'VulnerableDriverBlocklistEnable' 0;Set-Dword $ci 'VerifiedAndReputablePolicyState' 0;Set-BcdValue 'hypervisorlaunchtype' 'off'}else{$baseline=Read-Baseline $Option;if($baseline){foreach($snapshot in @($baseline.Registry)){Restore-RegValueSnapshot $snapshot};if([bool]$baseline.HypervisorPresent){Set-BcdValue 'hypervisorlaunchtype' ([string]$baseline.Hypervisor)}else{Set-BcdValue 'hypervisorlaunchtype' 'default'};Clear-Baseline $Option}else{Set-Dword $deviceGuard 'EnableVirtualizationBasedSecurity' 1;Set-Dword $hvci 'Enabled' 1;Set-Dword $ci 'VulnerableDriverBlocklistEnable' 1;Set-BcdValue 'hypervisorlaunchtype' 'auto'}}
   }
   'RiskDisableSmartScreen'{
      if($on){Save-Baseline $Option ([ordered]@{Registry=@(Get-RegValueSnapshot $smartScreen 'EnableSmartScreen')});Set-Dword $smartScreen 'EnableSmartScreen' 0}else{$baseline=Read-Baseline $Option;if($baseline){foreach($snapshot in @($baseline.Registry)){Restore-RegValueSnapshot $snapshot};Clear-Baseline $Option}else{Remove-Value $smartScreen 'EnableSmartScreen'}}
   }
   'RiskDisableExploitProtection'{
      $baselinePath=Get-BaselinePath $Option
      if($on){if(-not(Test-Path $baselinePath)){Get-ProcessMitigation -RegistryConfigFilePath $baselinePath};Set-ProcessMitigation -System -Disable DEP,SEHOP,ForceRelocateImages,BottomUp,HighEntropy,StrictHandle,DisableWin32kSystemCalls,DisableFsctlSystemCalls,DisableExtensionPoints,BlockDynamicCode,CFG,StrictCFG,MicrosoftSignedOnly,AllowStoreSignedBinaries,EnforceModuleDependencySigning,DisableNonSystemFonts,BlockRemoteImageLoads,BlockLowLabelImageLoads,PreferSystem32,TerminateOnError,UserShadowStack,UserShadowStackStrictMode;Set-RiskMarker $Option $true}else{if(Test-Path $baselinePath){Set-ProcessMitigation -PolicyFilePath $baselinePath;Clear-Baseline $Option}else{Set-ProcessMitigation -System -Reset};Set-RiskMarker $Option $false}
   }
   'RiskLegacyBoot'{
      $names=@('useplatformtick','disabledynamictick','bootmenupolicy','quietboot')
      if($on){$values=@();foreach($name in $names){$values+=[pscustomobject]@{Name=$name;Exists=(Has-BcdValue $name);Value=(Get-BcdValue $name '')}};Save-Baseline $Option ([ordered]@{Values=$values});Set-BcdValue 'useplatformtick' 'no';Set-BcdValue 'disabledynamictick' 'yes';Set-BcdValue 'bootmenupolicy' 'Legacy';Set-BcdValue 'quietboot' 'on';Set-RiskMarker $Option $true}else{$baseline=Read-Baseline $Option;if($baseline){foreach($item in @($baseline.Values)){if([bool]$item.Exists){Set-BcdValue ([string]$item.Name) ([string]$item.Value)}else{Set-BcdValue ([string]$item.Name) 'default'}};Clear-Baseline $Option}else{foreach($name in $names){Set-BcdValue $name 'default'}};Set-RiskMarker $Option $false}
   }
   'RiskUnsafeDownloads'{
      $snapshots=@(Get-RegValueSnapshot $internetUser '1806';Get-RegValueSnapshot $internetMachine '1806';Get-RegValueSnapshot $internetPolicy 'DisableSecuritySettingsCheck')
      if($on){Save-Baseline $Option ([ordered]@{Registry=$snapshots});Set-Dword $internetUser '1806' 0;Set-Dword $internetMachine '1806' 0;Set-Dword $internetPolicy 'DisableSecuritySettingsCheck' 1}else{$baseline=Read-Baseline $Option;if($baseline){foreach($snapshot in @($baseline.Registry)){Restore-RegValueSnapshot $snapshot};Clear-Baseline $Option}else{Remove-Value $internetUser '1806';Remove-Value $internetMachine '1806';Remove-Value $internetPolicy 'DisableSecuritySettingsCheck'}}
   }
   'RiskDisableBackgroundMaintenance'{
      $services=@('SysMain','WSearch','Spooler','bthserv','BTAGService','WerSvc','WdiServiceHost','DiagTrack','WpnService','vmcompute')
      $tasks=@('\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem','\Microsoft\Windows\Windows Error Reporting\QueueReporting','\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\StartupAppTask','\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector','\Microsoft\Windows\Defrag\ScheduledDefrag','\Microsoft\Windows\DiskFootprint\StorageSense','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip')
      if($on){
       $serviceValues=@();foreach($name in $services){$path="HKLM:\SYSTEM\CurrentControlSet\Services\$name";if(Test-Path $path){$snapshot=Get-RegValueSnapshot $path 'Start';$serviceValues+=[pscustomobject]@{Service=$name;Path=$snapshot.Path;Name=$snapshot.Name;Exists=$snapshot.Exists;Value=$snapshot.Value}}}
       $taskValues=@();foreach($taskName in $tasks){$leaf=Split-Path $taskName -Leaf;$taskPath=($taskName.Substring(0,$taskName.Length-$leaf.Length));$task=Get-ScheduledTask -TaskName $leaf -TaskPath $taskPath -ErrorAction SilentlyContinue;if($task){$taskValues+=[pscustomobject]@{Name=$leaf;Path=$taskPath;Enabled=([string]$task.State -ne 'Disabled')}}}
       Save-Baseline $Option ([ordered]@{Services=$serviceValues;Tasks=$taskValues})
       try{
        foreach($snapshot in $serviceValues){Set-ServiceStartValue ([string]$snapshot.Service) 4}
        foreach($task in $taskValues){Disable-ScheduledTask -TaskName ([string]$task.Name) -TaskPath ([string]$task.Path) -ErrorAction Stop|Out-Null}
        Set-RiskMarker $Option $true
       }catch{
        $applyError=$_.Exception.Message
        foreach($snapshot in $serviceValues){if([bool]$snapshot.Exists){try{Set-ServiceStartValue ([string]$snapshot.Service) ([int]$snapshot.Value)}catch{}}}
        foreach($task in $taskValues){try{if([bool]$task.Enabled){Enable-ScheduledTask -TaskName ([string]$task.Name) -TaskPath ([string]$task.Path) -ErrorAction Stop|Out-Null}else{Disable-ScheduledTask -TaskName ([string]$task.Name) -TaskPath ([string]$task.Path) -ErrorAction Stop|Out-Null}}catch{}}
        Clear-Baseline $Option
        throw "Application annulée et état précédent restauré : $applyError"
       }
      }else{
       $baseline=Read-Baseline $Option
       if($baseline){foreach($snapshot in @($baseline.Services)){if([bool]$snapshot.Exists){Set-ServiceStartValue ([string]$snapshot.Service) ([int]$snapshot.Value)}};foreach($task in @($baseline.Tasks)){if([bool]$task.Enabled){Enable-ScheduledTask -TaskName ([string]$task.Name) -TaskPath ([string]$task.Path) -ErrorAction Stop|Out-Null}else{Disable-ScheduledTask -TaskName ([string]$task.Name) -TaskPath ([string]$task.Path) -ErrorAction Stop|Out-Null}};Clear-Baseline $Option}
       Set-RiskMarker $Option $false
      }
   }
   default{throw "Réglage inconnu : $Option"}
  }
  $result.Success=$true;$result.Message=if($on){'Réglage activé. Un redémarrage peut être nécessaire.'}else{'Réglage restauré sur le comportement Windows. Un redémarrage peut être nécessaire.'}
 }elseif($Action -eq 'RestoreQuantum'){
  Set-Dword $priority 'Win32PrioritySeparation' 38;$result.Quantum=38;$result.Success=$true;$result.Message='Planificateur restauré sur le défaut Windows 0x26.'
 }else{
  switch($Option){
   'LazyModeTimeout'{if($Value -match 'supprimer'){Remove-Value $mm 'LazyModeTimeout'}else{Set-Dword $mm 'LazyModeTimeout' ([int]($Value -replace '\D',''))}}
   'SystemResponsiveness'{$data=if($Value -match '^\d+$'){[int]$Value}elseif($Value -match '100'){100}elseif($Value -match '10'){10}else{20};Set-Dword $mm 'SystemResponsiveness' $data}
   'ReceiveBuffers'{foreach($key in Get-NetClassKeys){if($Value -match 'supprimer'){Remove-Value $key.PSPath '*ReceiveBuffers'}else{Set-Dword $key.PSPath '*ReceiveBuffers' ([int]$Value)}}}
   'TransmitBuffers'{foreach($key in Get-NetClassKeys){if($Value -match 'supprimer'){Remove-Value $key.PSPath '*TransmitBuffers'}else{Set-Dword $key.PSPath '*TransmitBuffers' ([int]$Value)}}}
   'CsrssPriority'{$csrss='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions';$data=if($Value -match 'Temps réel'){4}elseif($Value -eq 'Haute'){3}elseif($Value -match 'Supérieure'){6}elseif($Value -match 'Inférieure'){5}else{2};Set-Dword $csrss 'CpuPriorityClass' $data}
   'IoLatencyCap'{$data=if($Value -match '^\d+$'){[int]$Value}elseif($Value -match 'Désactivé'){0}else{80};Set-Dword $memory 'IoLatencyCap' $data}
   'IoPageLockLimit'{if($Value -match 'supprimer'){Remove-Value $memory 'IoPageLockLimit'}elseif($Value -match 'Maximum'){$total=[int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory;$bytes=[Math]::Min([int64]0xFFFFFFFF,[Math]::Floor($total/8));Set-Dword $memory 'IoPageLockLimit' ([uint32]$bytes)}else{$mb=[int]([regex]::Match($Value,'^\d+').Value);Set-Dword $memory 'IoPageLockLimit' ($mb*1MB)}}
   'TscSyncPolicy'{if($Value -match 'supprimer|Défaut Windows'){Set-BcdValue 'tscsyncpolicy' 'default'}elseif($Value -match 'Héritée'){Set-BcdValue 'tscsyncpolicy' 'Legacy'}else{Set-BcdValue 'tscsyncpolicy' 'Enhanced'}}
   'UsePlatformTick'{if($Value -match 'supprimer'){Set-BcdValue 'useplatformtick' 'default'}elseif($Value -match 'Activée'){Set-BcdValue 'useplatformtick' 'yes'}else{Set-BcdValue 'useplatformtick' 'no'}}
   'DisableDynamicTick'{switch -Exact ($Value){'Défaut (supprimer le réglage)'{Set-IndividualDynamicTick 'default'}'Désactivé (Yes)'{Set-IndividualDynamicTick 'yes'}'Activé (No)'{Set-IndividualDynamicTick 'no'}default{throw 'Choix du tick dynamique invalide.'}}}
   'UsePlatformClock'{switch -Exact ($Value){'Défaut (supprimer le réglage)'{Set-CheckedTimerBoolean 'useplatformclock' 'default'}'Ne pas forcer (No)'{Set-CheckedTimerBoolean 'useplatformclock' 'no'}'Forcer (Yes)'{Set-CheckedTimerBoolean 'useplatformclock' 'yes'}default{throw "Choix de l’horloge de plateforme invalide."}}}
   'QueuedPresentLimit'{if($Value -match 'Défaut'){Remove-Value $graphics 'QueuedPresentLimit'}else{Set-Dword $graphics 'QueuedPresentLimit' ([int]$Value)}}
   'Quantum'{$q=[int]$Value;if($q -lt 16 -or $q -gt 63){throw 'Valeur Quantum hors limites.'};Set-Dword $priority 'Win32PrioritySeparation' $q;$result.Quantum=$q}
   default{throw "Réglage inconnu : $Option"}
  }
  $result.Success=$true
  if($script:BcdAlreadyDefault){
   $result.Message="D$([char]0x00E9)j$([char]0x00E0) au r$([char]0x00E9)glage par d$([char]0x00E9)faut. Aucune modification n$([char]0x00E9)cessaire."
  }else{$result.Message='Réglage appliqué. Un redémarrage peut être nécessaire.'}
 }
}catch{$result.Message=$_.Exception.Message}
finally{$parent=Split-Path -Parent ([IO.Path]::GetFullPath($ResultPath));if(-not(Test-Path $parent)){New-Item -ItemType Directory $parent -Force|Out-Null};[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
if($result.Success){exit 0}else{exit 1}
