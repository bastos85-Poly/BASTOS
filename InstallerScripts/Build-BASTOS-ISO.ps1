[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SourceIso,

    [Parameter(Mandatory = $true)]
    [string]$OutputIso,

    [ValidateRange(0, 99)]
    [int]$EditionIndex = 0,

    [string]$EditionPattern = '*Windows 11*Pro*',

    [string]$WorkRoot = 'C:\PUBGISO-Work',

    [ValidateNotNullOrEmpty()]
    [ValidateSet('Administrator','BastOS')]
    [string]$LocalUserName = 'BastOS',

    [ValidatePattern('^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$')]
    [string]$KeyboardLayout,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'de-DE','en-US','en-GB','ar-SA','bg-BG','zh-CN','zh-TW','ko-KR','hr-HR','da-DK',
        'es-ES','es-MX','et-EE','fi-FI','fr-FR','fr-CA','el-GR','he-IL','hu-HU','it-IT',
        'ja-JP','lv-LV','lt-LT','nl-NL','nb-NO','pl-PL','pt-PT','pt-BR','ro-RO','ru-RU',
        'sr-Latn-RS','sk-SK','sl-SI','sv-SE','cs-CZ','th-TH','tr-TR','uk-UA'
    )]
    [string]$WindowsLocale = 'fr-FR',

    [ValidateSet('None','Edge','Chrome','Brave','Firefox','FirefoxNightly','Opera','Vivaldi')]
    [string]$BrowserId = 'None',

    [string]$RemoveListPath,

    [string]$RemovalOptionsPath,

    [string]$ProgressPath,

    [string]$ResultPath,

    [string]$OperationId = '',

    [string]$AdkEvidencePath = '',

    [string]$CancellationPath,

    [switch]$Force,
    [switch]$KeepWorkFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.Cancellation.psm1') -Force -ErrorAction Stop
$script:CancellationCleanupVerified=$false
$script:CancellationCleanupFailed=$false
Import-Module (Join-Path $PSScriptRoot 'Bastos.Deployment.psm1') -Force -ErrorAction Stop
$script:BuildEvidence = @{}

# Le chemin des modules peut contenir PowerShell 7 avant Windows PowerShell.
# Charger explicitement la version native pour verifier les signatures Microsoft.
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$script:CurrentBuildPhase = 'Initialisation'
$script:CurrentBuildMessage = 'Demarrage du constructeur ISO.'
$script:CurrentBuildStep = 0
$script:CurrentBuildTotalSteps = 7
$script:BuildResultWritten = $false

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ouvre Windows PowerShell en tant qu''administrateur, puis relance la commande.'
    }
}

function Write-BuildProgress {
    param([int]$Percent, [string]$Phase, [string]$Message, [int]$Step, [int]$TotalSteps=7)
    $script:CurrentBuildPhase = $Phase
    $script:CurrentBuildMessage = $Message
    $script:CurrentBuildStep = $Step
    $script:CurrentBuildTotalSteps = $TotalSteps
    Write-Host ("[{0}%] {1} - {2}" -f $Percent,$Phase,$Message)
    try { Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message -Step $Step -TotalSteps $TotalSteps } catch {}
}

function Save-BuildResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][bool]$Cancelled,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Message,
        [string]$Detail = ''
    )
    if (-not $ResultPath) { return }
    try {
        $report = [ordered]@{
            Success = $Success
            Cancelled = $Cancelled
            CancellationScope = 'IsoBuildCheckpoint'
            CancellationCleanupVerified = ($Cancelled -and $script:CancellationCleanupVerified)
            ErrorCode = $(if($script:CancellationCleanupFailed){'CANCELLATION_CLEANUP_UNCONFIRMED'}else{''})
            ExitCode = $ExitCode
            Phase = $script:CurrentBuildPhase
            Message = $Message
            ProgressMessage = $script:CurrentBuildMessage
            Step = $script:CurrentBuildStep
            TotalSteps = $script:CurrentBuildTotalSteps
            OutputIso = $OutputIso
            TimestampUtc = [DateTime]::UtcNow.ToString('o')
            Detail = $Detail
        }
        foreach($key in $script:BuildEvidence.Keys){$report[$key]=$script:BuildEvidence[$key]}
        Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $Success -Message $Message -Data $report
        $script:BuildResultWritten = $true
    } catch {
        Write-Warning "Le rapport de construction ISO n a pas pu etre enregistre : $($_.Exception.Message)"
    }
}

function Get-NativeOutputTail {
    param([object[]]$Output,[int]$MaximumCharacters=2400)
    $text = (@($Output | ForEach-Object { [string]$_ }) -join "`r`n").Trim()
    if ($text.Length -gt $MaximumCharacters) { return $text.Substring($text.Length - $MaximumCharacters) }
    return $text
}

