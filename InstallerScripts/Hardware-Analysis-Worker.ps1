[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [string]$CimNamespace = 'root/cimv2',
    [string]$OperationId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
$script:AnalysisErrors = New-Object Collections.Generic.List[object]
$script:CimNamespace = $CimNamespace

function Write-AnalysisProgress {
    param([int]$Percent, [string]$Phase, [string]$Message)
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}
function Add-AnalysisError {
    param([string]$Category, [string]$Message)
    $script:AnalysisErrors.Add([pscustomobject]@{ Category=$Category; Message=$Message })
}

function Get-CimSafe {
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace=$script:CimNamespace,
        [string]$Filter='',
        [string[]]$Property=@('*'),
        [int]$TimeoutSeconds=10
    )
    try {
        $parameters = @{
            ClassName=$ClassName
            Namespace=$Namespace
            OperationTimeoutSec=$TimeoutSeconds
            ErrorAction='Stop'
        }
        if ($Filter) { $parameters.Filter = $Filter }
        $items = @(Get-CimInstance @parameters)
        if ($Property.Count -eq 1 -and $Property[0] -eq '*') { return $items }
        return @($items | Select-Object -Property $Property)
    } catch {
        Add-AnalysisError -Category $ClassName -Message $_.Exception.Message
        return @()
    }
}

function Convert-AnalysisDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [datetime]) { return ([datetime]$Value).ToString('yyyy-MM-dd') }
        return ([Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToString('yyyy-MM-dd')
    } catch {
        try { return ([datetime]$Value).ToString('yyyy-MM-dd') } catch { return [string]$Value }
    }
}

function Convert-ToGiB {
    param($Bytes)
    if ($null -eq $Bytes) { return $null }
    try { return [math]::Round(([double]$Bytes / 1GB), 2) } catch { return $null }
}

function Get-StorageType {
    param($Disk)
    $text = "$($Disk.Model) $($Disk.MediaType) $($Disk.InterfaceType) $($Disk.PNPDeviceID)"
    if ($text -match '(?i)NVMe|NVM Express') { return 'NVMe' }
    if ($text -match '(?i)SSD|Solid State') { return 'SSD SATA ou autre' }
    if ($text -match '(?i)SATA|IDE') { return 'SATA' }
    if ($text -match '(?i)USB') { return 'USB' }
    return 'Information indisponible'
}

function Get-ComputerType {
    param([string]$Manufacturer, [string]$Model, [int[]]$ChassisTypes)
    $portableCodes = @(8,9,10,11,12,14,18,21,30,31,32)
    if (@($ChassisTypes | Where-Object { $portableCodes -contains $_ }).Count -gt 0) { return 'Portable' }
    if ("$Manufacturer $Model" -match '(?i)Dell|Alienware|Hewlett-Packard|\bHP\b|Lenovo|ThinkPad|Legion|Acer|Predator|ASUS|ROG|MSI|Micro-Star') { return 'Ordinateur de marque' }
    return 'PC assemble'
}

