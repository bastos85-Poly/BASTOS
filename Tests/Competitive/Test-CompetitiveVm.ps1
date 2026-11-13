param([string]$Folder='C:\BastosCompetitiveTest')
$ErrorActionPreference='Stop'
$worker=Join-Path $Folder 'Manage-BASTOS-Competitive.ps1'
$results=[Collections.Generic.List[object]]::new()
function Check($condition,$name){$results.Add([pscustomobject]@{Test=$name;Passed=[bool]$condition});if(-not $condition){throw $name}}
function Invoke-Option($action,$id,[switch]$FakeAudio){
 $file=Join-Path $Folder ($id+'-'+$action+'-'+[guid]::NewGuid().ToString('N')+'.json')
 if($FakeAudio){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Folder 'Fake-AudioEntry.ps1') -Worker $worker -Action $action -ResultPath $file}
 else{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker -Action $action -Id $id -ResultPath $file}
 Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$state=Join-Path $env:ProgramData ('BASTOS\CompetitiveTuning\'+$sid)
try{
 $pending=@(Get-ChildItem -LiteralPath $state -Filter '*.json' -ErrorAction SilentlyContinue|ForEach-Object { (Get-Content $_.FullName -Raw|ConvertFrom-Json).Items })
 Check (-not $pending.Count) 'VM begins with no pending competitive tuning changes'
 $beforeRead=@(Get-ChildItem -LiteralPath $state -File -ErrorAction SilentlyContinue|Get-FileHash|ForEach-Object {$_.Path+$_.Hash}) -join '|'
 $read=Invoke-Option Get all
 Check (@($read.Results).Count -eq 7) 'All seven independent options have readable results'
 $afterRead=@(Get-ChildItem -LiteralPath $state -File -ErrorAction SilentlyContinue|Get-FileHash|ForEach-Object {$_.Path+$_.Hash}) -join '|'
 Check ($beforeRead -eq $afterRead) 'Reading options leaves restoration state unchanged'
 $paths=@{
  'udp-fastpath'=@('HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters','FastSendDatagramThreshold')
  'mouse-queue'=@('HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters','MouseDataQueueSize')
  'sdl3'=@('HKCU:\Environment','SDL_WINDOWS_RAW_KEYBOARD')
 }
 foreach($id in @('udp-fastpath','mouse-queue','sdl3','frame-timers')){
  $a=Invoke-Option Apply $id;Check $a.Success ($id+': apply verifies actual values')
  $journal=Get-Content (Join-Path $state ($id+'.json')) -Raw|ConvertFrom-Json
  Check (@($journal.Items).Count -gt 0) ($id+': originals durably recorded')
  $first=$journal|ConvertTo-Json -Depth 30 -Compress
  $again=Invoke-Option Apply $id
  $second=Get-Content (Join-Path $state ($id+'.json')) -Raw|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress
  Check ($again.Success -and $first -eq $second) ($id+': repeat apply preserves originals')
  $r=Invoke-Option Restore $id;Check $r.Success ($id+': restores and verifies originals')
  Check (@((Get-Content (Join-Path $state ($id+'.json')) -Raw|ConvertFrom-Json).Items).Count -eq 0) ($id+': no pending restoration remains')
 }
 $a=Invoke-Option Apply 'mouse-queue'
 New-ItemProperty -Path $paths['mouse-queue'][0] -Name MouseDataQueueSize -Value 444 -PropertyType DWord -Force|Out-Null
 $r=Invoke-Option Restore 'mouse-queue'
 Check ($r.Success -and (Get-ItemPropertyValue -Path $paths['mouse-queue'][0] -Name MouseDataQueueSize) -eq 444) 'Restoration preserves external changes'
 Remove-ItemProperty -Path $paths['mouse-queue'][0] -Name MouseDataQueueSize
 $driver='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}\0099'
 New-Item -Path ($driver+'\PowerSettings') -Force|Out-Null
 New-ItemProperty -Path ($driver+'\PowerSettings') -Name PerformanceIdleTime -Value ([byte[]](12,0,0,0)) -PropertyType Binary -Force|Out-Null
 $a=Invoke-Option Apply 'audio-power';Check $a.Success 'Audio codec idle settings applied and read back on a test driver'
 $r=Invoke-Option Restore 'audio-power'
 $back=Get-ItemPropertyValue -Path ($driver+'\PowerSettings') -Name PerformanceIdleTime
 Check ($r.Success -and ($back -join ',') -eq '12,0,0,0') 'Audio codec original binary values restored'
 $steam=Join-Path $Folder 'steam.exe';[IO.File]::WriteAllText($steam,'test-only; never executed')
 $steamPrefs='HKCU:\Software\Valve\Steam'
 New-Item $steamPrefs -Force|Out-Null
 New-ItemProperty $steamPrefs SteamExe -Value $steam -PropertyType String -Force|Out-Null
 New-ItemProperty $steamPrefs GPUAccelWebViewsV3 -Value 1 -PropertyType DWord -Force|Out-Null
 $run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
 $old=Get-ItemProperty -Path $run -Name Steam -ErrorAction SilentlyContinue
 Check ($null -eq $old) 'Steam fixture does not replace an installed client startup'
 New-Item -Path $run -Force|Out-Null
 New-ItemProperty -Path $run -Name Steam -Value ('"'+$steam+'" -silent -tenfoot') -PropertyType ExpandString -Force|Out-Null
 $shortcut=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Steam-Competitive-Test.lnk'
 $shell=New-Object -ComObject WScript.Shell;$lnk=$shell.CreateShortcut($shortcut);$lnk.TargetPath=$steam;$lnk.Arguments='-silent -tenfoot';$lnk.Save()
 $a=Invoke-Option Apply 'steam-gpu'
 Check ($a.Success -and (Get-ItemPropertyValue $run Steam) -match '-cef-disable-gpu') 'Steam acceleration argument added to existing startup only'
 Check ((Get-ItemPropertyValue $steamPrefs GPUAccelWebViewsV3) -eq 0) 'Steam preference disables GPU independently of launch arguments'
 $lnk=$shell.CreateShortcut($shortcut);Check ($lnk.Arguments -eq '-silent -tenfoot -cef-disable-gpu') 'Steam shortcut keeps its other arguments'
 $r=Invoke-Option Restore 'steam-gpu';$lnk=$shell.CreateShortcut($shortcut)
 Check ($r.Success -and $lnk.Arguments -eq '-silent -tenfoot' -and (Get-Item $run).GetValueKind('Steam').ToString() -eq 'ExpandString') 'Steam shortcut and original registry kind restored'
 Check ((Get-ItemPropertyValue $steamPrefs GPUAccelWebViewsV3) -eq 1) 'Steam previous permanent preference restored'
 Remove-ItemProperty -Path $steamPrefs -Name GPUAccelWebViewsV3
 $a=Invoke-Option Apply 'steam-gpu'
 $first=Get-Content (Join-Path $state 'steam-gpu.json') -Raw|ConvertFrom-Json
 $a=Invoke-Option Apply 'steam-gpu'
 $again=Get-Content (Join-Path $state 'steam-gpu.json') -Raw|ConvertFrom-Json
 Check ($a.Success -and -not ($again.Items|Where-Object Name -eq GPUAccelWebViewsV3).Original.Exists) 'Steam absent preference is saved once across repeated applications'
 $r=Invoke-Option Restore 'steam-gpu'
 Check ($r.Success -and (Get-Item $steamPrefs).GetValueNames() -notcontains 'GPUAccelWebViewsV3') 'Steam absent original preference restored by removal'
 Remove-ItemProperty -Path $steamPrefs -Name SteamExe
 Remove-Item -LiteralPath $shortcut;Remove-ItemProperty -Path $run -Name Steam
 $native=Invoke-Option Get 'audio-game'
 Check ($null -ne $native.Results) 'Native audio adapter handles VM absence without claiming success'
 foreach($name in @('Format','Effects','Spatial','Period')){$file=Join-Path $Folder ('AudioFixture\'+$name);if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
 $a=Invoke-Option Apply 'audio-game' -FakeAudio
 Check $a.Success 'Controlled audio endpoint: 48 kHz effects and spatial applied without forcing period'
 $journalPath=Join-Path $state 'audio-game.json'
 $journal=Get-Content $journalPath -Raw|ConvertFrom-Json
 $originalFormat=($journal.Items|Where-Object Name -eq Format).Original
 ($journal.Items|Where-Object Name -eq Format).Desired='obsolete-unsupported-format'
 $journal|ConvertTo-Json -Depth 30|Set-Content $journalPath -Encoding UTF8
 # The previous release saved a desired format which failed to apply.
 [IO.File]::WriteAllText((Join-Path $Folder 'AudioFixture\Format'),$originalFormat)
 $a=Invoke-Option Apply 'audio-game' -FakeAudio
 $journal=Get-Content $journalPath -Raw|ConvertFrom-Json
 Check ($a.Success -and ($journal.Items|Where-Object Name -eq Format).Original -eq $originalFormat -and ($journal.Items|Where-Object Name -eq Format).Desired -ne 'obsolete-unsupported-format') 'Audio upgrade migrates failed target while preserving original values'
 $r=Invoke-Option Restore 'audio-game' -FakeAudio
 Check $r.Success 'Controlled audio endpoint: exact format effects and spatial restored'
 [pscustomobject]@{Success=$true;Tests=@($results.ToArray())}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $Folder 'Tests.json') -Encoding UTF8
}catch{
 [pscustomobject]@{Success=$false;Error=$_.Exception.Message;Tests=@($results.ToArray())}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $Folder 'Tests.json') -Encoding UTF8
 throw
}