function Get-WimImagesFromEmbeddedXml {
    param([Parameter(Mandatory)][string]$ImagePath)
    $stream = $null
    try {
        $stream = [IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $tailLength = [int][Math]::Min([int64](32MB),$stream.Length)
        $null = $stream.Seek(-$tailLength,[IO.SeekOrigin]::End)
        $buffer = New-Object byte[] $tailLength
        $read = $stream.Read($buffer,0,$tailLength)
        if ($read -le 0) { throw 'Metadonnees WIM illisibles.' }
        $text = [Text.Encoding]::Unicode.GetString($buffer,0,$read)
        $start = $text.LastIndexOf('<?xml',[StringComparison]::OrdinalIgnoreCase)
        if ($start -lt 0) { $start = $text.LastIndexOf('<WIM>',[StringComparison]::OrdinalIgnoreCase) }
        $end = $text.LastIndexOf('</WIM>',[StringComparison]::OrdinalIgnoreCase)
        if ($start -lt 0 -or $end -lt $start) { throw 'Bloc XML WIM introuvable.' }
        [xml]$metadata = $text.Substring($start,($end + 6) - $start)
        $images = @(
            foreach ($node in @($metadata.WIM.IMAGE)) {
                $indexText = $node.GetAttribute('INDEX')
                $nameText = [string]$node.NAME
                if ($indexText -match '^\d+$' -and -not [string]::IsNullOrWhiteSpace($nameText)) {
                    [pscustomobject]@{
                        ImageIndex = [int]$indexText
                        ImageName = $nameText.Trim()
                        DisplayName = ([string]$node.DISPLAYNAME).Trim()
                        EditionId = ([string]$node.WINDOWS.EDITIONID).Trim()
                        Flags = ([string]$node.FLAGS).Trim()
                    }
                }
            }
        )
        if ($images.Count -eq 0) { throw 'Aucune edition Windows dans les metadonnees WIM.' }
        return $images
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-BastosWindowsImages {
    param([Parameter(Mandatory)][string]$ImagePath)
    $xmlError = ''
    try {
        $xmlImages = @(Get-WimImagesFromEmbeddedXml -ImagePath $ImagePath)
        if ($xmlImages.Count -gt 0) {
            Write-Host "Metadonnees WIM canoniques lues : $($xmlImages.Count) editions."
            return $xmlImages
        }
    } catch {
        $xmlError = $_.Exception.Message
    }

    $cmdletError = ''
    try {
        $images = @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop)
        if ($images.Count -gt 0) { return $images }
        $cmdletError = 'Get-WindowsImage n a retourne aucune edition.'
    } catch {
        $cmdletError = $_.Exception.Message
    }

    $dismOutput = @()
    $dismExitCode = -1
    try {
        $dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
        $dismOutput = @(& $dismPath '/English' '/Get-WimInfo' "/WimFile:$ImagePath" 2>&1)
        $dismExitCode = $LASTEXITCODE
        if ($dismExitCode -eq 0) {
            $parsed = New-Object Collections.Generic.List[object]
            $currentIndex = 0
            foreach ($line in $dismOutput) {
                $lineText = [string]$line
                if ($lineText -match '^\s*Index\s*:\s*(\d+)\s*$') {
                    $currentIndex = [int]$matches[1]
                } elseif ($currentIndex -gt 0 -and $lineText -match '^\s*Name\s*:\s*(.+?)\s*$') {
                    $parsed.Add([pscustomobject]@{ ImageIndex=$currentIndex; ImageName=$matches[1].Trim() })
                    $currentIndex = 0
                }
            }
            if ($parsed.Count -gt 0) {
                Write-Warning "Get-WindowsImage a echoue; lecture des editions reprise avec DISM.exe : $cmdletError"
                return @($parsed)
            }
        }
    } catch {
        $dismOutput += $_.Exception.Message
    }

    $dismDetail = Get-NativeOutputTail -Output $dismOutput
    throw "Lecture des editions Windows impossible. Get-WindowsImage : $cmdletError | DISM.exe (code $dismExitCode) : $dismDetail | Metadonnees WIM : $xmlError"
}

function Select-BastosWindowsEdition {
    param(
        [Parameter(Mandatory)][object[]]$Images,
        [int]$RequestedIndex = 0,
        [string]$RequestedPattern = '*Windows 11*Pro*'
    )
    if ($Images.Count -eq 0) { throw 'Aucune edition Windows disponible dans image source.' }
    if ($RequestedIndex -gt 0) {
        $indexed = $Images | Where-Object { [int]$_.ImageIndex -eq $RequestedIndex } | Select-Object -First 1
        if (-not $indexed) { throw "Index d edition introuvable : $RequestedIndex" }
        return $indexed
    }

    $internalMatches = @($Images | Where-Object {
        $editionProperty = $_.PSObject.Properties['EditionId']
        $editionProperty -and [string]$editionProperty.Value -eq 'Professional'
    })
    if ($internalMatches.Count -eq 1) { return $internalMatches[0] }
    if ($internalMatches.Count -gt 1) {
        throw 'Metadonnees WIM invalides : plusieurs images portent identifiant Microsoft Professional.'
    }

    $exactNameMatches = @($Images | Where-Object { [string]$_.ImageName -match '(?i)^Windows\s*11\s+(?:Pro|Professionnel)$' })
    if ($exactNameMatches.Count -eq 1) { return $exactNameMatches[0] }

    $patternMatches = @($Images | Where-Object {
        [string]$_.ImageName -like $RequestedPattern -and
        [string]$_.ImageName -notmatch '(?i)\bN\b|Education|[ÉE]ducation|Workstations?|Stations?\s+de\s+travail'
    })
    if ($patternMatches.Count -eq 1) { return $patternMatches[0] }

    $editionSummary = @($Images | ForEach-Object {
        $editionProperty = $_.PSObject.Properties['EditionId']
        $editionId = if($editionProperty){[string]$editionProperty.Value}else{'identifiant absent'}
        "index $($_.ImageIndex) : $($_.ImageName) [$editionId]"
    }) -join ' | '
    throw "Edition Windows 11 Pro standard introuvable ou ambigue. Editions detectees : $editionSummary"
}

function Export-BastosWindowsImage {
    param(
        [Parameter(Mandatory)][string]$SourceImagePath,
        [Parameter(Mandatory)][int]$SourceIndex,
        [Parameter(Mandatory)][string]$DestinationImagePath
    )
    $cmdletError = ''
    try {
        Export-WindowsImage -SourceImagePath $SourceImagePath -SourceIndex $SourceIndex -DestinationImagePath $DestinationImagePath -CompressionType Max -CheckIntegrity -ErrorAction Stop | Out-Null
        return
    } catch {
        $cmdletError = $_.Exception.Message
        Remove-Item -LiteralPath $DestinationImagePath -Force -ErrorAction SilentlyContinue
    }
    $dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
    $dismOutput = @(& $dismPath '/English' '/Export-Image' "/SourceImageFile:$SourceImagePath" "/SourceIndex:$SourceIndex" "/DestinationImageFile:$DestinationImagePath" '/Compress:max' '/CheckIntegrity' 2>&1)
    $dismExitCode = $LASTEXITCODE
    if ($dismExitCode -eq 0 -and (Test-Path -LiteralPath $DestinationImagePath -PathType Leaf)) {
        Write-Warning "Export-WindowsImage a echoue; export termine avec DISM.exe : $cmdletError"
        return
    }
    Remove-Item -LiteralPath $DestinationImagePath -Force -ErrorAction SilentlyContinue
    $dismDetail = Get-NativeOutputTail -Output $dismOutput
    throw "Extraction de Windows 11 Pro impossible. Export-WindowsImage : $cmdletError | DISM.exe (code $dismExitCode) : $dismDetail. Verifie ou retelecharge ISO officielle si DISM signale une image endommagee."
}

function Assert-MicrosoftSignedFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Description)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description introuvable : $Path" }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $microsoftRetailSignature = $signature.Status -eq 'Valid' -and $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match '(?i)Microsoft'
    $microsoftInsiderSignature = $false
    if (-not $microsoftRetailSignature -and $signature.Status -eq 'UnknownError' -and
        $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match '(?i)^CN=Microsoft Corporation,' -and
        $signature.SignerCertificate.Issuer -match '(?i)^CN=Microsoft Development PCA 2014,' -and
        $signature.StatusMessage -match '(?i)(racine.+(pas|non).+approuv|root.+not trusted|untrusted root)') {
        # Les ISO officielles Insider utilisent la racine de developpement
        # Microsoft, volontairement absente du magasin public Windows. Autoriser
        # uniquement cette chaine si elle est cryptographiquement coherente et
        # aboutit a l empreinte connue de Microsoft Development Root CA 2014.
        $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
        try {
            $chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chainBuilt = $chain.Build($signature.SignerCertificate)
            $root = if($chain.ChainElements.Count -gt 0){$chain.ChainElements[$chain.ChainElements.Count-1].Certificate}else{$null}
            $microsoftInsiderSignature = $chainBuilt -and $root -and
                $root.Subject -match '(?i)^CN=Microsoft Development Root Certificate Authority 2014,' -and
                $root.Thumbprint -eq 'F8DB7E1C16F1FFD4AAAD4AAD8DFF0F2445184AEB'
        } finally {
            $chain.Dispose()
        }
    }
    if (-not $microsoftRetailSignature -and -not $microsoftInsiderSignature) {
        throw "$Description refuse : signature Microsoft invalide ou absente ($($signature.Status))."
    }
}

function Find-Oscdimg {
    $evidence=Assert-BastosAdkEvidence -EvidencePath $AdkEvidencePath
    return [string]$evidence.Oscdimg
}
function Test-SafeBuildDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($fullPath.Length -le ($fullRoot.Length + 10) -or -not $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refus de nettoyer un chemin de travail non sur : $fullPath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $fullPath '.pubgiso-build-marker'))) {
        throw "Marqueur de securite absent dans : $fullPath"
    }
}

function Test-BuildPathInsideRoot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-MountedWindowsImagePath {
    param([Parameter(Mandatory)]$Image)
    foreach ($propertyName in @('Path','MountPath')) {
        $property = $Image.PSObject.Properties[$propertyName]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { return [string]$property.Value }
    }
    return ''
}

function Repair-BastosStaleBuilds {
    param([Parameter(Mandatory)][string]$Root)
    $staleBuilds = @(Get-ChildItem -LiteralPath $Root -Directory -Filter 'build-*' -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^build-[a-f0-9]{32}$' -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName '.pubgiso-build-marker') -PathType Leaf)
    })
    if ($staleBuilds.Count -eq 0) { return }

    $mountedImages = @(Get-WindowsImage -Mounted -ErrorAction Stop)
    foreach ($staleBuild in $staleBuilds) {
        Test-SafeBuildDirectory -Path $staleBuild.FullName -Root $Root
        foreach ($mountedImage in $mountedImages) {
            $mountedPath = Get-MountedWindowsImagePath -Image $mountedImage
            if ($mountedPath -and (Test-BuildPathInsideRoot -Path $mountedPath -Root $staleBuild.FullName)) {
                Write-Host "Recuperation du montage BASTOS interrompu : $mountedPath"
                Dismount-WindowsImage -Path $mountedPath -Discard -ErrorAction Stop | Out-Null
            }
        }
        $remaining = @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object {
            $candidatePath = Get-MountedWindowsImagePath -Image $_
            $candidatePath -and (Test-BuildPathInsideRoot -Path $candidatePath -Root $staleBuild.FullName)
        })
        if ($remaining.Count -gt 0) { throw "Le montage BASTOS interrompu ne peut pas etre recupere : $($staleBuild.FullName)" }
        Remove-Item -LiteralPath $staleBuild.FullName -Recurse -Force
        Write-Host "Ancien dossier de construction BASTOS nettoye : $($staleBuild.FullName)"
    }
}

function Get-PathDriveInfo {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($root -notmatch '^[A-Za-z]:\\$') { throw "Chemin local sur volume Windows requis : $Path" }
    $drive = Get-PSDrive -Name $root.Substring(0,1) -PSProvider FileSystem -ErrorAction Stop
    return [pscustomobject]@{ Root=$root.ToUpperInvariant(); Free=[int64]$drive.Free }
}