try {
    $progressFolder = Split-Path -Parent $ProgressPath
    $resultFolder = Split-Path -Parent $ResultPath
    if ($progressFolder) { New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null }
    if ($resultFolder) { New-Item -ItemType Directory -Path $resultFolder -Force | Out-Null }

    Write-AnalysisProgress 3 'Etape 1/9 - Systeme' 'Lecture de Windows et du type de machine...'
    $computer = @(Get-CimSafe -ClassName Win32_ComputerSystem -Property Manufacturer,Model,PCSystemType,TotalPhysicalMemory,NumberOfLogicalProcessors,SystemType,Name | Select-Object -First 1)
    $os = @(Get-CimSafe -ClassName Win32_OperatingSystem -Property Caption,Version,BuildNumber,OSArchitecture,CSName,InstallDate | Select-Object -First 1)
    $enclosures = @(Get-CimSafe -ClassName Win32_SystemEnclosure -Property ChassisTypes)
    $chassisTypes = @($enclosures | ForEach-Object { @($_.ChassisTypes) } | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Select-Object -Unique)

    Write-AnalysisProgress 12 'Etape 2/9 - Carte mere et BIOS' 'Lecture de la carte mere, du BIOS et du Secure Boot...'
    $boardRaw = @(Get-CimSafe -ClassName Win32_BaseBoard -Property Manufacturer,Product,Version | Select-Object -First 1)
    $biosRaw = @(Get-CimSafe -ClassName Win32_BIOS -Property Manufacturer,SMBIOSBIOSVersion,Version,ReleaseDate | Select-Object -First 1)
    $secureBoot = 'Information indisponible'
    try { $secureBoot = if ([bool](Confirm-SecureBootUEFI -ErrorAction Stop)) { 'Actif' } else { 'Inactif' } } catch { Add-AnalysisError 'Secure Boot' $_.Exception.Message }
    $firmwareMode = 'Information indisponible'
    try {
        $firmware = Get-ComputerInfo -Property BiosFirmwareType -ErrorAction Stop
        if ($firmware -and $firmware.BiosFirmwareType) { $firmwareMode = [string]$firmware.BiosFirmwareType }
    } catch { Add-AnalysisError 'Mode BIOS' $_.Exception.Message }

    Write-AnalysisProgress 23 'Etape 3/9 - Processeur et memoire' 'Lecture des processeurs et des barrettes de memoire...'
    $cpuRaw = @(Get-CimSafe -ClassName Win32_Processor -Property Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed)
    $memoryRaw = @(Get-CimSafe -ClassName Win32_PhysicalMemory -Property Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed,DeviceLocator)

    Write-AnalysisProgress 34 'Etape 4/9 - Carte graphique' 'Lecture de tous les GPU et de leurs pilotes...'
    $gpuRaw = @(Get-CimSafe -ClassName Win32_VideoController -Property Name,AdapterCompatibility,DriverVersion,DriverDate,AdapterRAM,PNPDeviceID,Status)

    Write-AnalysisProgress 44 'Etape 5/9 - Stockage' 'Lecture des disques, volumes, espace libre et etat de sante...'
    $diskRaw = @(Get-CimSafe -ClassName Win32_DiskDrive -Property Model,Manufacturer,InterfaceType,MediaType,Size,Status,PNPDeviceID,Index)
    $volumeRaw = @(Get-CimSafe -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -Property DeviceID,FileSystem,Size,FreeSpace)
    $physicalDisks = @()
    try {
        $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,Size)
    } catch { Add-AnalysisError 'SMART / PhysicalDisk' $_.Exception.Message }

    Write-AnalysisProgress 56 'Etape 6/9 - Reseau et audio' 'Lecture des controleurs Ethernet, Wi-Fi, Bluetooth et audio...'
    $networkRaw = @(Get-CimSafe -ClassName Win32_NetworkAdapter -Property Name,Manufacturer,AdapterType,PhysicalAdapter,NetEnabled,PNPDeviceID,NetConnectionID | Where-Object { $_.PhysicalAdapter -or $_.PNPDeviceID -match '(?i)PCI|USB' })
    $audioRaw = @(Get-CimSafe -ClassName Win32_SoundDevice -Property Name,Manufacturer,PNPDeviceID,Status)

    Write-AnalysisProgress 68 'Etape 7/9 - Peripheriques' 'Recherche des peripheriques inconnus ou en erreur...'
    $pnpRaw = @(Get-CimSafe -ClassName Win32_PnPEntity -Property Name,Manufacturer,PNPDeviceID,HardwareID,Status,ConfigManagerErrorCode,Service,ClassGuid)
    # Le code PnP 22 signifie « périphérique désactivé » et ne prouve ni une
    # panne ni l'absence d'un pilote. Ne signaler que les erreurs réelles ou
    # les périphériques explicitement inconnus.
    $problemRaw = @($pnpRaw | Where-Object {
        (([int]$_.ConfigManagerErrorCode -ne 0) -and ([int]$_.ConfigManagerErrorCode -ne 22)) -or
        ([string]$_.Name -match '(?i)unknown device|peripherique inconnu')
    })

    Write-AnalysisProgress 79 'Etape 8/9 - Pilotes installes' 'Inventaire des pilotes PnP signes et de leurs versions...'
    $driverRaw = @(Get-CimSafe -ClassName Win32_PnPSignedDriver -Property DeviceName,Manufacturer,DriverProviderName,DriverVersion,DriverDate,IsSigned,DeviceID,InfName | Where-Object { $_.DeviceName })

    Write-AnalysisProgress 91 'Etape 9/9 - Classification' 'Construction du rapport local et des indicateurs...'
    $systemObject = [pscustomobject]@{
        Manufacturer=$(if($computer){[string]$computer[0].Manufacturer}else{'Information indisponible'})
        Model=$(if($computer){[string]$computer[0].Model}else{'Information indisponible'})
        PCSystemType=$(if($computer){[string]$computer[0].PCSystemType}else{'Information indisponible'})
        ChassisTypes=$chassisTypes
        ComputerType=$(Get-ComputerType -Manufacturer $(if($computer){[string]$computer[0].Manufacturer}else{''}) -Model $(if($computer){[string]$computer[0].Model}else{''}) -ChassisTypes $chassisTypes)
        WindowsEdition=$(if($os){[string]$os[0].Caption}else{'Information indisponible'})
        WindowsVersion=$(if($os){[string]$os[0].Version}else{'Information indisponible'})
        BuildNumber=$(if($os){[string]$os[0].BuildNumber}else{'Information indisponible'})
        Architecture=$(if($os){[string]$os[0].OSArchitecture}else{[string]$env:PROCESSOR_ARCHITECTURE})
        ComputerName=$(if($os){[string]$os[0].CSName}elseif($computer){[string]$computer[0].Name}else{$env:COMPUTERNAME})
        WindowsInstallDate=$(if($os){Convert-AnalysisDate $os[0].InstallDate}else{$null})
        TotalMemoryGB=$(if($computer){Convert-ToGiB $computer[0].TotalPhysicalMemory}else{$null})
    }
    $motherboardObject = [pscustomobject]@{
        Manufacturer=$(if($boardRaw){[string]$boardRaw[0].Manufacturer}else{'Information indisponible'})
        Model=$(if($boardRaw){[string]$boardRaw[0].Product}else{'Information indisponible'})
        Revision=$(if($boardRaw){[string]$boardRaw[0].Version}else{'Information indisponible'})
        BiosManufacturer=$(if($biosRaw){[string]$biosRaw[0].Manufacturer}else{'Information indisponible'})
        BiosVersion=$(if($biosRaw){[string]$biosRaw[0].SMBIOSBIOSVersion}else{'Information indisponible'})
        BiosReleaseDate=$(if($biosRaw){Convert-AnalysisDate $biosRaw[0].ReleaseDate}else{$null})
        FirmwareMode=$firmwareMode
        SecureBoot=$secureBoot
    }
    $processors = @($cpuRaw | ForEach-Object {
        [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; Cores=[int]$_.NumberOfCores; Threads=[int]$_.NumberOfLogicalProcessors; MaxClockMHz=[int]$_.MaxClockSpeed }
    })
    $memory = @($memoryRaw | ForEach-Object {
        [pscustomobject]@{ Manufacturer=[string]$_.Manufacturer; PartNumber=([string]$_.PartNumber).Trim(); CapacityGB=Convert-ToGiB $_.Capacity; SpeedMHz=$_.Speed; ConfiguredClockMHz=$_.ConfiguredClockSpeed; Slot=[string]$_.DeviceLocator }
    })
    $graphics = @($gpuRaw | ForEach-Object {
        [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.AdapterCompatibility; DriverVersion=[string]$_.DriverVersion; DriverDate=Convert-AnalysisDate $_.DriverDate; MemoryGB=Convert-ToGiB $_.AdapterRAM; PNPDeviceID=[string]$_.PNPDeviceID; Status=[string]$_.Status }
    })
    $storage = @($diskRaw | ForEach-Object {
        $disk = $_
        $health = @($physicalDisks | Where-Object { [string]$_.FriendlyName -eq [string]$disk.Model } | Select-Object -First 1)
        [pscustomobject]@{ Model=[string]$disk.Model; Manufacturer=[string]$disk.Manufacturer; Type=Get-StorageType $disk; CapacityGB=Convert-ToGiB $disk.Size; Status=[string]$disk.Status; Health=$(if($health){[string]$health[0].HealthStatus}else{'Information indisponible'}); PNPDeviceID=[string]$disk.PNPDeviceID }
    })
    $volumes = @($volumeRaw | ForEach-Object {
        $size = [double]$_.Size
        $free = [double]$_.FreeSpace
        $freePercent = if($size -gt 0){[math]::Round(100*$free/$size,1)}else{$null}
        [pscustomobject]@{ Drive=[string]$_.DeviceID; FileSystem=[string]$_.FileSystem; CapacityGB=Convert-ToGiB $_.Size; FreeGB=Convert-ToGiB $_.FreeSpace; FreePercent=$freePercent; Status=$(if($null -ne $freePercent -and $freePercent -lt 10){'Attention - espace faible'}else{'Correct'}) }
    })
    $network = @($networkRaw | ForEach-Object {
        $type = if([string]$_.Name -match '(?i)Bluetooth'){'Bluetooth'}elseif("$($_.Name) $($_.AdapterType)" -match '(?i)Wireless|Wi-Fi|802\.11|WLAN'){'Wi-Fi'}else{'Ethernet'}
        [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; Type=$type; Enabled=$_.NetEnabled; PNPDeviceID=[string]$_.PNPDeviceID }
    })
    $bluetoothExtras = @($pnpRaw | Where-Object { [string]$_.Name -match '(?i)Bluetooth' -and $_.PNPDeviceID } | Select-Object -First 12 | ForEach-Object {
        [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; Type='Bluetooth'; Enabled=$true; PNPDeviceID=[string]$_.PNPDeviceID }
    })
    $network = @($network + $bluetoothExtras | Sort-Object Name,PNPDeviceID -Unique)
    $audio = @($audioRaw | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; PNPDeviceID=[string]$_.PNPDeviceID; Status=[string]$_.Status } })
    $problemDevices = @($problemRaw | ForEach-Object {
        $code = [int]$_.ConfigManagerErrorCode
        $state = if($code -eq 28){'Pilote absent'}elseif([string]$_.Name -match '(?i)unknown device|peripherique inconnu'){'Peripherique inconnu'}else{'Attention'}
        [pscustomobject]@{ Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; PNPDeviceID=[string]$_.PNPDeviceID; HardwareIDs=@($_.HardwareID); ErrorCode=$code; Status=$state }
    })
    $drivers = @($driverRaw | ForEach-Object {
        $driverDate = Convert-AnalysisDate $_.DriverDate
        $ageNotice = 'Correct'
        if ($driverDate) {
            try { if(([datetime]$driverDate) -lt (Get-Date).AddYears(-5)){ $ageNotice='Verification recommandee - une date ancienne ne prouve pas que le pilote est obsolete' } } catch {}
        }
        [pscustomobject]@{ DeviceName=[string]$_.DeviceName; Manufacturer=[string]$_.Manufacturer; Provider=[string]$_.DriverProviderName; DriverVersion=[string]$_.DriverVersion; DriverDate=$driverDate; IsSigned=$_.IsSigned; DeviceID=[string]$_.DeviceID; InfName=[string]$_.InfName; DateIndicator=$ageNotice }
    })
    $unsignedDrivers = @($drivers | Where-Object { $null -ne $_.IsSigned -and -not [bool]$_.IsSigned })
    $collectionErrors = @($script:AnalysisErrors | ForEach-Object { $_ })
    $overallStatus = if ($problemDevices.Count -gt 0) { 'Attention' } else { 'Correct' }

    $report = [ordered]@{
        AnalysisDate=(Get-Date).ToString('o')
        Privacy='Analyse locale. Aucun numero de serie, adresse MAC, adresse IP, mot de passe, cookie ou code d assistance collecte.'
        System=$systemObject
        Motherboard=$motherboardObject
        Processors=$processors
        MemoryModules=$memory
        Graphics=$graphics
        Storage=$storage
        Volumes=$volumes
        Network=$network
        Audio=$audio
        ProblemDevices=$problemDevices
        Drivers=$drivers
        UnsignedDrivers=$unsignedDrivers
        Summary=[pscustomobject]@{
            DetectedDevices=$pnpRaw.Count
            ProblemCount=$problemDevices.Count
            DriverCount=$drivers.Count
            UnsignedDriverCount=$unsignedDrivers.Count
            Status=$overallStatus
        }
        CollectionErrors=$collectionErrors
    }
    Write-AnalysisProgress 96 'Recommandations pilotes' 'Association du matériel aux pages de support officielles...'
    $recommendations = @()
    $recommendationError = ''
    try {
        $driverModule = Join-Path $PSScriptRoot 'Driver-Recommendation-Service.psm1'
        $officialSources = Join-Path $PSScriptRoot 'Official-Sources.json'
        if (-not (Test-Path -LiteralPath $driverModule -PathType Leaf)) { throw 'Module de recommandations de pilotes absent.' }
        if (-not (Test-Path -LiteralPath $officialSources -PathType Leaf)) { throw 'Liste des sources officielles absente.' }
        Import-Module $driverModule -Force -ErrorAction Stop
        $recommendations = @(Get-BastosDriverRecommendations -Report ([pscustomobject]$report) -ConfigPath $officialSources)
    } catch {
        $recommendationError = $_.Exception.Message
        Add-AnalysisError 'Recommandations pilotes' $recommendationError
    }
    $payload = [ordered]@{ Success=$true; Report=$report; Recommendations=$recommendations; RecommendationError=$recommendationError }
    Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success ([bool]$payload.Success) -Message $(if($payload.Success){"Analyse recue."}else{$fatalMessage}) -Data $payload
    Write-AnalysisProgress 100 'Termine' "$($pnpRaw.Count) peripheriques - $($drivers.Count) pilotes - $($problemDevices.Count) problemes"
    exit 0
} catch {
    $fatalMessage = $_.Exception.Message
    $fatalStack = $_.ScriptStackTrace
    try {
        $errorItems = @($script:AnalysisErrors | ForEach-Object { $_ })
        $payload = [ordered]@{ Success=$false; Error=$fatalMessage; Stack=$fatalStack; CollectionErrors=$errorItems }
        Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success ([bool]$payload.Success) -Message $(if($payload.Success){"Analyse recue."}else{$fatalMessage}) -Data $payload
        Write-AnalysisProgress 100 'Erreur' $fatalMessage
    } catch {
        try { [IO.File]::WriteAllText($ResultPath, ("{`"Success`":false,`"Error`":`"" + ($fatalMessage -replace '"','\"') + "`"}"), [Text.UTF8Encoding]::new($false)) } catch {}
    }
    Write-Error "$fatalMessage`n$fatalStack" -ErrorAction Continue
    exit 1
}
