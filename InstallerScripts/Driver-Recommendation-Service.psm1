Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BastosOfficialConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "Configuration des sources officielles introuvable : $Path" }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-BastosHardwareIds {
    param([AllowNull()][string]$Text)
    $result = New-Object Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($match in [regex]::Matches($Text, '(?i)PCI\\VEN_(?<vendor>[0-9A-F]{4})&DEV_(?<device>[0-9A-F]{4})')) {
        $result.Add([pscustomobject]@{ Type='PCI'; VendorId=$match.Groups['vendor'].Value.ToUpperInvariant(); DeviceId=$match.Groups['device'].Value.ToUpperInvariant(); Raw=$match.Value })
    }
    foreach ($match in [regex]::Matches($Text, '(?i)USB\\VID_(?<vendor>[0-9A-F]{4})&PID_(?<device>[0-9A-F]{4})')) {
        $result.Add([pscustomobject]@{ Type='USB'; VendorId=$match.Groups['vendor'].Value.ToUpperInvariant(); DeviceId=$match.Groups['device'].Value.ToUpperInvariant(); Raw=$match.Value })
    }
    return $result.ToArray()
}

function Get-BastosVendor {
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][string]$Manufacturer,
        [AllowNull()][string]$HardwareId
    )
    $combined = "$Manufacturer $Name $HardwareId"
    $map = [ordered]@{
        'AMD'='(?i)AMD|Advanced Micro Devices|VEN_(1002|1022)'
        'NVIDIA'='(?i)NVIDIA|VEN_10DE'
        'Intel'='(?i)Intel|VEN_8086'
        'Realtek'='(?i)Realtek|VEN_10EC|VID_0BDA'
        'Creative'='(?i)Creative|Sound Blaster|VEN_1102|VID_041E'
        'Qualcomm'='(?i)Qualcomm|Atheros|VEN_168C'
        'Broadcom'='(?i)Broadcom|VEN_14E4'
        'Logitech'='(?i)Logitech|VID_046D'
        'Microsoft'='(?i)Microsoft|VID_045E'
        'Kingston'='(?i)Kingston|VID_0951'
        'Samsung'='(?i)Samsung'
        'Corsair'='(?i)Corsair'
        'Crucial'='(?i)Crucial|Micron'
        'Razer'='(?i)Razer|VID_1532'
        'ASUS'='(?i)ASUS|ASUSTeK'
        'MSI'='(?i)Micro-Star|\bMSI\b'
        'Gigabyte'='(?i)Gigabyte'
        'ASRock'='(?i)ASRock'
        'Dell'='(?i)Dell|Alienware'
        'HP'='(?i)Hewlett-Packard|\bHP\b|OMEN'
        'Lenovo'='(?i)Lenovo|ThinkPad|Legion'
        'Acer'='(?i)Acer|Predator'
    }
    foreach ($entry in $map.GetEnumerator()) {
        if ($combined -match $entry.Value) { return $entry.Key }
    }
    return 'Inconnu'
}