function Assert-BuildFreeSpace {
    param(
        [Parameter(Mandatory)][string]$WorkPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$SourceIsoPath,
        [string]$OutputFilePath,
        [switch]$ReplacingExistingOutput
    )
    $workDrive = Get-PathDriveInfo -Path $WorkPath
    $outputDrive = Get-PathDriveInfo -Path $OutputPath
    $workRequired = 30GB
    if ($workDrive.Free -lt $workRequired) {
        throw ('Espace insuffisant sur {0} : {1:N1} Go libres, 30 Go requis pour la construction.' -f $workDrive.Root,($workDrive.Free / 1GB))
    }
    $replaceableBytes = [int64]0
    if ($ReplacingExistingOutput -and $OutputFilePath -and (Test-Path -LiteralPath $OutputFilePath -PathType Leaf)) {
        $replaceableBytes = [int64](Get-Item -LiteralPath $OutputFilePath -Force).Length
    }
    $effectiveOutputFree = [int64]$outputDrive.Free + $replaceableBytes
    # Une ISO BASTOS ne conserve qu une edition Windows et est normalement plus
    # petite que la source multi-editions. Garder 256 Mo de marge evite de
    # refuser a tort un volume qui peut reellement recevoir le fichier final.
    $sourceIsoLength = [int64](Get-Item -LiteralPath $SourceIsoPath -Force).Length
    $outputRequired = $sourceIsoLength + 256MB
    if ($outputDrive.Root -ne $workDrive.Root -and $effectiveOutputFree -lt $outputRequired) {
        throw ('Espace insuffisant sur {0} : {1:N1} Go utilisables, {2:N1} Go requis pour cette ISO.' -f $outputDrive.Root,($effectiveOutputFree / 1GB),($outputRequired / 1GB))
    }
    Write-Host ('Espace disque valide : {0:N1} Go libres sur {1}.' -f ($workDrive.Free / 1GB),$workDrive.Root)
    if ($outputDrive.Root -ne $workDrive.Root) {
        Write-Host ('Sortie ISO : {0:N1} Go utilisables sur {1} ({2:N1} Go recuperes lors du remplacement).' -f ($effectiveOutputFree / 1GB),$outputDrive.Root,($replaceableBytes / 1GB))
    }
}

function Assert-BuildNotCancelled {
    param([Parameter(Mandatory)][string]$Phase,[int]$Step=0)
    if ($CancellationPath -and (Test-Path -LiteralPath $CancellationPath -PathType Leaf)) {
        Write-BuildProgress 0 'Annulation' "Demande recue apres : $Phase. Recuperation des montages..." $Step
        throw ([System.OperationCanceledException]::new('Construction ISO annulee proprement a la demande de utilisateur.'))
    }
}

function Assert-SafeLocalUserName {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -cne 'BastOS') { throw 'BASTOS utilise exclusivement le compte local administrateur BastOS sans mot de passe.' }
}

# Capture aussi les erreurs des controles preliminaires. Auparavant, ces erreurs
# survenaient avant le bloc try principal et l interface ne recevait que
# "etape inconnue".
trap {
    $uncaughtMessage = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { [string]$_ }
    if (-not $script:BuildResultWritten) {
        $uncaughtDetail = (@($_.InvocationInfo.PositionMessage,$_.ScriptStackTrace) | Where-Object { $_ }) -join "`r`n"
        Save-BuildResult -Success $false -Cancelled $false -ExitCode 1 -Message $uncaughtMessage -Detail $uncaughtDetail
    }
    [Console]::Error.WriteLine($uncaughtMessage)
    exit 1
}

Assert-Administrator
$LocalUserName = 'BastOS'
$localDisplayName = 'BastOS'
Assert-SafeLocalUserName -Name $LocalUserName
$browserCatalog = @{
    None=[pscustomobject]@{ Id='None'; DisplayName='Aucun navigateur'; WingetId=''; OfficialUri=''; RemoveEdge=$false }
    Edge=[pscustomobject]@{ Id='Edge'; DisplayName='Microsoft Edge'; WingetId='Microsoft.Edge'; OfficialUri='https://www.microsoft.com/edge' }
    Chrome=[pscustomobject]@{ Id='Chrome'; DisplayName='Google Chrome'; WingetId='Google.Chrome'; OfficialUri='https://www.google.com/chrome/' }
    Brave=[pscustomobject]@{ Id='Brave'; DisplayName='Brave'; WingetId='Brave.Brave'; OfficialUri='https://brave.com/download/' }
    Firefox=[pscustomobject]@{ Id='Firefox'; DisplayName='Mozilla Firefox'; WingetId='Mozilla.Firefox'; OfficialUri='https://www.mozilla.org/firefox/new/' }
    FirefoxNightly=[pscustomobject]@{ Id='FirefoxNightly'; DisplayName='Mozilla Firefox Nightly'; WingetId='Mozilla.Firefox.Nightly.MSIX'; OfficialUri='https://nightly.mozfr.org/' }
    Opera=[pscustomobject]@{ Id='Opera'; DisplayName='Opera'; WingetId='Opera.Opera'; OfficialUri='https://www.opera.com/download' }
    Vivaldi=[pscustomobject]@{ Id='Vivaldi'; DisplayName='Vivaldi'; WingetId='Vivaldi.Vivaldi'; OfficialUri='https://vivaldi.com/download/' }
}
$selectedBrowser = $browserCatalog[$BrowserId]
if (-not $selectedBrowser) { throw "Navigateur BASTOS inconnu : $BrowserId" }
$kitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$payloadCandidate = Join-Path $kitRoot 'Payload'
$payloadRoot = if (Test-Path -LiteralPath $payloadCandidate -PathType Container) { $payloadCandidate } else { $kitRoot }
$answerTemplateFile = Join-Path $kitRoot 'autounattend.xml'
$defaultRemoveListFile = Join-Path $kitRoot 'Remove-Appx.txt'
$winreIntegrationFile = Join-Path $kitRoot 'Integrate-WinRE-Into-BASTOS.ps1'

foreach ($required in @($payloadRoot, $answerTemplateFile, $defaultRemoveListFile, $winreIntegrationFile)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Fichier requis absent : $required" }
}
$protectedAppxDisplayNames = @(
    # Mobile connecte / Votre telephone doit rester dans toutes les ISO BASTOS.
    'Microsoft.YourPhone'
)
$removeListFile = $defaultRemoveListFile
$removeNames = @(Get-Content -LiteralPath $defaultRemoveListFile | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -notin $protectedAppxDisplayNames } |
    Select-Object -Unique)
if ($RemoveListPath) {
    if (-not (Test-Path -LiteralPath $RemoveListPath -PathType Leaf)) { throw "Liste personnalisee introuvable : $RemoveListPath" }
    $removeListFile = (Resolve-Path -LiteralPath $RemoveListPath).Path
    $allowedNames = @($removeNames)
    $requestedNames = @(Get-Content -LiteralPath $removeListFile | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -notin $protectedAppxDisplayNames } |
        Select-Object -Unique)
    $unknownNames = @($requestedNames | Where-Object { $_ -notin $allowedNames })
    if ($unknownNames.Count -gt 0) { throw "La liste personnalisee contient des applications non autorisees : $($unknownNames -join ', ')" }
    $removeNames = @($requestedNames)
}
$removalOptions = [ordered]@{ RemoveOneDrive = $true; DisableConsumerContent = $true }
if ($RemovalOptionsPath) {
    if (-not (Test-Path -LiteralPath $RemovalOptionsPath -PathType Leaf)) { throw "Options de suppression introuvables : $RemovalOptionsPath" }
    $requestedOptions = Get-Content -LiteralPath $RemovalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @('RemoveOneDrive','DisableConsumerContent')) {
        if (-not $requestedOptions.PSObject.Properties[$name] -or $requestedOptions.$name -isnot [bool]) {
            throw "Option de suppression invalide : $name"
        }
        $removalOptions[$name] = [bool]$requestedOptions.$name
    }
}

