[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('RadeonSoftwareSlimmer','RadeonTuner')]
    [string]$Tool,

    [Parameter(Mandatory)]
    [string]$DestinationRoot,

    [string]$ProgressPath,
    [string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$catalog = @{
    RadeonSoftwareSlimmer = [pscustomobject]@{
        Name = 'Radeon Software Slimmer'
        Folder = 'RadeonSoftwareSlimmer'
        Version = '1.12.0'
        ExpectedExe = 'RadeonSoftwareSlimmer.exe'
        Uri = 'https://github.com/GSDragoon/RadeonSoftwareSlimmer/releases/download/1.12.0/RadeonSoftwareSlimmer_1.12.0_net48.zip'
        RequiredPath = '^/GSDragoon/RadeonSoftwareSlimmer/releases/download/1\.12\.0/RadeonSoftwareSlimmer_1\.12\.0_net48\.zip$'
        ExpectedSize = 3530569L
        ExpectedSha256 = 'E4F1737CA779E38BDA1B776F0E5560069E54BA533A90CB4EFDC48A020A3E51D4'
    }
    RadeonTuner = [pscustomobject]@{
        Name = 'Radeon Tuner'
        Folder = 'RadeonTuner'
        Version = 'v0.40.0.0'
        ExpectedExe = 'RadeonTuner.exe'
        Uri = 'https://github.com/dumbie/RadeonTuner/releases/download/release/RadeonTuner.zip'
        RequiredPath = '^/dumbie/RadeonTuner/releases/download/release/RadeonTuner\.zip$'
        MetadataUri = 'https://api.github.com/repos/dumbie/RadeonTuner/releases/tags/release'
        ExpectedSize = 0L
        ExpectedSha256 = ''
    }
}
$definition = $catalog[$Tool]

function Write-ToolProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    try { Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message } catch {}
}

function Save-ToolResult {
    param([bool]$Success,[string]$Message,[string]$ExecutablePath='',[string]$Version='',[string]$Sha256='')
    if (-not $ResultPath) { return }
    $payload = [pscustomobject]@{
        Success = $Success
        Tool = $Tool
        Name = $definition.Name
        Message = $Message
        ExecutablePath = $ExecutablePath
        Version = $Version
        SourceUrl = $definition.Uri
        ArchiveSha256 = $Sha256
    }
    Write-BastosJsonFile -Path $ResultPath -Data $payload
}

function Assert-PinnedGithubUri {
    param([Parameter(Mandatory)][Uri]$Uri)
    if ($Uri.Scheme -ne 'https' -or $Uri.DnsSafeHost -ne 'github.com' -or $Uri.AbsolutePath -notmatch $definition.RequiredPath) {
        throw "Lien refuse pour $($definition.Name) : le depot, la version ou le fichier ne correspond pas a la source BASTOS epinglee."
    }
}

function Get-RadeonTunerReleaseIntegrity {
    $headers = @{
        'User-Agent' = 'BASTOS-Radeon-Tools/1.2'
        'Accept' = 'application/vnd.github+json'
    }
    try {
        $release = Invoke-RestMethod -Uri $definition.MetadataUri -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    } catch {
        throw "Verification de la version Radeon Tuner impossible aupres de GitHub : $($_.Exception.Message)"
    }
    if ([string]$release.tag_name -cne 'release') { throw 'Version GitHub Radeon Tuner inattendue.' }
    $releaseVersion = [string]$release.name
    if ($releaseVersion -notmatch '^v?\d+\.\d+\.\d+\.\d+$') { throw 'Numero de version Radeon Tuner invalide sur GitHub.' }
    $assets = @($release.assets | Where-Object {
        [string]$_.name -ceq 'RadeonTuner.zip' -and
        [string]$_.browser_download_url -ceq $definition.Uri
    })
    if ($assets.Count -ne 1) { throw 'Archive officielle Radeon Tuner absente ou ambigue dans la version GitHub.' }
    $asset = $assets[0]
    $size = [int64]$asset.size
    $digest = [string]$asset.digest
    if ($size -lt 100KB -or $size -gt 50MB -or $digest -cnotmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'Metadonnees de taille ou empreinte SHA256 Radeon Tuner invalides sur GitHub.'
    }
    return [pscustomobject]@{Size=$size;Sha256=$digest.Substring(7).ToUpperInvariant();Version=$releaseVersion}
}

function Expand-SafeZip {
    param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        if ($zip.Entries.Count -lt 1 -or $zip.Entries.Count -gt 5000) { throw 'Archive ZIP vide ou anormalement volumineuse.' }
        [int64]$totalLength = 0
        foreach ($entry in $zip.Entries) { $totalLength += [int64]$entry.Length }
        if ($totalLength -gt 2GB) { throw 'Archive ZIP refusee : taille decompressee superieure a 2 Go.' }
        foreach ($entry in $zip.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Entree ZIP dangereuse refusee : $relative"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $input = $entry.Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        }
    } finally { $zip.Dispose() }
}

$fullDestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$documentsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$allowedDestinations = @(
    [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'BASTOS\Tools')).TrimEnd('\')
    [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'BASTOS\Software\Portable')).TrimEnd('\')
    [IO.Path]::GetFullPath((Join-Path $documentsRoot 'Bastos\Application\Applications portables\Radeon')).TrimEnd('\')
)
$destinationAllowed = @($allowedDestinations | Where-Object {
    $fullDestinationRoot.Equals($_, [StringComparison]::OrdinalIgnoreCase)
}).Count -gt 0

$sourceUri = [Uri]$definition.Uri
Assert-PinnedGithubUri -Uri $sourceUri
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$workRoot = Join-Path $tempBase ('BASTOS-Radeon-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $workRoot 'download.zip'
$extractRoot = Join-Path $workRoot 'Extracted'
$candidateRoot = Join-Path $workRoot 'Candidate'
$installPath = Join-Path $fullDestinationRoot $definition.Folder
$backupPath = $installPath + '.previous-' + [guid]::NewGuid().ToString('N')
$client = $null

try {
    if (-not $destinationAllowed) {
        throw "Destination refusee. Emplacements BASTOS autorises : $($allowedDestinations -join ' ; ')"
    }
    New-Item -ItemType Directory -Path $workRoot,$candidateRoot,$fullDestinationRoot -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $workRoot '.bastos-radeon-download') -Force | Out-Null
    Write-ToolProgress 3 $definition.Name 'Connexion au depot GitHub epingle...'

    $expectedSize = [int64]$definition.ExpectedSize
    $expectedSha256 = [string]$definition.ExpectedSha256
    if ($Tool -eq 'RadeonTuner') {
        Write-ToolProgress 3 $definition.Name 'Verification de la taille et du SHA256 publies par GitHub...'
        $integrity = Get-RadeonTunerReleaseIntegrity
        $expectedSize = $integrity.Size
        $expectedSha256 = $integrity.Sha256
        $installedExe = Join-Path $installPath $definition.ExpectedExe
        $installedMetadataPath = Join-Path $installPath 'BASTOS-Source.json'
        if ((Test-Path -LiteralPath $installedExe -PathType Leaf) -and
            (Test-Path -LiteralPath $installedMetadataPath -PathType Leaf)) {
            try {
                $installedMetadata = Get-Content -LiteralPath $installedMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$installedMetadata.ArchiveSha256 -eq $expectedSha256) {
                    Write-ToolProgress 100 $definition.Name "Deja a jour - version $($integrity.Version)"
                    Save-ToolResult -Success $true -Message "$($definition.Name) est deja a jour ($($integrity.Version))." -ExecutablePath $installedExe -Version $integrity.Version -Sha256 $expectedSha256
                    Write-Output "$($definition.Name) deja a jour : $installedExe"
                    return
                }
            } catch {
                # Une ancienne fiche illisible n'empeche pas de reinstaller l'archive verifiee.
            }
        }
    }

    $downloaded = $false
    $downloadFailure = ''
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $response = $null
        $input = $null
        $output = $null
        try {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
            $handler = [Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $true
            $client = [Net.Http.HttpClient]::new($handler)
            $client.Timeout = [TimeSpan]::FromMinutes(15)
            $client.DefaultRequestHeaders.UserAgent.ParseAdd('BASTOS-Radeon-Tools/1.1')
            Write-ToolProgress 3 $definition.Name ("Connexion GitHub - tentative {0}/3..." -f $attempt)
            $response = $client.GetAsync($sourceUri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode() | Out-Null
            $finalUri = $response.RequestMessage.RequestUri
            $allowedDownloadHosts = @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com')
            if ($finalUri.Scheme -ne 'https' -or $finalUri.DnsSafeHost -notin $allowedDownloadHosts) {
                throw "Redirection GitHub refusee : $($finalUri.DnsSafeHost)"
            }

            $total = $response.Content.Headers.ContentLength
            $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $output = [IO.File]::Open($archivePath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $buffer = New-Object byte[] 1048576
            [int64]$received = 0
            while (($read = $input.Read($buffer,0,$buffer.Length)) -gt 0) {
                $output.Write($buffer,0,$read)
                $received += $read
                $percent = if($total -and $total -gt 0){[Math]::Min(78,3 + [int](75 * $received / $total))}else{35}
                Write-ToolProgress $percent $definition.Name ("{0:N1} Mo recus" -f ($received / 1MB))
            }
            $downloaded = $true
            break
        } catch {
            $downloadFailure = $_.Exception.Message
            if ($attempt -lt 3) {
                Write-ToolProgress 3 $definition.Name ("Echec temporaire : {0}. Nouvelle tentative..." -f $downloadFailure)
                Start-Sleep -Seconds (2 * $attempt)
            }
        } finally {
            if ($output) { $output.Dispose() }
            if ($input) { $input.Dispose() }
            if ($response) { $response.Dispose() }
            if ($client) { $client.Dispose(); $client = $null }
        }
    }
    if (-not $downloaded) {
        throw "Telechargement de $($definition.Name) impossible apres trois tentatives : $downloadFailure"
    }

    $archiveInfo = Get-Item -LiteralPath $archivePath
    if ($archiveInfo.Length -ne $expectedSize) {
        throw "Taille archive inattendue pour $($definition.Name) : $($archiveInfo.Length) octets au lieu de $expectedSize."
    }
    $header = [IO.File]::ReadAllBytes($archivePath)[0..1]
    if ($header[0] -ne 0x50 -or $header[1] -ne 0x4B) { throw 'Le fichier telecharge ne possede pas une signature ZIP valide.' }
    $sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($sha256 -ne $expectedSha256) {
        throw "Empreinte SHA256 refusee pour $($definition.Name). Attendue : $expectedSha256. Obtenue : $sha256."
    }

    Write-ToolProgress 82 'Verification' 'Extraction securisee et recherche de executable attendu...'
    Expand-SafeZip -Archive $archivePath -Destination $extractRoot
    $expected = Get-ChildItem -LiteralPath $extractRoot -Filter $definition.ExpectedExe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $expected) { throw "Executable attendu absent de archive : $($definition.ExpectedExe)" }

    $topItems = @(Get-ChildItem -LiteralPath $extractRoot -Force)
    $copyRoot = if($topItems.Count -eq 1 -and $topItems[0].PSIsContainer){$topItems[0].FullName}else{$extractRoot}
    foreach ($item in @(Get-ChildItem -LiteralPath $copyRoot -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $candidateRoot -Recurse -Force
    }
    if ($Tool -eq 'RadeonTuner' -and (Test-Path -LiteralPath $installPath -PathType Container)) {
        if (Get-Process -Name RadeonTuner -ErrorAction SilentlyContinue) {
            throw 'Ferme Radeon Tuner avant de lancer sa mise a jour.'
        }
        $previousSettings = Join-Path $installPath 'Settings'
        if (Test-Path -LiteralPath $previousSettings -PathType Container) {
            $settingsInfo = Get-Item -LiteralPath $previousSettings -Force
            if ($settingsInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Dossier de reglages Radeon Tuner non standard : mise a jour interrompue.'
            }
            $candidateSettings = Join-Path $candidateRoot 'Settings'
            New-Item -ItemType Directory -Path $candidateSettings -Force | Out-Null
            foreach ($setting in @(Get-ChildItem -LiteralPath $previousSettings -Force)) {
                if ($setting.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Reglage Radeon Tuner non standard : $($setting.Name)"
                }
                Copy-Item -LiteralPath $setting.FullName -Destination $candidateSettings -Recurse -Force
            }
        }
    }
    $candidateExe = Get-ChildItem -LiteralPath $candidateRoot -Filter $definition.ExpectedExe -File -Recurse | Select-Object -First 1
    if (-not $candidateExe) { throw 'La preparation locale de outil a echoue.' }
    $relativeExe = $candidateExe.FullName.Substring($candidateRoot.Length).TrimStart('\')
    $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($candidateExe.FullName).ProductVersion
    $reportedVersion = if($fileVersion){$fileVersion}elseif($Tool -eq 'RadeonTuner'){$integrity.Version}else{$definition.Version}
    $metadata = [pscustomobject]@{
        Tool = $Tool
        Name = $definition.Name
        Version = $reportedVersion
        SourceUrl = $definition.Uri
        ArchiveSha256 = $sha256
        ExpectedArchiveSha256 = $expectedSha256
        DownloadedUtc = [DateTime]::UtcNow.ToString('o')
        Executable = $relativeExe
    }
    [IO.File]::WriteAllText((Join-Path $candidateRoot 'BASTOS-Source.json'), ($metadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

    Write-ToolProgress 94 'Installation portable' 'Remplacement atomique de la copie locale...'
    if (Test-Path -LiteralPath $installPath) { Move-Item -LiteralPath $installPath -Destination $backupPath }
    try {
        Move-Item -LiteralPath $candidateRoot -Destination $installPath
    } catch {
        if ((Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $installPath)) {
            Move-Item -LiteralPath $backupPath -Destination $installPath
        }
        throw
    }
    if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Recurse -Force }

    $installedExe = Join-Path $installPath $relativeExe
    if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) { throw 'Executable introuvable apres installation portable.' }
    Write-ToolProgress 100 $definition.Name ("Pret - version {0}" -f $reportedVersion)
    Save-ToolResult -Success $true -Message "$($definition.Name) est pret." -ExecutablePath $installedExe -Version $reportedVersion -Sha256 $sha256
    Write-Output "$($definition.Name) pret : $installedExe - SHA256 $sha256"
} catch {
    Save-ToolResult -Success $false -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
} finally {
    if ($client) { $client.Dispose() }
    $resolvedWorkRoot = [IO.Path]::GetFullPath($workRoot)
    if ($resolvedWorkRoot.StartsWith($tempBase + '\BASTOS-Radeon-', [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath (Join-Path $resolvedWorkRoot '.bastos-radeon-download'))) {
        Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