function Test-BastosOfficialUrl {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)]$Config
    )
    try { $uri = [Uri]$Url } catch { return $false }
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.IsDefaultPort) { return $false }
    $hostName = $uri.DnsSafeHost.TrimEnd('.').ToLowerInvariant()
    foreach ($domain in @($Config.allowedDomains)) {
        $allowed = ([string]$domain).Trim().TrimStart('.').ToLowerInvariant()
        if ($hostName -eq $allowed -or $hostName.EndsWith(".$allowed", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-BastosComputerClass {
    param(
        [AllowNull()][string]$Manufacturer,
        [AllowNull()][string]$Model,
        [AllowNull()][int[]]$ChassisTypes
    )
    $portableCodes = @(8,9,10,11,12,14,18,21,30,31,32)
    if (@($ChassisTypes | Where-Object { $portableCodes -contains [int]$_ }).Count -gt 0) { return 'Portable' }
    $identity = "$Manufacturer $Model"
    if ($identity -match '(?i)Dell|Alienware|Hewlett-Packard|\bHP\b|Lenovo|ThinkPad|Legion|Acer|Predator|ASUS|ROG|MSI|Micro-Star') {
        return 'Ordinateur de marque'
    }
    if ([string]::IsNullOrWhiteSpace($Manufacturer) -or $identity -match '(?i)System manufacturer|System Product|To Be Filled|Default string|OEM') {
        return 'PC assemble'
    }
    return 'PC assemble'
}

function Find-BastosSource {
    param([AllowNull()][string]$Text, [Parameter(Mandatory)]$Config)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    foreach ($source in @($Config.sources)) {
        foreach ($pattern in @($source.patterns)) {
            if ($Text -match [regex]::Escape([string]$pattern)) { return $source }
        }
    }
    return $null
}

function ConvertTo-BastosComparableModel {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text.ToUpperInvariant() -replace '[^A-Z0-9]+',' ').Trim() -replace '\s+',' ')
}

function ConvertTo-BastosSupportSlug {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = $Text.Trim() -replace '(?i)\s*\(MS-[0-9A-Z-]+\)\s*$',''
    return (($clean -replace '[^A-Za-z0-9]+','-').Trim('-'))
}

function New-BastosBoardModelSource {
    param(
        [AllowNull()][string]$Manufacturer,
        [AllowNull()][string]$Model,
        [AllowNull()][string]$Revision,
        [Parameter(Mandatory)]$Config
    )
    if ([string]::IsNullOrWhiteSpace($Model)) { return $null }
    $vendor = Get-BastosVendor -Name $Model -Manufacturer $Manufacturer -HardwareId ''
    $cleanModel = ($Model.Trim() -replace '(?i)\s*\(MS-[0-9A-Z-]+\)\s*$','').Trim()
    $slug = ConvertTo-BastosSupportSlug $cleanModel
    $encodedModel = [Uri]::EscapeDataString($cleanModel)
    $url = ''
    $sourceName = ''

    switch ($vendor) {
        'MSI' {
            if ($slug) {
                $url = "https://www.msi.com/Motherboard/$slug/support"
                $sourceName = "$cleanModel - pilotes et support MSI"
            }
        }
        'ASUS' {
            if ($encodedModel) {
                $url = "https://www.asus.com/supportonly/$encodedModel/helpdesk_download/"
                $sourceName = "$cleanModel - pilotes et support ASUS"
            }
        }
        'Gigabyte' {
            $revisionMatch = [regex]::Match([string]$Revision, '(?i)(?:rev(?:ision)?[\s.:]*)?(?<revision>\d+(?:\.\d+)+)')
            if ($slug -and $revisionMatch.Success) {
                $revisionSlug = $revisionMatch.Groups['revision'].Value -replace '[^0-9]',''
                $url = "https://www.gigabyte.com/Motherboard/$slug-rev-$revisionSlug/support#support-dl-driver"
                $sourceName = "$cleanModel revision $($revisionMatch.Groups['revision'].Value) - pilotes et support GIGABYTE"
            }
        }
        'ASRock' {
            if ($encodedModel) {
                $url = "https://www.asrock.com/mb/download.asp?Model=$encodedModel"
                $sourceName = "$cleanModel - pilotes et support ASRock"
            }
        }
    }

    if (-not $url -or -not (Test-BastosOfficialUrl -Url $url -Config $Config)) { return $null }
    return [pscustomobject]@{
        key=('DYNAMIC_BOARD_' + $vendor.ToUpperInvariant())
        name=$sourceName
        url=$url
        confidence='Elevee'
        matchType='Modele detecte'
    }
}

function Find-BastosProductSource {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string]$Category,
        [Parameter(Mandatory)]$Config
    )
    $comparableText = ConvertTo-BastosComparableModel $Text
    if (-not $comparableText -or -not $Config.PSObject.Properties['products']) { return $null }
    foreach ($product in @($Config.products)) {
        if ($Category -and @($product.categories).Count -gt 0 -and @($product.categories) -notcontains $Category) { continue }
        foreach ($pattern in @($product.patterns)) {
            $comparablePattern = ConvertTo-BastosComparableModel ([string]$pattern)
            if ($comparablePattern -and $comparableText.Contains($comparablePattern)) {
                return [pscustomobject]@{
                    key=[string]$product.key
                    name=[string]$product.name
                    url=[string]$product.url
                    confidence=$(if($product.confidence){[string]$product.confidence}else{'Elevee'})
                    matchType='Produit exact'
                }
            }
        }
    }
    return $null
}

