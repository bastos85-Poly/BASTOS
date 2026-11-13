param([string]$Folder='C:\BastosCompetitiveTest')
$ErrorActionPreference='Stop'
$worker=Join-Path $Folder 'Manage-BASTOS-Extras.ps1'
$results=[Collections.Generic.List[object]]::new()
function Check($condition,$name){$results.Add([pscustomobject]@{Test=$name;Passed=[bool]$condition});if(-not $condition){throw $name}}
function Run($option,$action,$target='',[int]$ac=0,[int]$dc=0){
 $file=Join-Path $Folder ('Extras-'+[guid]::NewGuid().ToString('N')+'.json')
 $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$worker,'-Option',$option,'-Action',$action,'-ResultPath',$file)
 if($target){$args+=@('-Target',$target)}
 if($option -eq 'power' -and $action -eq 'Apply'){$args+=@('-AcValue',[string]$ac,'-DcValue',[string]$dc)}
 & powershell.exe @args|Out-Null
 Get-Content $file -Raw|ConvertFrom-Json
}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$state=Join-Path $env:ProgramData ('BASTOS\Extras\'+$sid)
try{
 Check (-not(Test-Path $state)) 'Extras initial read starts without restoration state'
 foreach($id in @('apps','usb','mtu','power')){$r=Run $id Get;Check $r.Success ($id+': native read completes without applying settings')}
 Check (-not(Test-Path $state)) 'Native reads do not create restoration state'
 $exe=Join-Path $Folder 'fixture-browser.exe';[IO.File]::WriteAllText($exe,'fixture; never executed')
 foreach($app in @(@{Id='chrome';Exe='chrome.exe';Path='HKCU:\Software\Policies\Google\Chrome';Value='HardwareAccelerationModeEnabled'},@{Id='firefox';Exe='firefox.exe';Path='HKCU:\Software\Policies\Mozilla\Firefox';Value='HardwareAcceleration'})){
  $ap='HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\'+$app.Exe
  Check (-not(Test-Path $ap)) ($app.Id+': fixture does not overwrite installed browser registration')
  New-Item $ap -Force|Out-Null;Set-Item $ap -Value $exe
  New-Item $app.Path -Force|Out-Null;New-ItemProperty $app.Path $app.Value -PropertyType DWord -Value 1 -Force|Out-Null
  $r=Run $app.Id Apply;Check ($r.Success -and (Get-ItemPropertyValue $app.Path $app.Value) -eq 0) ($app.Id+': GPU policy applied and read back')
  $r=Run $app.Id Apply
  $r=Run $app.Id Restore;Check ($r.Success -and (Get-ItemPropertyValue $app.Path $app.Value) -eq 1) ($app.Id+': original policy survives repeated apply and restores')
  Remove-ItemProperty $app.Path $app.Value
  $r=Run $app.Id Apply;$r=Run $app.Id Restore
  Check ($r.Success -and (Get-Item $app.Path).GetValueNames() -notcontains $app.Value) ($app.Id+': absent original policy restored by removal')
  $r=Run $app.Id Apply;New-ItemProperty $app.Path $app.Value -PropertyType DWord -Value 2 -Force|Out-Null
  $r=Run $app.Id Restore;Check ($r.Success -and (Get-ItemPropertyValue $app.Path $app.Value) -eq 2) ($app.Id+': restoration preserves an external modification')
  Remove-ItemProperty $app.Path $app.Value
  $machinePath=$app.Path.Replace('HKCU:','HKLM:');New-Item $machinePath -Force|Out-Null
  Check ((Get-Item $machinePath).GetValueNames() -notcontains $app.Value) ($app.Id+': fixture does not replace a machine policy')
  New-ItemProperty $machinePath $app.Value -PropertyType DWord -Value 1 -Force|Out-Null
  $r=Run $app.Id Apply
  Check (-not $r.Success -and (Get-Item $app.Path).GetValueNames() -notcontains $app.Value) ($app.Id+': conflicting machine policy blocks false success and user writes')
  Remove-ItemProperty $machinePath $app.Value;Remove-Item -LiteralPath $ap
 }
 $discord=Join-Path $env:APPDATA 'discord\settings.json';Check (-not(Test-Path $discord)) 'Discord fixture does not overwrite real preferences'
 New-Item -ItemType Directory -Path (Split-Path $discord) -Force|Out-Null
 [IO.File]::WriteAllText($discord,'{"enableHardwareAcceleration":true,"theme":"dark","nested":{"keep":7}}')
 $r=Run discord Apply;$d=Get-Content $discord -Raw|ConvertFrom-Json
 Check ($r.Success -and -not $d.enableHardwareAcceleration -and $d.theme -eq 'dark' -and $d.nested.keep -eq 7) 'Discord changes only acceleration while preserving nested preferences'
 $r=Run discord Get;Check ($r.Success -and $r.Items[0].Applied) 'Discord preference persists across independent worker processes'
 $r=Run discord Apply
 $d=Get-Content $discord -Raw|ConvertFrom-Json;$d|Add-Member -NotePropertyName externalField -NotePropertyValue 'keep';$d|ConvertTo-Json -Depth 10|Set-Content $discord -Encoding UTF8
 $r=Run discord Restore;$d=Get-Content $discord -Raw|ConvertFrom-Json
 Check ($r.Success -and $d.enableHardwareAcceleration -and $d.externalField -eq 'keep') 'Discord original flag restores without losing subsequent unrelated edits'
 [IO.File]::WriteAllText($discord,'{"theme":"light"}')
 $r=Run discord Apply;$r=Run discord Restore;$d=Get-Content $discord -Raw|ConvertFrom-Json
 Check ($r.Success -and -not $d.PSObject.Properties['enableHardwareAcceleration'] -and $d.theme -eq 'light') 'Discord missing original flag restores by removing only that field'
 [IO.File]::WriteAllText($discord,'invalid-json')
 $r=Run apps Get
 Check ($r.Success -and @($r.Items).Count -eq 3 -and -not ($r.Items|Where-Object Id -eq discord).Installed) 'Invalid Discord JSON does not prevent reading other applications'
 $r=Run discord Apply;Check (-not $r.Success -and (Get-Content $discord -Raw) -eq 'invalid-json') 'Invalid Discord JSON is preserved and never overwritten'
 Remove-Item -LiteralPath $discord
 $r=Run power Get;$min=@($r.Items|Where-Object {$_.Id.EndsWith(':cpu-min')})[0];$max=@($r.Items|Where-Object {$_.Id.EndsWith(':cpu-max')})[0]
 $r=Run power Apply $min.Id 0 0;Check $r.Success 'Active plan CPU minimum applies and reads back for AC and DC'
 $r=Run power Apply $max.Id 90 90;Check $r.Success 'Active plan CPU maximum applies and reads back for AC and DC'
 $r=Run power Apply $min.Id 95 95;Check (-not $r.Success) 'Power bounds reject minimum greater than maximum'
 $r=Run power Restore $max.Id;Check $r.Success 'CPU maximum exact previous settings restore'
 $r=Run power Restore $min.Id;Check $r.Success 'CPU minimum exact previous settings restore'
 $r=Run power Get
 Check (($r.Items|Where-Object Id -eq $min.Id).Ac -eq $min.Ac -and ($r.Items|Where-Object Id -eq $max.Id).Dc -eq $max.Dc) 'Restored plan values match original AC and DC readings'
 $r=Run usb Apply 'not-a-real-device';Check (-not $r.Success) 'USB worker refuses unsupported or missing device'
 $r=Run mtu Apply 'not-a-real-adapter';Check (-not $r.Success) 'MTU refuses applying without valid selection and measurement'
 # Load only function definitions, then stub hardware enumeration for deterministic failure paths.
 $ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$null,[ref]$null)
 foreach($f in @($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]})){. ([scriptblock]::Create($f.Extent.Text))}
 $stateRoot=$state
 function RouteCheck($address,$index){}
 $adapter=[pscustomobject]@{Id='controlled';Index=2;Current=1500}
 $Destination='127.0.0.1'
 function Probe($address,$size){if($size -le 1464){'Ok'}else{'TooBig'}}
 $m=MeasureMtu $adapter;Check ($m.Mtu -eq 1492) 'MTU search adds IPv4 ICMP overhead and finds a confirmed path limit'
 function Probe($address,$size){if($size -eq 548){'Ok'}else{'Unknown'}}
 $refused=$false;try{$null=MeasureMtu $adapter}catch{$refused=$true}
 Check $refused 'MTU timeout remains indeterminate instead of producing an apply target'
 $blocked=$false
 try{ValidateSavedTarget chrome ([pscustomobject]@{Type='Registry';Path='HKLM:\Software\NotAnAllowedTarget';Name='HardwareAccelerationModeEnabled'})}catch{$blocked=$true}
 Check $blocked 'Restoration rejects a journal pointing outside the selected feature'
 $usbSample=[pscustomobject]@{Type='Registry';Path='Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\VID_1234&PID_5678\1&2\Device Parameters\WDF';Name='IdleInWorkingState';Original=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}}
 ValidateSavedTarget 'usb:VID_1234&PID_5678\1&2' $usbSample
 Check $true 'Restoration accepts only the exact matching USB instance and property'
 $script:originalValidation=${function:ValidateSavedTarget}
 function ValidateSavedTarget($key,$t){if($key -notin @('usb-fixture','mtu-fixture')){& $script:originalValidation $key $t}}
 $usbPath='HKCU:\Software\BASTOS\ExtrasUsbFixture';New-Item $usbPath -Force|Out-Null;New-ItemProperty $usbPath IdleInWorkingState -PropertyType DWord -Value 1 -Force|Out-Null
 $t=RegTarget $usbPath IdleInWorkingState 0
 ApplyTargets 'usb-fixture' @($t);Check ((RegRead $usbPath IdleInWorkingState).Value -eq 0) 'Controlled USB target captures and applies the exposed registry value'
 $null=RestoreTargets 'usb-fixture';Check ((RegRead $usbPath IdleInWorkingState).Value -eq 1) 'Controlled USB target restores the exact original value'
 Remove-Item -LiteralPath $usbPath
 $mtuFixture=@{ActiveStore=1500;PersistentStore=1400}
 function Get-NetAdapter { [CmdletBinding()]param([switch]$IncludeHidden) [pscustomobject]@{InterfaceGuid='controlled-adapter';ifIndex=7} }
 function Get-NetIPInterface { [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore) [pscustomobject]@{NlMtu=$mtuFixture[$PolicyStore]} }
 function Set-NetIPInterface { [CmdletBinding(SupportsShouldProcess)]param($InterfaceIndex,$AddressFamily,$PolicyStore,$NlMtu) $mtuFixture[$PolicyStore]=[int]$NlMtu }
 $targets=@(foreach($store in @('PersistentStore','ActiveStore')){[pscustomobject]@{Key=('mtu:controlled:'+ $store);Type='Mtu';Path='controlled-adapter';Name=$store;Desired=1492}})
 ApplyTargets 'mtu-fixture' $targets
 Check ($mtuFixture.ActiveStore -eq 1492 -and $mtuFixture.PersistentStore -eq 1492) 'Controlled MTU applies active and persistent stores separately'
 $null=RestoreTargets 'mtu-fixture'
 Check ($mtuFixture.ActiveStore -eq 1500 -and $mtuFixture.PersistentStore -eq 1400) 'Controlled MTU restores distinct active and persistent original values'
 [pscustomobject]@{Success=$true;Tests=$results.ToArray()}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $Folder ExtrasTests.json) -Encoding UTF8
}catch{[pscustomobject]@{Success=$false;Error=$_.Exception.Message;Tests=$results.ToArray()}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $Folder ExtrasTests.json) -Encoding UTF8;throw}
