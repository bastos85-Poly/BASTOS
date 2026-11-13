[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ProgressPath,
    [string]$ResultPath,
    [string]$OperationId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-DownloadProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    try { Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message } catch {}
}

function Save-Result {
    param([bool]$Success,[string]$Message,[string]$Version='',[hashtable]$Evidence=@{})
    if (-not $ResultPath) { return }
    $payload = @{ Version=$Version; Path=$OutputPath }
    foreach ($key in $Evidence.Keys) { $payload[$key] = $Evidence[$key] }
    Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $Success -Message $Message -Data $payload
}

$tempPath = $OutputPath + '.download'
$client = $null
try {
    Write-DownloadProgress 2 'Rufus officiel' 'Recherche de la derniere version stable sur GitHub...'
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(15)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('BASTOS-Rufus-Downloader/1.0')
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')

    $apiUri = [Uri]'https://api.github.com/repos/pbatard/rufus/releases/latest'
    $releaseText = $client.GetStringAsync($apiUri).GetAwaiter().GetResult()
    $release = $releaseText | ConvertFrom-Json
    $asset = @($release.assets | Where-Object { $_.name -match '^rufus-[0-9]+\.[0-9]+\.exe$' }) | Select-Object -First 1
    if (-not $asset) { throw 'Aucun executable Rufus x64 standard trouve dans la derniere version officielle.' }
    $downloadUri = [Uri]$asset.browser_download_url
    if ($downloadUri.Scheme -ne 'https' -or $downloadUri.DnsSafeHost -ne 'github.com' -or $downloadUri.AbsolutePath -notmatch '^/pbatard/rufus/releases/download/') {
        throw 'Le lien Rufus retourne par GitHub ne correspond pas au depot officiel pbatard/rufus.'
    }

    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Write-DownloadProgress 8 'Rufus officiel' ("Telechargement de {0}..." -f $asset.name)
    $response = $client.GetAsync($downloadUri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode()
    $finalUri = $response.RequestMessage.RequestUri
    if ($finalUri.Scheme -ne 'https' -or $finalUri.DnsSafeHost -notin @('github.com','release-assets.githubusercontent.com')) {
        throw "Redirection Rufus refusee : $($finalUri.DnsSafeHost)"
    }
    $total = $response.Content.Headers.ContentLength
    $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $output = [IO.File]::Open($tempPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = New-Object byte[] 1048576
        [int64]$received = 0
        while (($read = $input.Read($buffer,0,$buffer.Length)) -gt 0) {
            $output.Write($buffer,0,$read)
            $received += $read
            $percent = if($total -and $total -gt 0){[Math]::Min(92, 8 + [int](84 * $received / $total))}else{45}
            Write-DownloadProgress $percent 'Rufus officiel' ("{0:N1} Mo recus" -f ($received / 1MB))
        }
    } finally {
        $output.Dispose()
        $input.Dispose()
        $response.Dispose()
    }

    Write-DownloadProgress 94 'Verification de securite' 'Controle de la signature numerique Akeo Consulting...'
    if ($received -ne [long]$asset.size -or ($total -and $received -ne $total)) { throw 'Le fichier Rufus est incomplet : taille differente des metadonnees officielles.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $tempPath
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)Akeo Consulting') {
        throw "Signature Rufus invalide ou editeur inattendu : $($signature.Status)"
    }
    Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($OutputPath).ProductVersion
    Write-DownloadProgress 98 'Verification de l integrite' 'Calcul de l empreinte du fichier signe...'
    $evidence = @{ Sha256=(Get-BastosFileSha256 -Path $OutputPath); FileLength=([IO.FileInfo]$OutputPath).Length; ExpectedLength=[long]$asset.size; SignatureStatus=[string]$signature.Status; SignerSubject=$signature.SignerCertificate.Subject }
    Save-Result -Success $true -Message 'Rufus officiel telecharge et verifie.' -Version $version -Evidence $evidence
    Write-DownloadProgress 100 'Rufus pret' ("Version {0}, signature Akeo Consulting valide" -f $version)
    Write-Output "Rufus officiel pret : $OutputPath - version $version"
} catch {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Save-Result -Success $false -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
} finally {
    if ($client) { $client.Dispose() }
}