function New-BastosNvidiaGeForceSource {
    param([AllowNull()][string]$GpuName)
    if ([string]::IsNullOrWhiteSpace($GpuName) -or $GpuName -notmatch '(?i)\bNVIDIA\s+(GeForce|TITAN)\b') { return $null }
    return [pscustomobject]@{
        key='NVIDIA_GEFORCE_SUPPORT'
        name=("{0} - pilotes officiels NVIDIA" -f $GpuName.Trim())
        url='https://www.nvidia.com/fr-fr/drivers/'
        confidence='Moyenne'
        matchType='Fabricant identifie ; modele et Windows a confirmer sur le site'
        resolutionStrategy=''
    }
}

function Resolve-BastosOfficialDownloadUrl {
    param(
        [Parameter(Mandatory)]$Recommendation,
        [Parameter(Mandatory)]$Config,
        [AllowNull()][string]$HtmlOverride,
        [ValidateRange(2,30)][int]$TimeoutSeconds=8
    )
    $originalUrl = [string]$Recommendation.OfficialUrl
    if (-not (Test-BastosOfficialUrl -Url $originalUrl -Config $Config)) {
        throw 'Le lien initial ne figure pas dans la liste blanche officielle.'
    }
    $strategy = if($Recommendation.PSObject.Properties['ResolutionStrategy']){[string]$Recommendation.ResolutionStrategy}else{''}
    if ($strategy -ne 'NVIDIA_LATEST_GEFORCE') {
        return [pscustomobject]@{ OriginalUrl=$originalUrl; FinalUrl=$originalUrl; Resolved=$false; Status='Lien officiel direct' }
    }

    # Old cached recommendations also use the safe selector, never an arbitrary latest driver.
    $safeUrl='https://www.nvidia.com/fr-fr/drivers/'
    if (-not (Test-BastosOfficialUrl -Url $safeUrl -Config $Config)) { throw 'Source NVIDIA non autorisee.' }
    return [pscustomobject]@{ OriginalUrl=$originalUrl; FinalUrl=$safeUrl; Resolved=$false; Status='Selectionne le modele exact et Windows sur le site officiel NVIDIA.' }
}

function Find-BastosInstalledDriver {
    param([array]$Drivers, $Device)
    $pnpId = [string]$Device.PNPDeviceID
    $name = [string]$Device.Name
    if ($pnpId) {
        $match = @($Drivers | Where-Object { [string]$_.DeviceID -eq $pnpId } | Select-Object -First 1)
        if ($match.Count -gt 0) { return $match[0] }
    }
    if ($name) {
        $match = @($Drivers | Where-Object { [string]$_.DeviceName -eq $name } | Select-Object -First 1)
        if ($match.Count -gt 0) { return $match[0] }
    }
    return $null
}

function New-BastosRecommendation {
    param(
        [string]$Category, [string]$Hardware, [string]$Manufacturer,
        [AllowNull()]$Driver, $Source, [string]$Confidence, [string]$Reason,
        [bool]$Sensitive=$false
    )
    if (-not $Source) { return $null }
    return [pscustomobject]@{
        Category=$Category
        Hardware=$Hardware
        Manufacturer=$Manufacturer
        InstalledDriver=$(if ($Driver) { [string]$Driver.DeviceName } else { 'Information indisponible' })
        CurrentVersion=$(if ($Driver -and $Driver.DriverVersion) { [string]$Driver.DriverVersion } else { 'Information indisponible' })
        SourceName=[string]$Source.name
        OfficialUrl=[string]$Source.url
        Confidence=$Confidence
        Reason=$Reason
        SearchTerm=("{0} driver" -f $Hardware).Trim()
        Sensitive=$Sensitive
        MatchType=$(if($Source.PSObject.Properties['matchType']){[string]$Source.matchType}else{'Fabricant ou gamme'})
        ResolutionStrategy=$(if($Source.PSObject.Properties['resolutionStrategy']){[string]$Source.resolutionStrategy}else{''})
    }
}

