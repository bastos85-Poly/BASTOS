[CmdletBinding()]
param(
    [ValidateSet('Status','Inventory','CreateRestorePoint','RemoveDisplayDriver','OpenDdu','OpenOfficialDriver','ApplySafeSettings','OpenDisplaySettings','StartVendorCleanup','ContinueOfficialDriver','OpenSlimmer','PreviewImport','ApplyImport','RestoreImport','VerifyImport')]
    [string]$Action = 'Status',
    [ValidateSet('Auto','AMD','NVIDIA','Intel')]
    [string]$Vendor = 'Auto',
    [string]$ResultPath,
    [switch]$ConfirmGpuOnly,
    [string]$ExpectedUserSid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logPath = Join-Path $env:LOCALAPPDATA 'BASTOS\Logs\Graphics-Optimizations.log'
$backupRoot = Join-Path $root 'Backups\Graphics'
$workflowPath = Join-Path $env:LOCALAPPDATA 'BASTOS\Graphics-Workflow.json'

function Write-BastosGraphicsLog {
    param([string]$Message,[string]$Level='INFO')
    New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
    $line=('{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message,[Environment]::NewLine)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($line)
    for($attempt=1;$attempt -le 25;$attempt++){
        $stream=$null
        try{
            $stream=[IO.File]::Open($logPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            [void]$stream.Seek(0,[IO.SeekOrigin]::End)
            $stream.Write($bytes,0,$bytes.Length)
            return
        }catch{
            if($attempt -eq 25){throw}
            Start-Sleep -Milliseconds 20
        }finally{
            if($stream){$stream.Dispose()}
        }
    }
}

function Write-BastosGraphicsResult {
    param($Value)
    $json = $Value | ConvertTo-Json -Depth 8
    if ($ResultPath) {
        New-Item -ItemType Directory -Path (Split-Path $ResultPath) -Force | Out-Null
        [IO.File]::WriteAllText($ResultPath,$json,[Text.UTF8Encoding]::new($false))
    } else { Write-Output $json }
}

function Test-BastosAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BastosVendorFromDeviceId {
    param([string]$DeviceId,[string]$Name='')
    if ($DeviceId -match '(?i)VEN_1002' -or $Name -match '(?i)AMD|Radeon') { return 'AMD' }
    if ($DeviceId -match '(?i)VEN_10DE' -or $Name -match '(?i)NVIDIA|GeForce|Quadro') { return 'NVIDIA' }
    if ($DeviceId -match '(?i)VEN_8086' -or $Name -match '(?i)Intel.*(Arc|Graphics|Iris|UHD|HD)') { return 'Intel' }
    return 'Other'
}

function Get-BastosDisplayDrivers {
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object {
        [string]$_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID
    } | ForEach-Object {
        [pscustomobject]@{
            Vendor = Get-BastosVendorFromDeviceId -DeviceId ([string]$_.DeviceID) -Name ([string]$_.DeviceName)
            Name = [string]$_.DeviceName
            DeviceId = [string]$_.DeviceID
            DriverVersion = [string]$_.DriverVersion
            DriverDate = $_.DriverDate
            PublishedName = [string]$_.InfName
            Manufacturer = [string]$_.Manufacturer
            DeviceClass = [string]$_.DeviceClass
        }
    })
    return @($drivers | Where-Object { $_.Vendor -in @('AMD','NVIDIA','Intel') })
}

function Get-BastosAudioSnapshot {
    return @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object {
        [string]$_.DeviceClass -in @('MEDIA','AudioEndpoint') -and $_.DeviceID
    } | ForEach-Object {
        [pscustomobject]@{ DeviceId=[string]$_.DeviceID; Name=[string]$_.DeviceName; DriverVersion=[string]$_.DriverVersion; InfName=[string]$_.InfName; DeviceClass=[string]$_.DeviceClass }
    } | Sort-Object DeviceId -Unique)
}

function Resolve-BastosVendor {
    param([string]$Requested,[array]$Drivers)
    if ($Requested -ne 'Auto') { return $Requested }
    $vendors = @($Drivers.Vendor | Sort-Object -Unique)
    if ($vendors.Count -eq 1) { return [string]$vendors[0] }
    if ($vendors.Count -eq 0) { throw "Aucun pilote graphique AMD, NVIDIA ou Intel n est détecté." }
    throw "Plusieurs constructeurs graphiques sont détectés ($($vendors -join ', ')). Choisis explicitement le constructeur."
}

function New-BastosGraphicsBackup {
    param([array]$DisplayDrivers,[array]$AudioDevices,[string]$SelectedVendor)
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $path = Join-Path $backupRoot ('Graphics-{0}-{1}.json' -f $SelectedVendor,(Get-Date -Format 'yyyyMMdd-HHmmss'))
    $data = [ordered]@{ CreatedUtc=[DateTime]::UtcNow.ToString('o'); Vendor=$SelectedVendor; DisplayDrivers=$DisplayDrivers; AudioDevices=$AudioDevices }
    [IO.File]::WriteAllText($path,($data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    return $path
}

function Get-BastosBootId {
    return ([datetime](Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToUniversalTime().ToString('o')
}

function Get-BastosGraphicsWorkflow {
    if (-not (Test-Path -LiteralPath $workflowPath)) { return $null }
    try {
        $state = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.Stage -eq 'CleanupStarted' -and [string]$state.BootId -ne (Get-BastosBootId)) {
            $state.Stage = 'ReadyForDriver'
            [IO.File]::WriteAllText($workflowPath,($state|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        }
        return $state
    } catch { return $null }
}

function Set-BastosGraphicsWorkflow {
    param([string]$SelectedVendor,[string]$Stage)
    New-Item -ItemType Directory -Path (Split-Path $workflowPath) -Force | Out-Null
    $state = [ordered]@{ Vendor=$SelectedVendor; Stage=$Stage; BootId=(Get-BastosBootId); UpdatedUtc=[DateTime]::UtcNow.ToString('o') }
    [IO.File]::WriteAllText($workflowPath,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    return $state
}

function New-BastosRestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description ('BASTOS - pilote graphique - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return $true
    } catch { Write-BastosGraphicsLog "Point de restauration indisponible : $($_.Exception.Message)" 'WARN'; return $false }
}

function Remove-BastosDisplayDriverOnly {
    param([string]$SelectedVendor)
    if (-not (Test-BastosAdministrator)) { throw 'La désinstallation du pilote graphique exige les droits administrateur.' }
    if (-not $ConfirmGpuOnly) { throw 'La confirmation GPU uniquement est obligatoire.' }
    $allDisplay = @(Get-BastosDisplayDrivers)
    $targets = @($allDisplay | Where-Object { $_.Vendor -eq $SelectedVendor })
    if ($targets.Count -eq 0) { throw "Aucun pilote graphique $SelectedVendor n est détecté." }
    $invalid = @($targets | Where-Object { $_.DeviceClass -ne 'DISPLAY' -or $_.PublishedName -notmatch '(?i)^oem\d+\.inf$' })
    if ($invalid.Count -gt 0) { throw 'La désinstallation est refusée : un pilote ciblé ne possède pas une classe DISPLAY et un nom INF OEM valides.' }

    $audioBefore = @(Get-BastosAudioSnapshot)
    $backupPath = New-BastosGraphicsBackup -DisplayDrivers $allDisplay -AudioDevices $audioBefore -SelectedVendor $SelectedVendor
    $restorePoint = New-BastosRestorePoint
    $results = @()
    foreach ($inf in @($targets.PublishedName | Sort-Object -Unique)) {
        Write-BastosGraphicsLog "Suppression du pilote DISPLAY $SelectedVendor : $inf"
        $output = & pnputil.exe /delete-driver $inf /uninstall /force 2>&1
        $code = $LASTEXITCODE
        $results += [pscustomobject]@{ Inf=$inf; ExitCode=$code; Output=(@($output) -join "`n") }
        if ($code -ne 0) { throw "PnPUtil a refusé la suppression du pilote graphique $inf (code $code). Aucun pilote audio n a été ciblé." }
    }
    Start-Sleep -Seconds 2
    $audioAfter = @(Get-BastosAudioSnapshot)
    $missingAudio = @($audioBefore | Where-Object { $_.DeviceId -notin @($audioAfter.DeviceId) })
    if ($missingAudio.Count -gt 0) {
        throw "Contrôle de sécurité audio en échec : $($missingAudio.Count) périphérique(s) audio ne répondent plus. Journal et sauvegarde : $backupPath"
    }
    $remaining = @(Get-BastosDisplayDrivers | Where-Object { $_.Vendor -eq $SelectedVendor -and $_.PublishedName -in @($targets.PublishedName) })
    return [ordered]@{ Success=($remaining.Count -eq 0); Vendor=$SelectedVendor; RemovedInf=@($targets.PublishedName|Sort-Object -Unique); Remaining=@($remaining); AudioPreserved=$true; AudioCount=$audioAfter.Count; BackupPath=$backupPath; RestorePointCreated=$restorePoint; Results=$results; RestartRecommended=$true }
}

function Open-BastosVendorDriverPage {
    param([string]$SelectedVendor)
    $uri = switch ($SelectedVendor) {
        'AMD' { 'https://www.amd.com/en/support/download/drivers.html' }
        'NVIDIA' { 'https://www.nvidia.com/en-us/drivers/' }
        'Intel' { 'https://www.intel.com/content/www/us/en/download-center/home.html' }
    }
    Start-Process $uri
    return $uri
}

function Set-BastosSafeVendorSettings {
    param([string]$SelectedVendor)
    switch ($SelectedVendor) {
        'AMD' {
            New-Item 'HKCU:\Software\AMD\CN' -Force | Out-Null
            New-Item 'HKCU:\Software\AMD\DVR' -Force | Out-Null
            New-ItemProperty 'HKCU:\Software\AMD\CN' -Name SystemTray -PropertyType String -Value 'false' -Force | Out-Null
            New-ItemProperty 'HKCU:\Software\AMD\DVR' -Name ShowRSOverlay -PropertyType String -Value 'false' -Force | Out-Null
            New-ItemProperty 'HKCU:\Software\AMD\DVR' -Name HotkeysDisabled -PropertyType DWord -Value 1 -Force | Out-Null
        }
        'NVIDIA' {
            New-Item 'HKCU:\Software\NVIDIA Corporation\NvTray' -Force | Out-Null
            New-ItemProperty 'HKCU:\Software\NVIDIA Corporation\NvTray' -Name StartOnLogin -PropertyType DWord -Value 0 -Force | Out-Null
        }
        'Intel' {
            foreach ($name in @('IntelGraphicsSoftware','IntelGraphicsCommandCenter')) {
                Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return [ordered]@{ Success=$true; Vendor=$SelectedVendor; Scope='Réglages utilisateur réversibles uniquement'; DriverRegistryUntouched=$true }
}

# Adapted from FR33THYFR33THY/Ultimate, 5 Graphics/3 Driver Updated Install & Settings.ps1
# (MIT, commit a0a33a57078434201f582b0db5107dcbb502292a).
# Copyright (c) FR33THY. Permission is hereby granted, free of charge, to
# any person obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction, including without
# limitation the rights to use, copy, modify, merge, publish, distribute,
# sublicense, and/or sell copies of the Software, and to permit persons to whom
# the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
# WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
# OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
function Get-BastosRegistryChildPaths([Microsoft.Win32.RegistryKey]$key,[string]$prefix=''){
    foreach($name in $key.GetSubKeyNames()){
        $relative=if($prefix){"$prefix\$name"}else{$name}
        $relative
        $child=$key.OpenSubKey($name)
        try{if($child){Get-BastosRegistryChildPaths $child $relative}}finally{if($child){$child.Dispose()}}
    }
}
function Get-BastosImportTargets {
    param([string]$SelectedVendor)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if($ExpectedUserSid -and $ExpectedUserSid -ne $sid){throw 'Le compte Windows a changé pendant l importation.'}
    $targets=[Collections.Generic.List[object]]::new()
    function AddTarget([string]$hive,[string]$path,[string]$name,[string]$kind,[object]$value){
        $targets.Add([pscustomobject]@{Hive=$hive;Path=$path;Name=$name;Kind=$kind;Value=$value})
    }
    $classPath='SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $root=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($classPath)
    try {
        if($root){foreach($sub in $root.GetSubKeyNames() | Where-Object {$_ -match '^\d{4}$'}){
            $key=$root.OpenSubKey($sub)
            try{
                $identity=(@('MatchingDeviceId','DriverDesc','ProviderName') | ForEach-Object {[string]$key.GetValue($_)}) -join ' '
                $matches=switch($SelectedVendor){
                    'AMD' {$identity -match '(?i)VEN_1002|AMD|Radeon|Advanced Micro'}
                    'NVIDIA' {$identity -match '(?i)VEN_10DE|NVIDIA|GeForce|Quadro'}
                    'Intel' {$identity -match '(?i)VEN_8086|Intel'}
                }
                if(-not $matches){continue}
                $path="$classPath\$sub"
                switch($SelectedVendor){
                    'AMD' {
                        AddTarget 'HKLM' $path 'KMD_DeLagEnabled' 'DWord' 1
                        $umd=$key.OpenSubKey('UMD')
                        if($umd){
                            try {
                                foreach($setting in @(@('VSyncControl','0'),@('TFQ','2'),@('Tessellation','1'),@('Tessellation_OPTION','2'))){
                                    $name=$setting[0];$desired=$setting[1]
                                    $kind=if($umd.GetValueNames() -contains $name){[string]$umd.GetValueKind($name)}else{'String'}
                                    if($kind -eq 'String'){AddTarget 'HKLM' "$path\UMD" $name 'String' $desired}
                                    elseif($kind -eq 'Binary'){
                                        $existing=[byte[]]$umd.GetValue($name)
                                        $hex=if($existing.Length -ge 4){'{0:X2}000000' -f [int][char]$desired}else{'{0:X2}00' -f [int][char]$desired}
                                        AddTarget 'HKLM' "$path\UMD" $name 'Binary' $hex
                                    }else{throw "Format AMD UMD non pris en charge : $name ($kind)."}
                                }
                            }finally{$umd.Dispose()}
                        }
                        foreach($relative in @(Get-BastosRegistryChildPaths $key)){
                            if($relative -match '(?i)(^|\\)power_v1$'){
                                AddTarget 'HKLM' "$path\$relative" 'abmlevel' 'Binary' '00000000'
                            }
                        }
                    }
                    'NVIDIA' {
                        AddTarget 'HKLM' $path 'DisableDynamicPstate' 'DWord' 1
                        AddTarget 'HKLM' $path 'RMHdcpKeyglobZero' 'DWord' 1
                        AddTarget 'HKLM' $path 'RmProfilingAdminOnly' 'DWord' 0
                    }
                    'Intel' {
                        AddTarget 'HKLM' "$path\3DKeys" 'Global_AsyncFlipMode' 'DWord' 2
                        AddTarget 'HKLM' "$path\3DKeys" 'Global_LowLatency' 'DWord' 1
                    }
                }
            }finally{if($key){$key.Dispose()}}
        }}
    }finally{if($root){$root.Dispose()}}
    if(-not @($targets | Where-Object {$_.Hive -eq 'HKLM'}).Count){throw "Aucun pilote $SelectedVendor compatible n est détecté."}
    switch($SelectedVendor){
        'AMD' {
            $p='Software\AMD\CN'
            AddTarget 'HKCU' $p 'AutoUpdate' 'DWord' 0
            AddTarget 'HKCU' $p 'WizardProfile' 'String' 'PROFILE_CUSTOM'
            AddTarget 'HKCU' "$p\CustomResolutions" 'EulaAccepted' 'String' 'true'
            AddTarget 'HKCU' "$p\DisplayOverride" 'EulaAccepted' 'String' 'true'
            AddTarget 'HKCU' $p 'SystemTray' 'String' 'false'
            AddTarget 'HKCU' $p 'CN_Hide_Toast_Notification' 'String' 'true'
            AddTarget 'HKCU' $p 'AnimationEffect' 'String' 'false'
            AddTarget 'HKCU' "$p\Notification" '*' 'Tree' 'Reset'
            foreach($name in @('FreeSync','OverlayNotification','VirtualSuperResolution')){
                AddTarget 'HKCU' "$p\$name" 'AlreadyNotified' 'DWord' 1
            }
        }
        'NVIDIA' {AddTarget 'HKCU' 'Software\NVIDIA Corporation\NvTray' 'StartOnLogin' 'DWord' 0}
    }
    if($SelectedVendor -eq 'AMD'){
        $monitorPath='SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorDataStore'
        $monitor=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($monitorPath)
        try{if($monitor){foreach($relative in @(Get-BastosRegistryChildPaths $monitor)){
            AddTarget 'HKLM' "$monitorPath\$relative" 'AutoColorManagementEnabled' 'DWord' 0
        }}}finally{if($monitor){$monitor.Dispose()}}
        foreach($gpu in @(Get-PnpDevice -Class Display -ErrorAction Stop)){
            if($gpu.InstanceId -match '(?i)^PCI\\VEN_[0-9A-F]{4}&' -and $gpu.InstanceId -notmatch '[/:]'){
                $msi="SYSTEM\CurrentControlSet\Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                AddTarget 'HKLM' $msi 'MSISupported' 'DWord' 1
            }
        }
        $iconsPath='Control Panel\NotifyIconSettings'
        $icons=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($iconsPath)
        try{if($icons){foreach($relative in @(Get-BastosRegistryChildPaths $icons)){
            AddTarget 'HKCU' "$iconsPath\$relative" 'IsPromoted' 'DWord' 1
        }}}finally{if($icons){$icons.Dispose()}}
    }
    return @($targets.ToArray())
}

function Get-BastosImportBackupPath([string]$SelectedVendor){
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return Join-Path $env:LOCALAPPDATA "BASTOS\Backups\GraphicsSettings-$SelectedVendor-$sid.json"
}
function ConvertFrom-BastosHex([string]$hex){
    if($hex.Length % 2){throw 'Valeur binaire invalide.'}
    $bytes=[byte[]]::new($hex.Length/2)
    for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($hex.Substring($i*2,2),16)}
    return ,$bytes
}
function Get-BastosImportKey([object]$item,[bool]$writable,[bool]$create){
    $hive=if($item.Hive -eq 'HKLM'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    if($create){return $hive.CreateSubKey([string]$item.Path,$true)}
    return $hive.OpenSubKey([string]$item.Path,$writable)
}
function Get-BastosImportTree([Microsoft.Win32.RegistryKey]$key,[string]$relative=''){
    $values=@(foreach($name in $key.GetValueNames()){
        $kind=[string]$key.GetValueKind($name)
        $value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($kind -eq 'Binary'){$value=[Convert]::ToBase64String([byte[]]$value)}
        [pscustomobject]@{Name=$name;Kind=$kind;Value=$value}
    })
    [pscustomobject]@{Relative=$relative;Values=$values}
    foreach($name in $key.GetSubKeyNames()){
        $child=$key.OpenSubKey($name)
        try{if($child){Get-BastosImportTree $child $(if($relative){"$relative\$name"}else{$name})}}finally{if($child){$child.Dispose()}}
    }
}
function Reset-BastosImportTree([object]$item,[array]$tree,[bool]$exists){
    $hive=if($item.Hive -eq 'HKLM'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    $parentPath=Split-Path -Path $item.Path -Parent
    $leaf=Split-Path -Path $item.Path -Leaf
    $parent=$hive.OpenSubKey($parentPath,$true)
    try{if($parent){$parent.DeleteSubKeyTree($leaf,$false)}}finally{if($parent){$parent.Dispose()}}
    if(-not $exists){return}
    $rootKey=$hive.CreateSubKey([string]$item.Path,$true)
    $rootKey.Dispose()
    foreach($node in $tree){
        $relative=[string]$node.Relative
        if($relative -match '(^|\\)\.\.?(\\|$)' -or $relative.StartsWith('\') -or $relative.Contains(':')){throw 'Chemin de sauvegarde graphique interdit.'}
        $path=if($relative){"$($item.Path)\$relative"}else{[string]$item.Path}
        $key=$hive.CreateSubKey($path,$true)
        try{foreach($value in @($node.Values)){
            $kind=[Microsoft.Win32.RegistryValueKind]$value.Kind
            if($value.Kind -eq 'Binary'){$data=[Convert]::FromBase64String([string]$value.Value)}else{$data=$value.Value}
            $key.SetValue([string]$value.Name,$data,$kind)
        }}finally{$key.Dispose()}
    }
}
function Get-BastosImportSnapshot([object]$item){
    $key=Get-BastosImportKey $item $false $false
    try{
        if($item.Kind -eq 'Tree'){
            if(-not $key){return [pscustomobject]@{Hive=$item.Hive;Path=$item.Path;Name=$item.Name;Exists=$false;Kind='Tree';Tree=@()}}
            return [pscustomobject]@{Hive=$item.Hive;Path=$item.Path;Name=$item.Name;Exists=$true;Kind='Tree';Tree=@(Get-BastosImportTree $key)}
        }
        $exists=$key -and ($key.GetValueNames() -contains $item.Name)
        if(-not $exists){return [pscustomobject]@{Hive=$item.Hive;Path=$item.Path;Name=$item.Name;Exists=$false}}
        $kind=[string]$key.GetValueKind($item.Name)
        $value=$key.GetValue($item.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($kind -eq 'Binary'){$value=[Convert]::ToBase64String([byte[]]$value)}
        return [pscustomobject]@{Hive=$item.Hive;Path=$item.Path;Name=$item.Name;Exists=$true;Kind=$kind;Value=$value}
    }finally{if($key){$key.Dispose()}}
}
function Get-BastosImportIdentity([object]$item){
    return "$($item.Hive)|$($item.Path)|$($item.Name)|$($item.Kind)"
}
function Test-BastosImportBackupStale([object]$data,[array]$identities,[bool]$allowAdditionalCurrent=$false){
    if($data.Schema -eq 1){return $true}
    if($data.Schema -ne 2){throw 'Format de sauvegarde des réglages graphiques inconnu.'}
    if(-not $data.PSObject.Properties['Targets']){throw 'Sauvegarde graphique incomplète : liste des cibles absente.'}
    if($allowAdditionalCurrent){return @($data.Targets | Where-Object {$_ -notin $identities}).Count -gt 0}
    return [bool](Compare-Object @($data.Targets) $identities)
}
function Test-BastosImportTargets([array]$targets){
    $mismatches=[Collections.Generic.List[string]]::new()
    foreach($item in $targets){
        $actual=Get-BastosImportSnapshot $item
        if($item.Kind -eq 'Tree'){
            if(-not $actual.Exists -or @($actual.Tree).Count -ne 1 -or @($actual.Tree[0].Values).Count){$mismatches.Add("Notifications ($($item.Path))")}
            continue
        }
        $expected=if($item.Kind -eq 'Binary'){[Convert]::ToBase64String((ConvertFrom-BastosHex ([string]$item.Value)))}else{[string]$item.Value}
        if(-not $actual.Exists -or $actual.Kind -ne $item.Kind -or [string]$actual.Value -cne $expected){
            $mismatches.Add("$($item.Name) ($($item.Path))")
        }
    }
    return @($mismatches.ToArray())
}
function Set-BastosImportValue([object]$item){
    if($item.Kind -eq 'Tree'){
        Reset-BastosImportTree $item @() $true
        return
    }
    $key=Get-BastosImportKey $item $true $true
    try{
        $kind=[Microsoft.Win32.RegistryValueKind]$item.Kind
        $value=if($item.Kind -eq 'Binary') {ConvertFrom-BastosHex ([string]$item.Value)} else {$item.Value}
        $key.SetValue($item.Name,$value,$kind)
    }finally{$key.Dispose()}
}
function Restore-BastosImportValues([array]$snapshots){
    foreach($item in $snapshots){
        if($item.PSObject.Properties['Kind'] -and $item.Kind -eq 'Tree'){
            Reset-BastosImportTree $item @($item.Tree) ([bool]$item.Exists)
            continue
        }
        $key=Get-BastosImportKey $item $true ([bool]$item.Exists)
        if(-not $key){continue}
        try{
            if(-not $item.Exists){$key.DeleteValue($item.Name,$false);continue}
            $kind=[Microsoft.Win32.RegistryValueKind]$item.Kind
            if($item.Kind -eq 'Binary'){$value=[Convert]::FromBase64String([string]$item.Value)}else{$value=$item.Value}
            $key.SetValue($item.Name,$value,$kind)
        }finally{$key.Dispose()}
    }
}
function Invoke-BastosSettingsImport([string]$SelectedVendor,[string]$Operation){
    $backup=Get-BastosImportBackupPath $SelectedVendor
    if($Operation -eq 'PreviewImport'){
        $settings=switch($SelectedVendor){
            'AMD' {
                $targets=@(Get-BastosImportTargets 'AMD')
                $displayCount=@($targets | Where-Object {$_.Name -eq 'AutoColorManagementEnabled'}).Count
                $iconCount=@($targets | Where-Object {$_.Name -eq 'IsPromoted'}).Count
                @(
                    "Profil AMD complet : $($targets.Count) valeurs ou groupes détectés sur ce PC.",
                    'Graphismes : Anti-Lag, V-Sync, filtrage des textures, tessellation et profil personnalisé.',
                    'Affichage : acceptation des conditions AMD des résolutions personnalisées et des dérogations ; Vari-Bright (si présent).',
                    'AMD Software : mises à jour manuelles, icône et animations désactivées ; notifications effacées et indicateurs FreeSync, Overlay et VSR marqués comme vus.',
                    "Windows : gestion automatique des couleurs désactivée sur $displayCount entrée(s) d écran ; MSI activé pour les GPU ; $iconCount icône(s) de la barre des tâches affichée(s).",
                    'Les conditions des fonctions d affichage AMD seront marquées comme acceptées : lis-les dans AMD Software avant de confirmer.'
                )
            }
            'NVIDIA' {@('Pilote NVIDIA : DisableDynamicPstate = 1; RMHdcpKeyglobZero = 1; RmProfilingAdminOnly = 0','NVIDIA NvTray : StartOnLogin = 0')}
            'Intel' {@('Pilote Intel 3DKeys : Global_AsyncFlipMode = 2; Global_LowLatency = 1')}
        }
        return [ordered]@{Success=$true;Vendor=$SelectedVendor;Settings=@($settings);BackupExists=(Test-Path -LiteralPath $backup -PathType Leaf);BackupPath=$backup}
    }
    if($Operation -eq 'RestoreImport'){
        if(-not (Test-Path -LiteralPath $backup -PathType Leaf)){throw 'Aucune sauvegarde des réglages importés pour ce constructeur.'}
        $data=Get-Content -LiteralPath $backup -Raw -Encoding UTF8|ConvertFrom-Json
        if($data.Vendor -ne $SelectedVendor -or $data.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Sauvegarde non compatible avec ce compte ou constructeur.'}
        $currentTargets=@(Get-BastosImportTargets $SelectedVendor)
        $allowed=@($currentTargets | ForEach-Object {"$($_.Hive)|$($_.Path)|$($_.Name)"})
        $currentIdentities=@($currentTargets | ForEach-Object {Get-BastosImportIdentity $_})
        $stale=Test-BastosImportBackupStale $data $currentIdentities $true
        if($data.Schema -eq 2 -and $stale){
            throw 'Le pilote ou le format des réglages a changé depuis la sauvegarde. Restauration automatique impossible.'
        }
        foreach($item in @($data.Values)){
            $identity="$($item.Hive)|$($item.Path)|$($item.Name)"
            if($identity -notin $allowed){throw 'Le pilote a changé depuis la sauvegarde. Restauration automatique impossible.'}
        }
        if($Operation -eq 'RestoreImport' -and -not (Test-BastosAdministrator)){throw 'Droits administrateur requis pour restaurer les réglages du pilote.'}
        Restore-BastosImportValues @($data.Values)
        Remove-Item -LiteralPath $backup -Force
        return [ordered]@{Success=$true;Message='Valeurs précédentes restaurées';BackupPath=$backup;Count=@($data.Values).Count}
    }
    $targets=@(Get-BastosImportTargets $SelectedVendor)
    if($Operation -eq 'VerifyImport'){
        $mismatches=@(Test-BastosImportTargets $targets)
        return [ordered]@{Success=($mismatches.Count -eq 0);Vendor=$SelectedVendor;Count=$targets.Count;MismatchCount=$mismatches.Count;Mismatches=$mismatches;Message=if($mismatches.Count){"$($mismatches.Count) réglage(s) sur $($targets.Count) ne sont pas actifs."}else{'Tous les réglages importés sont présents.'}}
    }
    if(-not (Test-BastosAdministrator)){throw 'Droits administrateur requis pour importer les réglages du pilote.'}
    $identities=@($targets | ForEach-Object {Get-BastosImportIdentity $_})
    if(Test-Path -LiteralPath $backup -PathType Leaf){
        $existing=Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
        if($existing.Vendor -ne $SelectedVendor -or $existing.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Sauvegarde non compatible avec ce compte ou constructeur.'}
        if(Test-BastosImportBackupStale $existing $identities $true){
            $archive=[IO.Path]::Combine((Split-Path $backup),([IO.Path]::GetFileNameWithoutExtension($backup)+'-ancien-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'.json'))
            Move-Item -LiteralPath $backup -Destination $archive
        }else{
            $saved=@($existing.Targets)
            $added=@($targets | Where-Object {(Get-BastosImportIdentity $_) -notin $saved})
            if($added.Count){
                $existing.Targets=@($saved)+@($added | ForEach-Object {Get-BastosImportIdentity $_})
                $existing.Values=@($existing.Values)+@($added | ForEach-Object {Get-BastosImportSnapshot $_})
                $temp=$backup+'.merge-'+[guid]::NewGuid().ToString('N')
                [IO.File]::WriteAllText($temp,($existing|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
                $history=$backup+'.premerge-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
                [IO.File]::Replace($temp,$backup,$history)
            }
        }
    }
    $fresh=-not (Test-Path -LiteralPath $backup -PathType Leaf)
    $snapshots=if($fresh){@($targets|ForEach-Object {Get-BastosImportSnapshot $_})}else{@()}
    if($fresh){
        $data=[ordered]@{Schema=2;Vendor=$SelectedVendor;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;CreatedUtc=[DateTime]::UtcNow.ToString('o');Targets=$identities;Values=$snapshots}
        New-Item -ItemType Directory -Path (Split-Path $backup) -Force|Out-Null
        [IO.File]::WriteAllText($backup,($data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    }
    try{foreach($item in $targets){Set-BastosImportValue $item}}
    catch{if($fresh){Restore-BastosImportValues $snapshots;Remove-Item -LiteralPath $backup -Force};throw}
    Start-Sleep -Milliseconds 750
    $mismatches=@(Test-BastosImportTargets $targets)
    if($mismatches.Count){
        return [ordered]@{Success=$false;Vendor=$SelectedVendor;Count=$targets.Count;MismatchCount=$mismatches.Count;Mismatches=$mismatches;BackupPath=$backup;Message="Import incomplet : $($mismatches.Count) réglage(s) sur $($targets.Count) ne correspondent pas. Vérifier AMD Software ou le pilote. Sauvegarde conservée."}
    }
    return [ordered]@{Success=$true;Vendor=$SelectedVendor;Count=$targets.Count;BackupPath=$backup;Message='Réglages vérifiés après import — redémarrage conseillé'}
}

try {
    $drivers = @(Get-BastosDisplayDrivers)
    $selectedVendor = if ($Action -in @('Status','Inventory','OpenDisplaySettings')) { $Vendor } else { Resolve-BastosVendor -Requested $Vendor -Drivers $drivers }
    $result = switch ($Action) {
        'Status' { [ordered]@{ Success=$true; Architecture='BASTOS Graphics Vendor Workflow v2'; DisplayDrivers=$drivers; Workflow=(Get-BastosGraphicsWorkflow); AudioProtection='Les outils doivent rester en mode GPU uniquement; aucun nettoyage Audio ne doit être sélectionné' } }
        'Inventory' { [ordered]@{ Success=$true; DisplayDrivers=$drivers; AudioDevices=@(Get-BastosAudioSnapshot) } }
        'CreateRestorePoint' { [ordered]@{ Success=(New-BastosRestorePoint) } }
        'RemoveDisplayDriver' { Remove-BastosDisplayDriverOnly -SelectedVendor $selectedVendor }
        'OpenDdu' { Start-Process 'https://www.wagnardsoft.com/display-driver-uninstaller-ddu'; [ordered]@{ Success=$true; ManualOnly=$true; Rule='Dans DDU, sélectionner GPU et le constructeur. Ne jamais sélectionner Audio, Realtek ou Sound Blaster.' } }
        'OpenOfficialDriver' { [ordered]@{ Success=$true; Vendor=$selectedVendor; Uri=(Open-BastosVendorDriverPage -SelectedVendor $selectedVendor) } }
        'ApplySafeSettings' { Set-BastosSafeVendorSettings -SelectedVendor $selectedVendor }
        'PreviewImport' { Invoke-BastosSettingsImport -SelectedVendor $selectedVendor -Operation $Action }
        'ApplyImport' { Invoke-BastosSettingsImport -SelectedVendor $selectedVendor -Operation $Action }
        'RestoreImport' { Invoke-BastosSettingsImport -SelectedVendor $selectedVendor -Operation $Action }
        'VerifyImport' { Invoke-BastosSettingsImport -SelectedVendor $selectedVendor -Operation $Action }
        'OpenDisplaySettings' { Start-Process 'ms-settings:display-advanced'; [ordered]@{ Success=$true } }
        'StartVendorCleanup' {
            $state = Set-BastosGraphicsWorkflow -SelectedVendor $selectedVendor -Stage 'CleanupStarted'
            if ($selectedVendor -eq 'AMD') {
                Start-Process 'https://drivers.amd.com/drivers/amdcleanuputility.exe'
                [ordered]@{ Success=$true; Vendor='AMD'; Stage=$state.Stage; Tool='AMD Cleanup Utility'; Official=$true; RestartRequired=$true; Warning='AMD indique que cet outil retire les pilotes graphiques et audio AMD, mais pas les pilotes chipset.' }
            } elseif ($selectedVendor -eq 'NVIDIA') {
                Start-Process 'https://www.wagnardsoft.com/display-driver-uninstaller-ddu'
                [ordered]@{ Success=$true; Vendor='NVIDIA'; Stage=$state.Stage; Tool='DDU'; Official=$false; RestartRequired=$true; Warning='Dans DDU sélectionner GPU puis NVIDIA. Ne jamais sélectionner Audio, Realtek ou Sound Blaster.' }
            } else { throw 'Ce parcours est disponible pour AMD et NVIDIA.' }
        }
        'ContinueOfficialDriver' {
            $uri = Open-BastosVendorDriverPage -SelectedVendor $selectedVendor
            $state = Set-BastosGraphicsWorkflow -SelectedVendor $selectedVendor -Stage 'ReadyForSlimmer'
            [ordered]@{ Success=$true; Vendor=$selectedVendor; Stage=$state.Stage; Uri=$uri }
        }
        'OpenSlimmer' {
            if ($selectedVendor -eq 'AMD') { $uri='https://github.com/GSDragoon/RadeonSoftwareSlimmer/releases' }
            elseif ($selectedVendor -eq 'NVIDIA') { $uri='https://www.techpowerup.com/download/techpowerup-nvcleanstall/' }
            else { throw "Aucun outil d allègement n est configuré pour ce constructeur." }
            Start-Process $uri
            $state = Set-BastosGraphicsWorkflow -SelectedVendor $selectedVendor -Stage 'Completed'
            [ordered]@{ Success=$true; Vendor=$selectedVendor; Stage=$state.Stage; Uri=$uri; ThirdParty=$true }
        }
    }
    Write-BastosGraphicsResult $result
    if($result.Success -eq $false){Write-BastosGraphicsLog "Action incomplète : $Action / $selectedVendor — $($result.Message)" 'ERROR';exit 1}
    Write-BastosGraphicsLog "Action terminée : $Action / $selectedVendor" 'OK'
    exit 0
} catch {
    Write-BastosGraphicsLog "Échec $Action : $($_.Exception.Message)" 'ERROR'
    Write-BastosGraphicsResult ([ordered]@{ Success=$false; Action=$Action; Vendor=$Vendor; Message=$_.Exception.Message })
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
