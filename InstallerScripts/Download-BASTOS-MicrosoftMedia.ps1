[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ProgressPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop

function Write-DownloadProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}

$downloadUri = [Uri]$Uri
if (-not $downloadUri.IsAbsoluteUri -or $downloadUri.Scheme -ne 'https' -or $downloadUri.DnsSafeHost -ne 'go.microsoft.com') {
    throw 'Seuls les liens HTTPS officiels go.microsoft.com sont autorises par ce worker.'
}
$parentPath = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parentPath)) { New-Item -ItemType Directory -Path $parentPath -Force | Out-Null }
$partialPath = $OutputPath + '.partial'
Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Net.Http
$handler = New-Object Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $true
$client = New-Object Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromHours(2)
try {
    Write-DownloadProgress 2 'Microsoft' 'Connexion au service de telechargement officiel...'
    $response = $client.GetAsync($downloadUri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null
    $finalUri = $response.RequestMessage.RequestUri
    $finalHost = $finalUri.DnsSafeHost.ToLowerInvariant()
    if ($finalHost -ne 'go.microsoft.com' -and -not $finalHost.EndsWith('.microsoft.com')) {
        throw "Le redirecteur Microsoft a renvoye vers un domaine non autorise : $finalHost"
    }
    $total = if($response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength}else{0L}
    $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $output = [IO.File]::Open($partialPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = New-Object byte[] (1024 * 256)
        $received = 0L
        $lastPercent = -1
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $output.Write($buffer, 0, $read)
            $received += $read
            $percent = if($total -gt 0){[math]::Min(96,[int](5 + (91 * $received / $total)))}else{[math]::Min(90,5 + [int]($received / 1MB))}
            if ($percent -ne $lastPercent) {
                $sizeText = if($total -gt 0){'{0:N1} / {1:N1} Mo' -f ($received/1MB),($total/1MB)}else{'{0:N1} Mo' -f ($received/1MB)}
                Write-DownloadProgress $percent 'Telechargement Microsoft' $sizeText
                $lastPercent = $percent
            }
        }
    } finally {
        if ($output) { $output.Dispose() }
        if ($input) { $input.Dispose() }
        if ($response) { $response.Dispose() }
    }
    $downloadedFile = Get-Item -LiteralPath $partialPath
    if ($downloadedFile.Length -lt 1MB) {
        throw 'Le fichier Microsoft telecharge est anormalement petit.'
    }
    Write-DownloadProgress 97 'Verification Microsoft' 'Controle de la signature numerique avant enregistrement...'
    $signature = Get-AuthenticodeSignature -LiteralPath $partialPath
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?i)Microsoft') {
        throw "Signature Microsoft invalide ou absente : $($signature.Status)"
    }
    $hash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash
    Move-Item -LiteralPath $partialPath -Destination $OutputPath -Force
    Write-DownloadProgress 100 'Termine' ("Outil Microsoft enregistre : {0}" -f $OutputPath)
    Write-Output ("Fichier Microsoft signe : {0}`r`nSHA256 : {1}`r`nSignataire : {2}" -f $OutputPath,$hash,$signature.SignerCertificate.Subject)
} catch {
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    Write-DownloadProgress 0 'Erreur' $_.Exception.Message
    throw
} finally {
    $client.Dispose()
    $handler.Dispose()
}