function Get-BastosDriverInstallOrder {
    param([AllowNull()][string]$Category)
    switch -Regex ($Category) {
        '^Carte mere' { return 10 }
        '^Chipset' { return 20 }
        '^Carte graphique' { return 30 }
        '^Audio' { return 40 }
        '^Reseau' { return 50 }
        '^Stockage' { return 60 }
        '^Peripherique' { return 70 }
        default { return 90 }
    }
}

function Get-BastosDriverRecommendations {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    $config = Get-BastosOfficialConfig -Path $ConfigPath
    $recommendations = New-Object Collections.Generic.List[object]
    $drivers = @($Report.Drivers)
    $system = $Report.System
    $board = $Report.Motherboard
    $class = Get-BastosComputerClass -Manufacturer ([string]$system.Manufacturer) -Model ([string]$system.Model) -ChassisTypes @($system.ChassisTypes)
    $oemSource = Find-BastosSource -Text ("{0} {1}" -f $system.Manufacturer,$system.Model) -Config $config
    $boardRevision = if($board.PSObject.Properties['Revision']){[string]$board.Revision}else{''}
    $boardIdentity = "{0} {1} {2}" -f $board.Manufacturer,$board.Model,$boardRevision
    $boardProductSource = Find-BastosProductSource -Text $boardIdentity -Category 'Carte mere' -Config $config
    $boardModelSource = if ($boardProductSource) { $null } else { New-BastosBoardModelSource -Manufacturer ([string]$board.Manufacturer) -Model ([string]$board.Model) -Revision $boardRevision -Config $config }
    $boardSource = if ($boardProductSource) { $boardProductSource } elseif ($boardModelSource) { $boardModelSource } else { Find-BastosSource -Text $boardIdentity -Config $config }

    if ($boardSource) {
        $boardConfidence = if($boardProductSource){'Elevee'}elseif($class -eq 'PC assemble'){'Elevee'}else{'Moyenne'}
        $boardReason = if($boardProductSource){'Correspondance exacte du modele vers sa page produit et support officielle.'}elseif($boardModelSource){'Le modele detecte est insere dans adresse officielle du fabricant pour ouvrir directement sa page de pilotes.'}else{'Catalogue officiel du fabricant de la carte mere pour reseau, audio, Wi-Fi et Bluetooth; le modele est copie pour faciliter la recherche.'}
        $recommendations.Add((New-BastosRecommendation -Category 'Carte mere' -Hardware ([string]$board.Model) -Manufacturer ([string]$board.Manufacturer) -Driver $null -Source $boardSource -Confidence $boardConfidence -Reason $boardReason))
    }

    $chipsetProductSource = Find-BastosProductSource -Text $boardIdentity -Category 'Chipset' -Config $config
    foreach ($cpu in @($Report.Processors)) {
        $source = if($chipsetProductSource){$chipsetProductSource}elseif($boardModelSource){$boardModelSource}else{Find-BastosSource -Text ("{0} {1}" -f $cpu.Manufacturer,$cpu.Name) -Config $config}
        if ($source) {
            $isAmdB840 = $chipsetProductSource -and [string]$chipsetProductSource.key -eq 'AMD_B840_CHIPSET'
            $chipsetCategory = if($isAmdB840){'Chipset AMD B840 / Ryzen 9800X3D'}elseif($chipsetProductSource -or $boardModelSource){'Chipset - support carte mere'}else{'Chipset'}
            $chipsetReason = if($isAmdB840){'La carte mere B840 est identifiee : cette page AMD affiche directement le dernier pilote chipset et son bouton de telechargement pour Windows 11. Le paquet prend en charge le Ryzen 7 9800X3D.'}elseif($chipsetProductSource -or $boardModelSource){'Modele de carte mere identifie : sa page officielle regroupe le pilote chipset valide pour cette plateforme.'}else{'Pilote chipset depuis le fabricant du processeur lorsque le constructeur du PC ne fournit pas une version imposee.'}
            $recommendations.Add((New-BastosRecommendation -Category $chipsetCategory -Hardware ([string]$cpu.Name) -Manufacturer ([string]$cpu.Manufacturer) -Driver $null -Source $source -Confidence 'Elevee' -Reason $chipsetReason))
        }
    }
    foreach ($gpu in @($Report.Graphics)) {
        $gpuIdentity = "{0} {1} {2}" -f $gpu.Manufacturer,$gpu.Name,$gpu.PNPDeviceID
        $productSource = Find-BastosProductSource -Text $gpuIdentity -Category 'Carte graphique' -Config $config
        $geForceSource = New-BastosNvidiaGeForceSource -GpuName ([string]$gpu.Name)
        $source = if($productSource){$productSource}elseif($geForceSource){$geForceSource}else{Find-BastosSource -Text $gpuIdentity -Config $config}
        $driver = Find-BastosInstalledDriver -Drivers $drivers -Device $gpu
        if ($source) {
            $reason = if($productSource){'Correspondance exacte du GPU vers sa page officielle de pilotes.'}elseif($geForceSource){'GPU NVIDIA detecte : ouverture du selecteur officiel. Confirme le modele exact et la version de Windows ; aucun dernier pilote presume compatible.'}else{'Correspondance par nom, fabricant et identifiant PnP vers le site officiel du GPU.'}
            $recommendations.Add((New-BastosRecommendation -Category 'Carte graphique' -Hardware ([string]$gpu.Name) -Manufacturer ([string]$gpu.Manufacturer) -Driver $driver -Source $source -Confidence $(if($productSource){'Elevee'}else{'Moyenne'}) -Reason $reason))
        }
    }
    foreach ($disk in @($Report.Storage)) {
        $diskIdentity = "{0} {1} {2}" -f $disk.Manufacturer,$disk.Model,$disk.PNPDeviceID
        $productSource = Find-BastosProductSource -Text $diskIdentity -Category 'Stockage / firmware' -Config $config
        $source = if($productSource){$productSource}else{Find-BastosSource -Text $diskIdentity -Config $config}
        if ($source) {
            $confidence = if($productSource){'Elevee'}else{'Moyenne'}
            $reason = if($productSource){'Correspondance exacte du SSD vers sa page de support et de firmware officielle.'}else{'Page de support officielle du fabricant du stockage.'}
            $recommendations.Add((New-BastosRecommendation -Category 'Stockage / firmware' -Hardware ([string]$disk.Model) -Manufacturer ([string]$disk.Manufacturer) -Driver $null -Source $source -Confidence $confidence -Reason $reason))
        }
    }
    foreach ($network in @($Report.Network)) {
        $driver = Find-BastosInstalledDriver -Drivers $drivers -Device $network
        $networkIdentity = "{0} {1} {2} {3} {4}" -f $network.Manufacturer,$network.Name,$network.PNPDeviceID,$(if($driver){$driver.DeviceName}else{''}),$(if($driver){$driver.DeviceID}else{''})
        $productSource = Find-BastosProductSource -Text $networkIdentity -Category 'Reseau' -Config $config
        $componentSource = if($productSource){$productSource}else{Find-BastosSource -Text $networkIdentity -Config $config}
        $source = if($productSource){$productSource}elseif([string]$network.PNPDeviceID -match '^USB\\'){$componentSource}elseif($class -eq 'PC assemble' -and $boardSource){$boardSource}elseif($oemSource){$oemSource}else{$componentSource}
        if ($source) {
            $confidence = if($productSource){'Elevee'}elseif($componentSource -or $boardSource){'Moyenne'}else{'Faible'}
            $reason = if($productSource){'Correspondance du controleur reseau vers sa page officielle de pilotes. Verifie le modele et Windows avant telechargement.'}elseif([string]$network.PNPDeviceID -match '^USB\\'){'Adaptateur USB : support du fabricant de l adaptateur, sans utiliser les pilotes de la carte mere.'}else{'Source officielle du fabricant ou du PC ; correspondance exacte du pilote a confirmer.'}
            $recommendations.Add((New-BastosRecommendation -Category ("Reseau - " + [string]$network.Type) -Hardware ([string]$network.Name) -Manufacturer ([string]$network.Manufacturer) -Driver $driver -Source $source -Confidence $confidence -Reason $reason))
        }
    }
    foreach ($audio in @($Report.Audio)) {
        $driver = Find-BastosInstalledDriver -Drivers $drivers -Device $audio
        $audioIdentity = "{0} {1} {2} {3} {4}" -f $audio.Manufacturer,$audio.Name,$audio.PNPDeviceID,$(if($driver){$driver.DeviceName}else{''}),$(if($driver){$driver.DeviceID}else{''})
        $productSource = Find-BastosProductSource -Text $audioIdentity -Category 'Audio' -Config $config
        $componentSource = if($productSource){$productSource}else{Find-BastosSource -Text $audioIdentity -Config $config}
        $audioVendor = Get-BastosVendor -Name ([string]$audio.Name) -Manufacturer ([string]$audio.Manufacturer) -HardwareId ([string]$audio.PNPDeviceID)
        if (-not $productSource -and ($audioIdentity -match '(?i)Virtual Audio|Voicemod|NVIDIA (High Definition|Virtual) Audio|AMD High Definition Audio|Peripherique audio USB|USB Audio|Peripherique High Definition Audio|High Definition Audio Device')) { continue }
        if (-not $productSource -and $audioVendor -notin @('Creative','Realtek')) { continue }
        $source = if($productSource){$productSource}elseif($audioVendor -eq 'Creative' -and $componentSource){$componentSource}elseif($audioVendor -eq 'Realtek' -and $class -eq 'PC assemble' -and $boardSource){$boardSource}elseif($audioVendor -eq 'Realtek' -and $oemSource){$oemSource}else{$componentSource}
        if ($source) {
            $confidence = if($productSource){'Elevee'}elseif($componentSource){'Moyenne'}else{'Faible'}
            $category = if($productSource -and [string]$productSource.key -match '^CREATIVE_SOUND_BLASTER'){'Audio - Sound Blaster AE-5'}elseif($audioVendor -eq 'Creative'){'Audio - Creative'}else{'Audio - Realtek integre'}
            $reason = if($productSource){'Sound BlasterX AE-5 identifiee exactement : ouverture de sa page Creative officielle regroupant le support et les telechargements encore disponibles.'}elseif($audioVendor -eq 'Creative'){'Peripherique Creative reel identifie; ouverture du support officiel Creative sans le confondre avec Sound Blaster Command pour AE-5.'}else{'Controleur audio Realtek integre identifie; le support exact du PC ou de la carte mere est prioritaire pour son pilote personnalise.'}
            $recommendations.Add((New-BastosRecommendation -Category $category -Hardware ([string]$audio.Name) -Manufacturer ([string]$audio.Manufacturer) -Driver $driver -Source $source -Confidence $confidence -Reason $reason))
        }
    }
    foreach ($problem in @($Report.ProblemDevices)) {
        $source = Find-BastosSource -Text ("{0} {1} {2}" -f $problem.Manufacturer,$problem.Name,$problem.PNPDeviceID) -Config $config
        if (-not $source) { $source = Find-BastosSource -Text 'Microsoft' -Config $config }
        $driver = Find-BastosInstalledDriver -Drivers $drivers -Device $problem
        $recommendations.Add((New-BastosRecommendation -Category 'Peripherique en erreur' -Hardware ([string]$problem.Name) -Manufacturer ([string]$problem.Manufacturer) -Driver $driver -Source $source -Confidence 'Faible' -Reason 'Une erreur est detectee. Verifier le Gestionnaire de peripheriques avant toute installation.'))
    }

    $valid = @($recommendations | Where-Object { $_ -and (Test-BastosOfficialUrl -Url $_.OfficialUrl -Config $config) })
    return @($valid | Sort-Object @{Expression={ Get-BastosDriverInstallOrder -Category ([string]$_.Category) }},Hardware,OfficialUrl -Unique)
}