$sourceIsoPath = (Resolve-Path -LiteralPath $SourceIso).Path
$outputIsoPath = [IO.Path]::GetFullPath($OutputIso)
if ([IO.Path]::GetExtension($outputIsoPath) -ne '.iso') { throw 'OutputIso doit se terminer par .iso.' }
if ($sourceIsoPath.Equals($outputIsoPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'La source ISO et la sortie ISO doivent etre deux fichiers differents.' }
if ((Test-Path -LiteralPath $outputIsoPath) -and -not $Force) {
    throw "Le fichier existe deja : $outputIsoPath. Ajoute -Force pour le remplacer."
}

$outputParent = Split-Path -Parent $outputIsoPath
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
Assert-BuildFreeSpace -WorkPath $WorkRoot -OutputPath $outputParent -SourceIsoPath $sourceIsoPath -OutputFilePath $outputIsoPath -ReplacingExistingOutput:$Force
Repair-BastosStaleBuilds -Root $WorkRoot
$oscdimg = Find-Oscdimg

$buildId = 'build-' + [guid]::NewGuid().ToString('N')
$buildDir = Join-Path $WorkRoot $buildId
$mediaDir = Join-Path $buildDir 'Media'
$mountDir = Join-Path $buildDir 'Mount'
New-Item -ItemType Directory -Path $mediaDir, $mountDir -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $buildDir '.pubgiso-build-marker') -Force | Out-Null
$answerFile = Join-Path $buildDir 'autounattend.xml'
$answerTemplate = Get-Content -LiteralPath $answerTemplateFile -Raw -Encoding UTF8
if ($answerTemplate -notmatch '__BASTOS_USERNAME__') { throw 'Le modele autounattend.xml ne contient pas le marqueur de compte BASTOS.' }
if (@([regex]::Matches($answerTemplate,'__BASTOS_INPUT_LOCALE__')).Count -ne 2) { throw 'Le modele autounattend.xml doit contenir exactement deux marqueurs de clavier BASTOS.' }
if (@([regex]::Matches($answerTemplate,'__BASTOS_WINDOWS_LOCALE__')).Count -ne 7) { throw 'Le modele autounattend.xml doit contenir exactement sept marqueurs de langue BASTOS.' }
$computerName = ([string]$env:COMPUTERNAME).Trim().ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($computerName) -or $computerName.Length -gt 15 -or $computerName -match '[^A-Z0-9-]' -or $computerName -notmatch '[A-Z]' -or $computerName -like 'MININT-*' -or $computerName -match '(?i)KernelOS|KernelPan|KRNLGame|KOS[ -]?Post') {
    $computerName = 'BASTOS-' + [guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()
}
if (@([regex]::Matches($answerTemplate,'__BASTOS_COMPUTER_NAME__')).Count -ne 2) { throw 'Le modele autounattend.xml doit contenir exactement deux references au nom de machine BASTOS.' }
$escapedUserName = [Security.SecurityElement]::Escape($LocalUserName)
$answerContent = $answerTemplate.Replace('__BASTOS_USERNAME__', $escapedUserName).Replace('__BASTOS_INPUT_LOCALE__', $KeyboardLayout).Replace('__BASTOS_WINDOWS_LOCALE__', $WindowsLocale).Replace('__BASTOS_COMPUTER_NAME__', $computerName)
if ($answerContent -match '__BASTOS_[A-Z_]+__') { throw 'Le fichier de reponse genere contient encore un marqueur BASTOS non remplace.' }
try { [xml]$generatedAnswer = $answerContent } catch { throw "Le fichier de reponse genere est invalide : $($_.Exception.Message)" }
$answerNs = [Xml.XmlNamespaceManager]::new($generatedAnswer.NameTable)
$answerNs.AddNamespace('u','urn:schemas-microsoft-com:unattend')
$specializeCommands = @($generatedAnswer.SelectNodes('//u:settings[@pass="specialize"]//u:RunSynchronousCommand',$answerNs))
$answerComputerName=$generatedAnswer.SelectSingleNode('//u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:ComputerName',$answerNs)
if($specializeCommands.Count -ne 0 -or -not $answerComputerName -or $answerComputerName.InnerText -ne $computerName){
    throw 'Le modele autounattend doit figer le nom de machine sans commande de compte pendant specialize.'
}
$answerLocalAccounts=@($generatedAnswer.SelectNodes('//u:settings[@pass="oobeSystem"]//u:LocalAccount',$answerNs))
$answerLocalPassword=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccount/u:Password/u:Value',$answerNs)
$answerLocalName=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccount/u:Name',$answerNs)
$answerLocalDisplayName=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccount/u:DisplayName',$answerNs)
$answerInput=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:InputLocale',$answerNs)
$answerLanguage=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UILanguage',$answerNs)
$hideOnline=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideOnlineAccountScreens',$answerNs)
$hideLocal=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideLocalAccountScreen',$answerNs)
$hideWireless=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideWirelessSetupInOOBE',$answerNs)
$answerAutoLogon=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon',$answerNs)
$answerAutoLogonPassword=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Password/u:Value',$answerNs)
$answerAutoLogonDomain=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Domain',$answerNs)
$answerAutoLogonUsername=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Username',$answerNs)
$answerAutoLogonEnabled=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Enabled',$answerNs)
$answerAutoLogonCount=$generatedAnswer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:LogonCount',$answerNs)
if($answerLocalAccounts.Count -ne 1 -or -not $answerLocalPassword -or $answerLocalPassword.InnerText -ne '' -or -not $answerLocalName -or $answerLocalName.InnerText -cne $LocalUserName -or -not $answerLocalDisplayName -or $answerLocalDisplayName.InnerText -cne $localDisplayName){throw 'Le compte local BastOS sans mot de passe n est pas verrouille dans le fichier de reponses.'}
if(-not $answerInput -or $answerInput.InnerText -ne $KeyboardLayout){throw 'Le clavier choisi n est pas verrouille dans le fichier de reponses.'}
if(-not $answerLanguage -or $answerLanguage.InnerText -ne $WindowsLocale){throw 'La langue choisie n est pas verrouillee dans le fichier de reponses.'}
if(-not $hideOnline -or $hideOnline.InnerText -ne 'true' -or -not $hideLocal -or $hideLocal.InnerText -ne 'true' -or -not $hideWireless -or $hideWireless.InnerText -ne 'true'){throw 'Le fichier de reponses ne garantit pas un OOBE sans interaction reseau ou compte Microsoft.'}
if(-not $answerAutoLogon -or -not $answerAutoLogonPassword -or $answerAutoLogonPassword.InnerText -ne '' -or
   -not $answerAutoLogonUsername -or $answerAutoLogonUsername.InnerText -cne $LocalUserName -or
   -not $answerAutoLogonEnabled -or $answerAutoLogonEnabled.InnerText -ne 'true' -or
   -not $answerAutoLogonCount -or $answerAutoLogonCount.InnerText -ne '1' -or
   -not $answerAutoLogonDomain -or $answerAutoLogonDomain.InnerText -cne $computerName -or $answerAutoLogonDomain.InnerText -eq '.'){
    throw 'Le fichier de reponses doit configurer AutoLogon pour BastOS avec le domaine local egal au nom de machine.'
}
[IO.File]::WriteAllText($answerFile, $answerContent, [Text.UTF8Encoding]::new($false))

$diskImage = $null
$wimMounted = $false
$verificationDiskImage = $null
$buildCancelled = $false
$outputTouched = $false
$deleteFailedOutput = $false
$shortNameRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$shortNameOriginal = $null
$shortNameAdjusted = $false
try {
    Assert-BuildNotCancelled -Phase 'demarrage' -Step 1
    Write-BuildProgress 5 'Source Microsoft' 'Montage de l ISO officielle...' 1
    $diskImage = Mount-DiskImage -ImagePath $sourceIsoPath -PassThru
    $volume = $diskImage | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) { throw 'Impossible de trouver la lettre du lecteur ISO monte.' }
    $sourceRoot = $volume.DriveLetter + ':\'
    Assert-MicrosoftSignedFile -Path (Join-Path $sourceRoot 'setup.exe') -Description 'Programme installation de ISO source'
    Assert-BuildNotCancelled -Phase 'montage et validation de ISO Microsoft' -Step 1

    Write-BuildProgress 15 'Fichiers Windows' 'Copie des fichiers d installation, sans dupliquer l image Windows...' 2
    # L'image sera exportee directement depuis l'ISO montee. La copier ici
    # ajouterait plusieurs Go d'ecritures avant une seconde lecture complete.
    $robocopyOutput = @(& robocopy.exe $sourceRoot $mediaDir /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NP /XF install.wim install.esd 2>&1)
    $robocopyExitCode = $LASTEXITCODE
    if ($robocopyExitCode -gt 7) {
        $robocopyDetail = Get-NativeOutputTail -Output $robocopyOutput
        throw "Copie de ISO Microsoft impossible avec Robocopy (code $robocopyExitCode) : $robocopyDetail"
    }
    Assert-BuildNotCancelled -Phase 'copie des fichiers Windows' -Step 2

    $sourceWim = Join-Path $sourceRoot 'sources\install.wim'
    $sourceEsd = Join-Path $sourceRoot 'sources\install.esd'
    $sourceImage = if (Test-Path -LiteralPath $sourceWim) { $sourceWim } elseif (Test-Path -LiteralPath $sourceEsd) { $sourceEsd } else { $null }
    if (-not $sourceImage) { throw 'Ni sources\install.wim ni sources\install.esd n''a ete trouve.' }

    Write-BuildProgress 22 'Editions Windows' 'Lecture des editions contenues dans install.wim...' 3
    $images = @(Get-BastosWindowsImages -ImagePath $sourceImage)
    $selected = Select-BastosWindowsEdition -Images $images -RequestedIndex $EditionIndex -RequestedPattern $EditionPattern
    if ([string]$selected.ImageName -notmatch '(?i)\bWindows\s*11\b') {
        throw "BASTOS accepte maintenant uniquement une ISO officielle Windows 11. Edition detectee : $($selected.ImageName)"
    }
    $selectedEditionProperty = $selected.PSObject.Properties['EditionId']
    $selectedEditionId = if($selectedEditionProperty){[string]$selectedEditionProperty.Value}else{'non fourni'}
    Write-Host ("Edition selectionnee : index {0}, {1}, identifiant Microsoft {2}" -f $selected.ImageIndex, $selected.ImageName, $selectedEditionId)

    Assert-BuildNotCancelled -Phase 'selection de edition Windows' -Step 3
    Write-BuildProgress 30 'Edition Windows' 'Conversion en une image Windows Pro unique...' 3
    $destinationWim = Join-Path $mediaDir 'sources\install.wim'
    Export-BastosWindowsImage -SourceImagePath $sourceImage -SourceIndex $selected.ImageIndex -DestinationImagePath $destinationWim
    Assert-BuildNotCancelled -Phase 'conversion de image Windows' -Step 3

    Write-BuildProgress 48 'Allegement sur' 'Suppression hors ligne des applications choisies...' 4
    $shortNameOriginal=[int](Get-ItemPropertyValue -LiteralPath $shortNameRegistryPath -Name 'NtfsDisable8dot3NameCreation' -ErrorAction Stop)
    if($shortNameOriginal -eq 1){
        # DISM exige encore les metadonnees 8.3 de certaines images Microsoft.
        # Le mode par volume reactive C: seulement pendant le montage, puis le
        # reglage global exact est restaure aussitot apres la sauvegarde du WIM.
        & fsutil.exe 8dot3name set 2 | Out-Null
        if($LASTEXITCODE -ne 0){throw "Impossible d ouvrir la compatibilite NTFS 8.3 pour DISM (code $LASTEXITCODE)."}
        $shortNameAdjusted=$true
    }
    Mount-WindowsImage -ImagePath $destinationWim -Index 1 -Path $mountDir -CheckIntegrity | Out-Null
    $wimMounted = $true
    $packages = @(Get-AppxProvisionedPackage -Path $mountDir)
    $removalFailures = [Collections.Generic.List[string]]::new()
    foreach ($package in $packages) {
        Assert-BuildNotCancelled -Phase 'allegement hors ligne' -Step 4
        if ($removeNames -contains $package.DisplayName) {
            Write-Host ("  - {0}" -f $package.DisplayName)
            try {
                Remove-AppxProvisionedPackage -Path $mountDir -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            } catch {
                $removalFailures.Add(("{0}: {1}" -f $package.DisplayName,$_.Exception.Message))
            }
        }
    }
    $remainingSelectedPackages = @(Get-AppxProvisionedPackage -Path $mountDir | Where-Object { $_.DisplayName -in $removeNames })
    if ($removalFailures.Count -gt 0 -or $remainingSelectedPackages.Count -gt 0) {
        $details = @($removalFailures) + @($remainingSelectedPackages | ForEach-Object { "Toujours present : $($_.DisplayName)" })
        throw "L'allegement hors ligne n'a pas pu retirer toutes les applications choisies : $($details -join ' | ')"
    }

    Assert-BuildNotCancelled -Phase 'allegement hors ligne' -Step 4
    Write-BuildProgress 68 'Integration BASTOS' 'Ajout du logiciel, des reglages et du retour arriere...' 5
    $oemTarget = Join-Path $mediaDir 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
    New-Item -ItemType Directory -Path $oemTarget -Force | Out-Null
    $errorHandlerSource = Join-Path $kitRoot 'BASTOS-ErrorHandler.cmd'
    if (-not (Test-Path -LiteralPath $errorHandlerSource -PathType Leaf)) { throw "Gestionnaire d erreur Setup absent : $errorHandlerSource" }
    $setupCompleteSource = Join-Path $kitRoot 'BASTOS-SetupComplete.cmd'
    if (-not (Test-Path -LiteralPath $setupCompleteSource -PathType Leaf)) { throw "Gestionnaire pre-connexion absent : $setupCompleteSource" }
    $setupScriptsTarget = Join-Path $mediaDir 'sources\$OEM$\$$\Setup\Scripts'
    New-Item -ItemType Directory -Path $setupScriptsTarget -Force | Out-Null
    Copy-Item -LiteralPath $errorHandlerSource -Destination (Join-Path $setupScriptsTarget 'ErrorHandler.cmd') -Force
    Copy-Item -LiteralPath $setupCompleteSource -Destination (Join-Path $setupScriptsTarget 'SetupComplete.cmd') -Force
    $wallpaperSource = Join-Path $kitRoot 'Assets\BASTOS-Wallpaper.jpg'
    if (-not (Test-Path -LiteralPath $wallpaperSource -PathType Leaf)) { throw "Fond d ecran BASTOS requis absent : $wallpaperSource" }
    $windowsWallpaperTarget = Join-Path $mediaDir 'sources\$OEM$\$$\Web\Wallpaper\Windows'
    $windows4KTarget = Join-Path $mediaDir 'sources\$OEM$\$$\Web\4K\Wallpaper\Windows'
    $windowsScreenTarget = Join-Path $mediaDir 'sources\$OEM$\$$\Web\Screen'
    New-Item -ItemType Directory -Path $windowsWallpaperTarget,$windows4KTarget,$windowsScreenTarget -Force | Out-Null
    Copy-Item -LiteralPath $wallpaperSource -Destination (Join-Path $windowsWallpaperTarget 'img0.jpg') -Force
    foreach($resolution in @('1024x768','1200x1920','1366x768','1600x2560','1920x1200','2160x3840','2560x1440','2560x1600','3840x2160')) { Copy-Item -LiteralPath $wallpaperSource -Destination (Join-Path $windows4KTarget ("img0_{0}.jpg" -f $resolution)) -Force }
    Copy-Item -LiteralPath $wallpaperSource -Destination (Join-Path $windowsScreenTarget 'img100.jpg') -Force
    $payloadItems = @(Get-ChildItem -LiteralPath $payloadRoot -Force | Where-Object {
        $_.Name -notin @(
            'Logs','Backups','MachineProfileApplied.ok','UserProfileApplied.ok','UserProfileCoreApplied.ok','Hardware-Target-Profile.json',
            'BASTOS-App-Manifest.json','BASTOS-Build.json','Remove-Appx-Selection.txt','Browser-Selection.json',
            'Regional-Selection.json','Appx-Machine-Removal.json'
        )
    })
    foreach ($payloadItem in $payloadItems) {
        Copy-Item -LiteralPath $payloadItem.FullName -Destination $oemTarget -Recurse -Force
    }
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination (Join-Path $oemTarget 'Build-BASTOS-ISO.ps1') -Force
    Copy-Item -LiteralPath $answerTemplateFile -Destination (Join-Path $oemTarget 'autounattend.xml') -Force
    Copy-Item -LiteralPath $defaultRemoveListFile -Destination (Join-Path $oemTarget 'Remove-Appx.txt') -Force
    $removeSelectionText = ((@(
        '# Applications selectionnees pour la suppression hors ligne.'
        '# Microsoft.YourPhone est toujours conserve par BASTOS.'
    ) + @($removeNames)) -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText((Join-Path $oemTarget 'Remove-Appx-Selection.txt'),$removeSelectionText,[Text.UTF8Encoding]::new($false))
    $removalOptionsTarget = Join-Path $oemTarget 'BASTOS-Removal-Options.json'
    [IO.File]::WriteAllText($removalOptionsTarget,($removalOptions | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $kitRoot 'Profile.json') -Destination $oemTarget -Force
    $browserSelectionPath = Join-Path $oemTarget 'Browser-Selection.json'
    [IO.File]::WriteAllText($browserSelectionPath, ($selectedBrowser | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $regionalSelection = [pscustomobject]@{
        WindowsLocale = $WindowsLocale
        InputLocale = $KeyboardLayout
    }
    $regionalSelectionPath = Join-Path $oemTarget 'Regional-Selection.json'
    [IO.File]::WriteAllText($regionalSelectionPath, ($regionalSelection | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $oemTarget 'BASTOS-LocalAccount.txt'),$LocalUserName,[Text.UTF8Encoding]::new($false))
    foreach ($supportFile in @('Repair-BASTOS-First-Run.ps1','Reparer-BASTOS-apres-installation.cmd','Repair-BASTOS-Applications.ps1','Rectifier-BASTOS-OneDrive-Edge-Xbox.cmd')) {
        $supportSource = Join-Path $kitRoot $supportFile
        if (-not (Test-Path -LiteralPath $supportSource -PathType Leaf)) { throw "Fichier BASTOS requis absent : $supportSource" }
        Copy-Item -LiteralPath $supportSource -Destination (Join-Path $oemTarget $supportFile) -Force
    }
    # Copy-Item conserve les attributs NTFS. Oscdimg ignore par defaut certains
    # fichiers caches ou systeme; normaliser la copie evite donc une ISO privee
    # de VERSION.txt ou de l'application native si la source porte ces attributs.
    $attributesToClear = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    foreach ($stagedItem in @(Get-ChildItem -LiteralPath $oemTarget -Recurse -Force)) {
        if (($stagedItem.Attributes -band $attributesToClear) -ne 0) {
            $stagedItem.Attributes = $stagedItem.Attributes -band (-bnot $attributesToClear)
        }
    }
    $requiredBastosFiles = @(
        'BASTOS-Architecture.psm1',
        'BASTOS-SetupDiagnostics.psm1',
        'Invoke-BASTOS-Specialize.ps1',
        'Apply-Machine.ps1',
        'Apply-User.ps1',
        'BASTOS-Specialize-App-Restore.ps1',
        'BASTOS-Specialize-WU-Off.ps1',
        'BASTOS-Start.cmd',
        'BASTOS-ErrorHandler.cmd',
        'Configure-BASTOS-AfterInstall.ps1',
        'Clear-BASTOS-StandbyList.ps1',
        'Complete-BASTOS-UserSetup.ps1',
        'Start-BASTOS-Autonomous-FirstLogon.ps1',
        'Initialize-BASTOS-Autonomous-FirstLogon.ps1',
        'Initialize-BASTOS-PreLogon.ps1',
        'Remove-BASTOS-LegacyKernelComponents.ps1',
        'Invoke-BASTOS-FirstDesktopEssentials.ps1',
        'Install-BASTOS-SoftwareSelection.ps1',
        'Invoke-BASTOS-PostInstall.ps1',
        'Bastos-Uninstall.exe',
        'Bastos.Native\BASTOS-Native.exe',
        'Bastos.Game\BASTOS-Game.exe',
        'Bastos.Recovery\BASTOS-Recovery-Probe.exe',
        'Assets\Bastos-Game-Tray.ico',
        'Remove-BASTOS-OneDrive.ps1',
        'Remove-BASTOS-Edge.ps1',
        'Set-BASTOS-EdgeDesktopPolicy.ps1',
        'BASTOS-REAL-Watchdog.ps1',
        'Initialize-BASTOS-Recovery.ps1',
        'Install-BASTOS-AdkDeploymentTools.ps1',
        'Integrate-WinRE-Into-BASTOS.ps1',
        'VERSION.txt',
        'Download-BASTOS-WindowsIso.ps1',
        'Download-BASTOS-RadeonTool.ps1',
        'Invoke-BASTOS-Protected.ps1',
        'Invoke-BASTOS-GraphicsOptimization.ps1',
        'Graphics-Optimizations\README.md',
        'WebView2\Microsoft.Web.WebView2.Core.dll',
        'WebView2\Microsoft.Web.WebView2.WinForms.dll',
        'WebView2\WebView2Loader.dll',
        'Assets\Bastos-App.ico',
        'Assets\Bastos-Logo-Dark-UI.png',
        'Assets\BASTOS-Wallpaper.jpg',
        'General-Optimization-Tools\11 Mpo.ps1',
        'General-Optimization-Tools\25 Device Manager Power Savings & Wake.ps1',
        'General-Optimization-Tools\26 Network Adapter Power Savings & Wake.ps1',
        'General-Optimization-Tools\27 Network IPv4 Only.ps1',
        'General-Optimization-Tools\30 Timer Resolution.ps1',
        'General-Optimization-Tools\6 Monitor Optimization.ps1',
        'Browser-Selection.json',
        'Regional-Selection.json',
        'BASTOS-Removal-Options.json',
        'Repair-BASTOS-First-Run.ps1',
        'Reparer-BASTOS-apres-installation.cmd',
        'Repair-BASTOS-Applications.ps1',
        'Rectifier-BASTOS-OneDrive-Edge-Xbox.cmd'
    )
    foreach ($requiredBastosFile in $requiredBastosFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $oemTarget $requiredBastosFile) -PathType Leaf)) {
            throw "Integration BASTOS incomplete : $requiredBastosFile"
        }
    }
    $embeddedPreLogonText = Get-Content -LiteralPath (Join-Path $oemTarget 'Initialize-BASTOS-PreLogon.ps1') -Raw -Encoding UTF8
    if ($embeddedPreLogonText -notmatch 'LogonUser' -or $embeddedPreLogonText -notmatch 'PasswordVerified' -or
        $embeddedPreLogonText -notmatch "standardName='BastOS'" -or $embeddedPreLogonText -notmatch 'Disable-BuiltInAdministrator' -or
        $embeddedPreLogonText -match 'Rename-BuiltInAdministrator') {
        throw 'Le media BASTOS doit verifier BastOS local, distinct du compte integre SID-500.'
    }
    $embeddedSetupCompleteText = Get-Content -LiteralPath (Join-Path $oemTarget 'BASTOS-SetupComplete.cmd') -Raw -Encoding UTF8
    if ($embeddedSetupCompleteText -notmatch 'Initialize-BASTOS-PreLogon\.ps1' -or
        $embeddedSetupCompleteText -notmatch 'BASTOS_PRELOGON_EXIT' -or $embeddedSetupCompleteText -notmatch 'ms-cxh:localonly') {
        throw 'Le media BASTOS ne contient pas le SetupComplete du compte local BastOS.'
    }
    $applyUserText = Get-Content -LiteralPath (Join-Path $oemTarget 'Apply-User.ps1') -Raw -Encoding UTF8
    if ($applyUserText -notmatch 'BASTOS\.lnk' -or $applyUserText -notmatch 'Bastos-App\.ico') {
        throw 'La version BASTOS integree ne garantit pas son raccourci personnalise sur le Bureau.'
    }
    $verificationPairs = @()
    foreach ($payloadItem in $payloadItems) {
        $sourceFiles = if($payloadItem.PSIsContainer){@(Get-ChildItem -LiteralPath $payloadItem.FullName -File -Recurse -Force)}else{@($payloadItem)}
        foreach ($sourceFile in $sourceFiles) {
            $relativePath = $sourceFile.FullName.Substring($payloadRoot.Length).TrimStart('\')
            $verificationPairs += [pscustomobject]@{ Source=$sourceFile.FullName; RelativePath=$relativePath }
        }
    }
    foreach ($sourcePair in @(
        [pscustomobject]@{ Source=$MyInvocation.MyCommand.Path; RelativePath='Build-BASTOS-ISO.ps1' },
        [pscustomobject]@{ Source=$answerTemplateFile; RelativePath='autounattend.xml' },
        [pscustomobject]@{ Source=$defaultRemoveListFile; RelativePath='Remove-Appx.txt' },
        [pscustomobject]@{ Source=$removalOptionsTarget; RelativePath='BASTOS-Removal-Options.json' },
        [pscustomobject]@{ Source=(Join-Path $kitRoot 'Profile.json'); RelativePath='Profile.json' },
        [pscustomobject]@{ Source=(Join-Path $kitRoot 'Repair-BASTOS-First-Run.ps1'); RelativePath='Repair-BASTOS-First-Run.ps1' },
        [pscustomobject]@{ Source=(Join-Path $kitRoot 'Reparer-BASTOS-apres-installation.cmd'); RelativePath='Reparer-BASTOS-apres-installation.cmd' }
    )) {
        if (-not (Test-Path -LiteralPath $sourcePair.Source -PathType Leaf)) { throw "Source BASTOS absente du manifeste : $($sourcePair.Source)" }
        $verificationPairs += $sourcePair
    }
    $manifestEntries = @()
    foreach ($pair in @($verificationPairs | Sort-Object RelativePath -Unique)) {
        $targetFile = Join-Path $oemTarget $pair.RelativePath
        if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) { throw "Copie BASTOS incomplete : $($pair.RelativePath)" }
        $sourceHash = (Get-FileHash -LiteralPath $pair.Source -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw "Copie BASTOS non conforme au fichier courant : $($pair.RelativePath)" }
        $manifestEntries += [pscustomobject]@{ Path=$pair.RelativePath; Sha256=$targetHash }
    }
    $bastosVersion = (Get-Content -LiteralPath (Join-Path $oemTarget 'VERSION.txt') -Raw -Encoding UTF8).Trim()
    $appManifest = [pscustomobject]@{
        BastosVersion = $bastosVersion
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        FileCount = $manifestEntries.Count
        Files = $manifestEntries
    }
    $appManifestPath = Join-Path $oemTarget 'BASTOS-App-Manifest.json'
    [IO.File]::WriteAllText($appManifestPath, ($appManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $buildMetadata = [pscustomobject]@{
        BuildId = $buildId
        BuiltUtc = [DateTime]::UtcNow.ToString('o')
        BastosVersion = $bastosVersion
        WindowsLocale = $WindowsLocale
        KeyboardLayout = $KeyboardLayout
        BrowserId = [string]$selectedBrowser.Id
        BrowserName = [string]$selectedBrowser.DisplayName
        BrowserSelectionSha256 = (Get-FileHash -LiteralPath $browserSelectionPath -Algorithm SHA256).Hash
        RegionalSelectionSha256 = (Get-FileHash -LiteralPath $regionalSelectionPath -Algorithm SHA256).Hash
        AppManifestSha256 = (Get-FileHash -LiteralPath $appManifestPath -Algorithm SHA256).Hash
        AppFileCount = $manifestEntries.Count
        NativeAppSha256 = (Get-FileHash -LiteralPath (Join-Path $oemTarget 'Bastos.Native\BASTOS-Native.exe') -Algorithm SHA256).Hash
        RemoveSelectionSha256 = (Get-FileHash -LiteralPath (Join-Path $oemTarget 'Remove-Appx-Selection.txt') -Algorithm SHA256).Hash
        RemovalOptionsSha256 = (Get-FileHash -LiteralPath $removalOptionsTarget -Algorithm SHA256).Hash
    }
    [IO.File]::WriteAllText((Join-Path $oemTarget 'BASTOS-Build.json'), ($buildMetadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $panther = Join-Path $mountDir 'Windows\Panther'
    New-Item -ItemType Directory -Path $panther -Force | Out-Null
    $embeddedUnattendDirectory = Join-Path $panther 'Unattend'
    New-Item -ItemType Directory -Path $embeddedUnattendDirectory -Force | Out-Null
    $cachedUnattendPath = Join-Path $panther 'unattend.xml'
    $embeddedUnattendPath = Join-Path $embeddedUnattendDirectory 'Unattend.xml'
    # Ne jamais figer une reponse OOBE dans install.wim : elle survivrait aux
    # changements de compte/nom de machine et pourrait reprendre priorite plus
    # tard. Recovery fournit /Unattend explicitement, puis WinPE recopie la
    # reponse resolue dans Panther juste avant le premier demarrage.
    Remove-Item -LiteralPath $cachedUnattendPath,$embeddedUnattendPath -Force -ErrorAction SilentlyContinue
    if((Test-Path -LiteralPath $cachedUnattendPath -PathType Leaf) -or (Test-Path -LiteralPath $embeddedUnattendPath -PathType Leaf)){
        throw 'Un ancien fichier de reponses Panther reste fige dans install.wim.'
    }
    Copy-Item -LiteralPath $answerFile -Destination (Join-Path $mediaDir 'autounattend.xml') -Force
    Copy-Item -LiteralPath $winreIntegrationFile -Destination (Join-Path $mediaDir 'Integrate-WinRE-Into-BASTOS.ps1') -Force
    if((Get-FileHash -LiteralPath $winreIntegrationFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $mediaDir 'Integrate-WinRE-Into-BASTOS.ps1') -Algorithm SHA256).Hash){throw 'La copie racine du module d integration WinRE est invalide.'}

    Assert-BuildNotCancelled -Phase 'integration BASTOS' -Step 5
    Dismount-WindowsImage -Path $mountDir -Save -CheckIntegrity | Out-Null
    $wimMounted = $false
    if($shortNameAdjusted -and $null -ne $shortNameOriginal){
        & fsutil.exe 8dot3name set $shortNameOriginal | Out-Null
        if($LASTEXITCODE -ne 0){throw "Le reglage NTFS 8.3 initial n a pas pu etre restaure (code $LASTEXITCODE)."}
        $shortNameAdjusted=$false
    }
    Assert-BuildNotCancelled -Phase 'enregistrement de image Windows' -Step 5

    Write-BuildProgress 88 'ISO amorcable' 'Creation du media BIOS et UEFI...' 6
    if (Test-Path -LiteralPath $outputIsoPath) { Remove-Item -LiteralPath $outputIsoPath -Force }
    $outputTouched = $true
    $bootData = "-bootdata:2#p0,e,b$mediaDir\boot\etfsboot.com#pEF,e,b$mediaDir\efi\microsoft\boot\efisys.bin"
    & $oscdimg '-m' '-o' '-h' '-u2' '-udfver102' $bootData $mediaDir $outputIsoPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputIsoPath)) {
        throw "Oscdimg a echoue avec le code $LASTEXITCODE."
    }
    Assert-BuildNotCancelled -Phase 'creation du media amorcable' -Step 6

    Write-BuildProgress 94 'Verification BASTOS' 'Reouverture de ISO finale et controle de application embarquee...' 7
    $verificationVolume = $null
    $verificationWim = ''
    $requiredEmbeddedFiles = @()
    for ($verificationAttempt = 1; $verificationAttempt -le 2; $verificationAttempt++) {
        if ($verificationDiskImage) {
            Dismount-DiskImage -ImagePath $outputIsoPath -ErrorAction SilentlyContinue | Out-Null
            $verificationDiskImage = $null
            Start-Sleep -Seconds 1
        }
        if ($verificationAttempt -gt 1) {
            Write-Host 'Premier montage incomplet; nouveau montage de ISO finale pour rafraichir le cache Windows.' -ForegroundColor Yellow
        }
        $verificationDiskImage = Mount-DiskImage -ImagePath $outputIsoPath -PassThru
        $verificationVolume = $null
        $volumeDeadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            $verificationVolume = $verificationDiskImage | Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | Select-Object -First 1
            if ($verificationVolume) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $volumeDeadline)
        if (-not $verificationVolume) { continue }

        $verificationIsoRoot = $verificationVolume.DriveLetter + ':\'
        $verificationWim = Join-Path $verificationIsoRoot 'sources\install.wim'
        $embeddedRoot = Join-Path $verificationIsoRoot 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
        $embeddedNativeApp = Join-Path $embeddedRoot 'Bastos.Native\BASTOS-Native.exe'
        $embeddedManifestPath = Join-Path $embeddedRoot 'BASTOS-App-Manifest.json'
        $embeddedBuildPath = Join-Path $embeddedRoot 'BASTOS-Build.json'
        $embeddedBrowserPath = Join-Path $embeddedRoot 'Browser-Selection.json'
        $embeddedRegionalPath = Join-Path $embeddedRoot 'Regional-Selection.json'
        $embeddedRemoveSelectionPath = Join-Path $embeddedRoot 'Remove-Appx-Selection.txt'
        $embeddedRemovalOptionsPath = Join-Path $embeddedRoot 'BASTOS-Removal-Options.json'
        $embeddedErrorHandlerPath = Join-Path $verificationIsoRoot 'sources\$OEM$\$$\Setup\Scripts\ErrorHandler.cmd'
        $embeddedSetupCompletePath = Join-Path $verificationIsoRoot 'sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd'
        $embeddedPreLogonPath = Join-Path $embeddedRoot 'Initialize-BASTOS-PreLogon.ps1'
        $embeddedAccountMarkerPath = Join-Path $embeddedRoot 'BASTOS-LocalAccount.txt'
        $requiredEmbeddedFiles = @($embeddedNativeApp,$embeddedManifestPath,$embeddedBuildPath,$embeddedBrowserPath,$embeddedRegionalPath,$embeddedRemoveSelectionPath,$embeddedRemovalOptionsPath,$embeddedErrorHandlerPath,$embeddedSetupCompletePath,$embeddedPreLogonPath,$embeddedAccountMarkerPath)
        $contentDeadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            $missingEmbeddedFiles = @($requiredEmbeddedFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
            if ((Test-Path -LiteralPath $verificationWim -PathType Leaf) -and $missingEmbeddedFiles.Count -eq 0) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $contentDeadline)
        if ((Test-Path -LiteralPath $verificationWim -PathType Leaf) -and $missingEmbeddedFiles.Count -eq 0) { break }
    }
    if (-not $verificationVolume) { throw 'Impossible de remonter ISO BASTOS finale pour verification.' }
    if (-not (Test-Path -LiteralPath $verificationWim -PathType Leaf)) { throw 'install.wim absent de ISO BASTOS finale.' }
    foreach ($requiredEmbeddedFile in $requiredEmbeddedFiles) {
        if (-not (Test-Path -LiteralPath $requiredEmbeddedFile -PathType Leaf)) {
            throw "Verification finale BASTOS incomplete : $requiredEmbeddedFile"
        }
    }
    if((Get-FileHash -LiteralPath $embeddedErrorHandlerPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $errorHandlerSource -Algorithm SHA256).Hash){throw 'ErrorHandler.cmd est divergent dans ISO BASTOS finale.'}
    $embeddedBuild = Get-Content -LiteralPath $embeddedBuildPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $embeddedManifest = Get-Content -LiteralPath $embeddedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $embeddedManifestFiles = @($embeddedManifest.Files)
    if ([int]$embeddedManifest.FileCount -ne $embeddedManifestFiles.Count -or
        [int]$embeddedBuild.AppFileCount -ne $embeddedManifestFiles.Count) {
        throw 'Le manifeste de application BASTOS embarquee est incomplet.'
    }
    $embeddedRootPrefix = [IO.Path]::GetFullPath($embeddedRoot).TrimEnd('\') + '\'
    foreach ($manifestFile in $embeddedManifestFiles) {
        $relativePath = [string]$manifestFile.Path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath)) {
            throw "Chemin invalide dans le manifeste BASTOS embarque : $relativePath"
        }
        $embeddedFile = [IO.Path]::GetFullPath((Join-Path $embeddedRoot $relativePath))
        if (-not $embeddedFile.StartsWith($embeddedRootPrefix,[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $embeddedFile -PathType Leaf)) {
            throw "Fichier de application BASTOS absent ou hors cible dans ISO finale : $relativePath"
        }
        $embeddedFileHash = (Get-FileHash -LiteralPath $embeddedFile -Algorithm SHA256).Hash
        if ($embeddedFileHash -ne [string]$manifestFile.Sha256) {
            throw "Fichier de application BASTOS different de la version courante dans ISO finale : $relativePath"
        }
    }
    $embeddedNativeHash = (Get-FileHash -LiteralPath $embeddedNativeApp -Algorithm SHA256).Hash
    $embeddedManifestHash = (Get-FileHash -LiteralPath $embeddedManifestPath -Algorithm SHA256).Hash
    $embeddedBrowserHash = (Get-FileHash -LiteralPath $embeddedBrowserPath -Algorithm SHA256).Hash
    $embeddedRegionalHash = (Get-FileHash -LiteralPath $embeddedRegionalPath -Algorithm SHA256).Hash
    $embeddedRemoveSelectionHash = (Get-FileHash -LiteralPath $embeddedRemoveSelectionPath -Algorithm SHA256).Hash
    $embeddedRemovalOptionsHash = (Get-FileHash -LiteralPath $embeddedRemovalOptionsPath -Algorithm SHA256).Hash
    if ([string]$embeddedBuild.BastosVersion -ne $bastosVersion -or
        [string]$embeddedBuild.NativeAppSha256 -ne [string]$buildMetadata.NativeAppSha256 -or
        $embeddedNativeHash -ne [string]$buildMetadata.NativeAppSha256 -or
        $embeddedManifestHash -ne [string]$buildMetadata.AppManifestSha256 -or
        $embeddedBrowserHash -ne [string]$buildMetadata.BrowserSelectionSha256 -or
        $embeddedRegionalHash -ne [string]$buildMetadata.RegionalSelectionSha256 -or
        $embeddedRemoveSelectionHash -ne [string]$buildMetadata.RemoveSelectionSha256 -or
        $embeddedRemovalOptionsHash -ne [string]$buildMetadata.RemovalOptionsSha256 -or
        [string]$embeddedBuild.BrowserId -ne [string]$selectedBrowser.Id -or
        [string]$embeddedBuild.WindowsLocale -ne $WindowsLocale -or
        [string]$embeddedBuild.KeyboardLayout -ne $KeyboardLayout) {
        throw 'ISO finale ne contient pas exactement la version BASTOS et les options verifiees pendant cette construction.'
    }
    # Verify boot files and the selected Windows image inside the reopened output.
    foreach($relative in @('setup.exe','bootmgr','boot\etfsboot.com','efi\microsoft\boot\efisys.bin','efi\boot\bootx64.efi','sources\boot.wim','autounattend.xml')) {
        $onMedia=Join-Path $mediaDir $relative;$inIso=Join-Path $verificationIsoRoot $relative
        if(-not (Test-Path -LiteralPath $inIso -PathType Leaf) -or
            (Get-BastosFileSha256 -Path $inIso) -ne (Get-BastosFileSha256 -Path $onMedia)) {throw "Fichier de demarrage absent ou divergent dans ISO : $relative"}
    }
    $finalImages=@(Get-BastosWindowsImages -ImagePath $verificationWim)
    $finalImage=Get-WindowsImage -ImagePath $verificationWim -Index 1 -ErrorAction Stop
    if($finalImages.Count -ne 1 -or [string]$finalImage.ImageName -ne [string]$selected.ImageName -or [int]$finalImage.Architecture -ne 9) {throw 'Image Windows finale differente de edition Windows 11 x64 selectionnee.'}
    Write-BuildProgress 96 'Verification image Windows' 'Comparaison de l image Windows exportee et de sa copie dans ISO finale...' 7
    $wimHash=Get-BastosFileSha256 -Path $destinationWim
    if($wimHash -ne (Get-BastosFileSha256 -Path $verificationWim)){throw 'Image Windows finale divergente ou incomplete.'}
    $script:BuildEvidence=@{
        SourceIso=$sourceIsoPath; WindowsLocale=$WindowsLocale;KeyboardLayout=$KeyboardLayout;LocalUserName=$LocalUserName
        AppManifestSha256=[string]$buildMetadata.AppManifestSha256;RemoveSelectionSha256=[string]$buildMetadata.RemoveSelectionSha256;RemovalOptionsSha256=[string]$buildMetadata.RemovalOptionsSha256
        SourceAppManifestSha256=(Get-BastosFileSha256 -Path (Join-Path $kitRoot 'BASTOS-App-Manifest.json'));NativeAppSha256=[string]$buildMetadata.NativeAppSha256
        MediaRemounted=$true;BootFilesVerified=$true;WindowsImageVerified=$true;EmbeddedFilesVerified=$true
        WindowsImageCount=$finalImages.Count;WindowsImageName=[string]$finalImage.ImageName;WindowsImageArchitecture=[int]$finalImage.Architecture
        WindowsImageSha256=$wimHash;VerifiedAppFileCount=$embeddedManifestFiles.Count
        RequestRemoveSelectionSha256=if($RemoveListPath){Get-BastosFileSha256 -Path $RemoveListPath}else{''}
        RequestRemovalOptionsSha256=if($RemovalOptionsPath){Get-BastosFileSha256 -Path $RemovalOptionsPath}else{''}
    }
    Dismount-DiskImage -ImagePath $outputIsoPath | Out-Null
    $verificationDiskImage = $null
    Write-Host "Version BASTOS finale reverifiee fichier par fichier dans sources\`$OEM`$ : v$bastosVersion, $($embeddedManifestFiles.Count) fichiers, langue $WindowsLocale, clavier $KeyboardLayout, navigateur $($selectedBrowser.DisplayName), application native SHA256 $embeddedNativeHash"
    Assert-BuildNotCancelled -Phase 'verification finale de application BASTOS' -Step 7

    Lock-BastosCancellation -CancellationPath $CancellationPath -Reason 'vérification et publication du fichier ISO final'
    Write-BuildProgress 97 'Verification' 'Calcul du SHA256 du fichier final...' 7
    $hash = [pscustomobject]@{Hash=(Get-BastosFileSha256 -Path $outputIsoPath)}
    $script:BuildEvidence.FileLength=[long](Get-Item -LiteralPath $outputIsoPath).Length
    $script:BuildEvidence.Sha256=$hash.Hash
    Write-Host ''
    Write-Host 'ISO terminee.' -ForegroundColor Green
    Write-Host ("Chemin : {0}" -f $outputIsoPath)
    Write-Host ("SHA256 : {0}" -f $hash.Hash)
    Write-Host 'Ce SHA256 est celui de ton ISO personnalisee, pas celui de l''ISO Microsoft source.'
    Write-BuildProgress 100 'Termine' ("ISO BASTOS creee : {0}" -f $outputIsoPath) 7
    Save-BuildResult -Success $true -Cancelled $false -ExitCode 0 -Message 'ISO BASTOS creee et reverifiee avec succes.' -Detail ("SHA256 : {0}" -f $hash.Hash)
}
catch [System.OperationCanceledException] {
    $buildCancelled = $true
    $deleteFailedOutput = $outputTouched
    $cancelMessage=$_.Exception.Message
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}
catch {
    $deleteFailedOutput = $outputTouched
    $failureDetail = (@($_.InvocationInfo.PositionMessage,$_.ScriptStackTrace) | Where-Object { $_ }) -join "`r`n"
    Save-BuildResult -Success $false -Cancelled $false -ExitCode 1 -Message $_.Exception.Message -Detail $failureDetail
    throw
}
finally {
    if ($verificationDiskImage) {
        Dismount-DiskImage -ImagePath $outputIsoPath -ErrorAction SilentlyContinue | Out-Null
    }
    if ($wimMounted) {
        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    if($shortNameAdjusted -and $null -ne $shortNameOriginal){
        & fsutil.exe 8dot3name set $shortNameOriginal 2>$null | Out-Null
    }
    if ($diskImage) {
        Dismount-DiskImage -ImagePath $sourceIsoPath -ErrorAction SilentlyContinue | Out-Null
    }
    if ($deleteFailedOutput -and (Test-Path -LiteralPath $outputIsoPath -PathType Leaf)) {
        Remove-Item -LiteralPath $outputIsoPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $KeepWorkFiles -and (Test-Path -LiteralPath $buildDir)) {
        Test-SafeBuildDirectory -Path $buildDir -Root $WorkRoot
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
}
if ($buildCancelled) {
    $script:CancellationCleanupVerified=$false
    try{
        $remaining=@(Get-WindowsImage -Mounted -ErrorAction Stop|Where-Object {$_.Path.TrimEnd('\') -eq $mountDir.TrimEnd('\')})
        $sourceAttached=(Get-DiskImage -ImagePath $sourceIsoPath -ErrorAction Stop).Attached
        $outputAttached=$false
        if(Test-Path -LiteralPath $outputIsoPath){$outputAttached=(Get-DiskImage -ImagePath $outputIsoPath -ErrorAction Stop).Attached}
        $script:CancellationCleanupVerified=($remaining.Count -eq 0 -and -not $sourceAttached -and -not $outputAttached -and
            (-not $outputTouched -or -not(Test-Path -LiteralPath $outputIsoPath)) -and
            ($KeepWorkFiles -or -not(Test-Path -LiteralPath $buildDir)))
    }catch{}
    $script:CancellationCleanupFailed=-not $script:CancellationCleanupVerified
    Save-BuildResult -Success $false -Cancelled $script:CancellationCleanupVerified -ExitCode $(if($script:CancellationCleanupVerified){2}else{1}) -Message $(if($script:CancellationCleanupVerified){$cancelMessage}else{'CANCELLATION_CLEANUP_UNCONFIRMED : annulation demandee, mais nettoyage des montages ou fichiers non confirme. Consulte le Journal avant de relancer.'})
    if($script:CancellationCleanupVerified){exit 2}else{exit 1}
}
