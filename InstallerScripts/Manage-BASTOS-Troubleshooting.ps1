[CmdletBinding()]
param(
    [ValidateSet('Get','Enable','Disable','Apply')][string]$Action = 'Get',
    [string]$Option = '',
    [string]$Value = '',
    [string]$ExpectedUserSid = '',
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RegDword([string]$Path,[string]$Name,[int]$Default = 0) {
    try { return [int](Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop) } catch { return $Default }
}
function Set-RegDword([string]$Path,[string]$Name,[int]$Data) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Data -Force | Out-Null
}
function Set-ServiceMode([string]$Name,[bool]$Enabled,[string]$Startup = 'Automatic') {
    $services = @(Get-Service -Name $Name -ErrorAction SilentlyContinue)
    foreach ($service in $services) {
        if ($Enabled) {
            Set-Service -Name $service.Name -StartupType $Startup -ErrorAction SilentlyContinue
            Start-Service -Name $service.Name -ErrorAction SilentlyContinue
        } else {
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
}
function Set-IfeoBlock([string[]]$Executables,[bool]$Blocked) {
    foreach ($exe in $Executables) {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe"
        if ($Blocked) {
            if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
            New-ItemProperty -LiteralPath $key -Name Debugger -PropertyType String -Value "$env:WINDIR\System32\cmd.exe /d /c exit" -Force | Out-Null
        } elseif (Test-Path -LiteralPath $key) {
            Remove-ItemProperty -LiteralPath $key -Name Debugger -ErrorAction SilentlyContinue
        }
    }
}
function Test-IfeoBlocked([string]$Executable) {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$Executable"
    return [bool](Get-ItemProperty -LiteralPath $key -Name Debugger -ErrorAction SilentlyContinue)
}

function Test-ServiceEnabled([string]$Name) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    return [bool]($service -and $service.StartMode -ne 'Disabled')
}
function Test-BackgroundMaintenanceDisabled {
    return (Get-RegDword 'HKLM:\SOFTWARE\BASTOS\RiskyOptimizations' 'RiskDisableBackgroundMaintenance' 0) -eq 1
}
function Assert-BackgroundMaintenanceAllows([string]$Feature) {
    if (-not (Test-BackgroundMaintenanceDisabled)) { return }

    $detail = switch ($Feature) {
        'Bluetooth' { 'Bluetooth (bthserv, BTAGService et les périphériques Bluetooth)' }
        'Printer' { "l’impression (Spooler et les services d’impression)" }
        default { $Feature }
    }
    throw "Le réglage $detail est verrouillé par « Désactiver la maintenance et des services Windows ». Désactivez d’abord cette option expérimentale dans Bastos : les valeurs sauvegardées seront restaurées, puis ce réglage pourra être modifié."
}

$dg='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$hvci="$dg\Scenarios\HypervisorEnforcedCodeIntegrity"
$pol='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'
$wu='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$ci='HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config'
$tcp4='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
$result=[ordered]@{Success=$false;Message='';States=[ordered]@{};Choices=[ordered]@{};UpdatedUtc=[datetime]::UtcNow.ToString('o')}

try {
    if ($Action -eq 'Get') {
        $result.States.Wifi = Test-ServiceEnabled 'WlanSvc'
        $result.States.Bluetooth = Test-ServiceEnabled 'bthserv'
        $result.States.Printer = Test-ServiceEnabled 'Spooler'
        $result.States.Vbs = (Get-RegDword $dg 'EnableVirtualizationBasedSecurity' 0) -eq 1
        $result.States.Hvci = (Get-RegDword $hvci 'Enabled' 0) -eq 1
        $result.States.Lua = (Get-RegDword "$pol\System" 'EnableLUA' 1) -eq 1
        $result.States.VulnerableDriverBlockList = (Get-RegDword $ci 'VulnerableDriverBlocklistEnable' 1) -eq 1
        $result.States.TextInputHost = -not (Test-IfeoBlocked 'TextInputHost.exe')
        $result.States.WindowsUpdateDrivers = (Get-RegDword $wu 'ExcludeWUDriversInQualityUpdate' 0) -eq 0
        $result.States.StartMenu = -not (Test-IfeoBlocked 'StartMenuExperienceHost.exe')
        $result.States.SearchHost = -not (Test-IfeoBlocked 'SearchHost.exe')
        $result.States.CrossDeviceResume = -not (Test-IfeoBlocked 'CrossDeviceResume.exe')
        $result.States.UseDefaultTile = (Get-RegDword "$pol\Explorer" 'UseDefaultTile' 0) -eq 1
        $ttl=Get-RegDword $tcp4 'DefaultTTL' 128
        $result.Choices.HopLimit = if($ttl -eq 128){'Par défaut (128)'}else{"$ttl"}
        $bcd=(& bcdedit.exe /enum '{current}' 2>$null | Out-String)
        $nx=if($bcd -match '(?im)^nx\s+(\S+)'){$Matches[1]}else{'OptIn'}
        $result.Choices.Nx = switch($nx.ToLowerInvariant()){'optout'{'OptOut'}'alwayson'{'AlwaysOn'}'alwaysoff'{'AlwaysOff'}default{'OptIn (par défaut)'}}
        $compat=Get-RegDword 'HKLM:\SOFTWARE\BASTOS\Troubleshooting' 'GameServicesCompatibility' 0
        $result.Choices.GameServices = if($compat -eq 1){'Compatibilité FiveM / Minecraft'}else{'Valeur BASTOS par défaut (restaurer)'}
        $result.Success=$true; $result.Message='État des réglages actualisé.'
    } elseif ($Action -in @('Enable','Disable')) {
        $enabled = $Action -eq 'Enable'
        switch ($Option) {
            'Wifi' {
                Set-ServiceMode 'WlanSvc' $enabled
                Set-ServiceMode 'vwififlt' $enabled 'Manual'
                Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceDescription -match 'Wireless|Wi-?Fi|802\.11'} | ForEach-Object { if($enabled){Enable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue}else{Disable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue} }
            }
            'Bluetooth' {
                Assert-BackgroundMaintenanceAllows 'Bluetooth'
                Set-ServiceMode 'bthserv' $enabled 'Manual'; Set-ServiceMode 'BluetoothUserService*' $enabled 'Manual'
                Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | ForEach-Object { if($enabled){Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue}else{Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue} }
            }
            'Printer' {
                Assert-BackgroundMaintenanceAllows 'Printer'
                Set-ServiceMode 'Spooler' $enabled; Set-ServiceMode 'PrintNotify' $enabled 'Manual'; Set-ServiceMode 'PrintWorkflowUserSvc*' $enabled 'Manual'
            }
            
            'Vbs' { Set-RegDword $dg 'EnableVirtualizationBasedSecurity' ([int]$enabled) }
            'Hvci' { Set-RegDword $hvci 'Enabled' ([int]$enabled) }
            'Lua' { Set-RegDword "$pol\System" 'EnableLUA' ([int]$enabled) }
            'VulnerableDriverBlockList' { Set-RegDword $ci 'VulnerableDriverBlocklistEnable' ([int]$enabled) }
            'TextInputHost' { Set-IfeoBlock @('TextInputHost.exe','TextInputHostNoUi.exe') (-not $enabled) }
            'WindowsUpdateDrivers' { Set-RegDword $wu 'ExcludeWUDriversInQualityUpdate' ([int](-not $enabled)); Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' $(if($enabled){1}else{0}) }
            'StartMenu' { Set-IfeoBlock @('StartMenuExperienceHost.exe') (-not $enabled) }
            'SearchHost' { Set-IfeoBlock @('SearchHost.exe','SearchApp.exe') (-not $enabled) }
            'CrossDeviceResume' { Set-IfeoBlock @('CrossDeviceResume.exe') (-not $enabled) }
            'UseDefaultTile' { Set-RegDword "$pol\Explorer" 'UseDefaultTile' ([int]$enabled) }
            default { throw "Réglage inconnu : $Option" }
        }
        $result.Success=$true; $result.Message=if($enabled){'Réglage activé. Un redémarrage peut être nécessaire.'}else{'Réglage désactivé. Un redémarrage peut être nécessaire.'}
    } else {
        switch ($Option) {
            'HopLimit' {
                $number=if($Value -match '64'){64}elseif($Value -match '255'){255}else{128}
                Set-RegDword $tcp4 'DefaultTTL' $number
                & netsh.exe interface ipv6 set global "defaultcurhoplimit=$number" | Out-Null
            }
            'Nx' {
                $mode=if($Value -match 'OptOut'){'OptOut'}elseif($Value -match 'AlwaysOn'){'AlwaysOn'}elseif($Value -match 'AlwaysOff'){'AlwaysOff'}else{'OptIn'}
                & bcdedit.exe /set '{current}' nx $mode | Out-Null
                if($LASTEXITCODE -ne 0){throw "BCD a retourné le code $LASTEXITCODE."}
            }
            'GameServices' {
                $compat=$Value -match 'Compatibilité'
                foreach($name in @('BFE','DPS','iphlpsvc','Winmgmt','GamingServices','GamingServicesNet','XboxGipSvc','XblAuthManager','XblGameSave','XboxNetApiSvc')){Set-ServiceMode $name $true 'Manual'}
                Set-RegDword 'HKLM:\SOFTWARE\BASTOS\Troubleshooting' 'GameServicesCompatibility' ([int]$compat)
            }
            'AdministratorFullName' {
                $administrator=Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop | Where-Object {[string]$_.SID -match '-500$'} | Select-Object -First 1
                if(-not $administrator){throw 'Le compte Administrateur integre (SID -500) est introuvable.'}
                $user=[string]$administrator.Name
                & net.exe user $user /fullname:"$Value" | Out-Null
                if($LASTEXITCODE -ne 0){throw "La modification du compte a retourné le code $LASTEXITCODE."}
            }
            
            default { throw "Réglage inconnu : $Option" }
        }
        $result.Success=$true; if (!$result.Message) { $result.Message='Réglage appliqué. Un redémarrage peut être nécessaire.' }
    }
} catch { $result.Message=$_.Exception.Message }
finally {
    $parent=Split-Path -Parent ([IO.Path]::GetFullPath($ResultPath)); if(-not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
if($result.Success){exit 0}else{exit 1}