function Remove-BastosSensitiveLogText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $safe = $Text -replace '(?i)(password|mot de passe|token|jeton|cookie|code temporaire)\s*[:=]\s*\S+', '$1=[DONNEE MASQUEE]'
    $safe = $safe -replace '(?i)C:\\Users\\[^\\\s]+', '%USERPROFILE%'
    $safe = $safe -replace '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[EMAIL MASQUE]'
    if ($safe -match '(?i)assistance|quick assist') { $safe = $safe -replace '(?<!\d)\d{6}(?!\d)', '[CODE MASQUE]' }
    return $safe
}

function ConvertTo-BastosSafeObject {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $output = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '(?i)serial|macaddress|ipaddress|password|token|cookie|assistancecode') { continue }
            $output[[string]$key] = ConvertTo-BastosSafeObject $Value[$key]
        }
        return [pscustomobject]$output
    }
    if ($Value -is [Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { ConvertTo-BastosSafeObject $_ })
    }
    $output = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match '(?i)serial|macaddress|ipaddress|password|token|cookie|assistancecode') { continue }
        $output[$property.Name] = ConvertTo-BastosSafeObject $property.Value
    }
    return [pscustomobject]$output
}

function Export-BastosHardwareReport {
    param(
        [Parameter(Mandatory)]$Report,
        [array]$Recommendations=@(),
        [array]$MaintenanceEvents=@(),
        [Parameter(Mandatory)][string]$Path
    )
    $safeEvents = @($MaintenanceEvents | ForEach-Object { Remove-BastosSensitiveLogText ([string]$_) })
    $payload = [ordered]@{
        ExportedAt=(Get-Date).ToString('o')
        Privacy='Rapport local sans numero de serie, adresse MAC, adresse IP, mot de passe, cookie ni code temporaire.'
        Hardware=ConvertTo-BastosSafeObject $Report
        Recommendations=ConvertTo-BastosSafeObject $Recommendations
        MaintenanceEvents=$safeEvents
    }
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.json') {
        [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($true))
        return $Path
    }
    if ($extension -ne '.html' -and $extension -ne '.htm') { throw 'Format de rapport non pris en charge. Choisir HTML ou JSON.' }
    $encoder = [Net.WebUtility]
    $hardwareJson = $encoder::HtmlEncode(($payload.Hardware | ConvertTo-Json -Depth 16))
    $rows = @($Recommendations | Select-Object Category,Hardware,Manufacturer,CurrentVersion,SourceName,Confidence,Reason)
    $recommendationHtml = if ($rows.Count -gt 0) { $rows | ConvertTo-Html -Fragment } else { '<p>Aucune recommandation disponible.</p>' }
    $eventHtml = if ($safeEvents.Count -gt 0) { '<ul>' + (($safeEvents | ForEach-Object { '<li>' + $encoder::HtmlEncode($_) + '</li>' }) -join '') + '</ul>' } else { '<p>Aucune operation de maintenance enregistree.</p>' }
    $html = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Rapport BASTOS</title>
<style>body{font-family:Segoe UI,Arial;background:#090a12;color:#f2f2f6;margin:32px}h1,h2{color:#45c8ff}pre,table{background:#11121c;border:1px solid #282a3a;padding:16px;overflow:auto}table{border-collapse:collapse;width:100%}th,td{border:1px solid #282a3a;padding:8px;text-align:left}th{color:#45c8ff}</style></head>
<body><h1>Rapport local BASTOS</h1><p>Exporte le $($payload.ExportedAt)</p><p>$($payload.Privacy)</p>
<h2>Inventaire materiel et pilotes</h2><pre>$hardwareJson</pre>
<h2>Pilotes officiels recommandes</h2>$recommendationHtml
<h2>Operations de maintenance</h2>$eventHtml</body></html>
"@
    [IO.File]::WriteAllText($Path, $html, [Text.UTF8Encoding]::new($true))
    return $Path
}

Export-ModuleMember -Function Get-BastosOfficialConfig,Get-BastosHardwareIds,Get-BastosVendor,Test-BastosOfficialUrl,Get-BastosComputerClass,Get-BastosDriverRecommendations,Resolve-BastosOfficialDownloadUrl,New-BastosBoardModelSource,Remove-BastosSensitiveLogText,ConvertTo-BastosSafeObject,Export-BastosHardwareReport
