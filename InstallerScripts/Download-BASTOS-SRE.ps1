[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$downloadUri=[Uri]'https://www.monitortests.com/download/sre/sre-1.0.zip'
$expectedExeHash='A16E2E3B2485FFA250FDB924646E1A7406A2E5EEEC33CB0731D7DB4A0714D74F'
$expectedExeLength=432128
$tempZip=Join-Path ([IO.Path]::GetTempPath()) ("BASTOS-SRE-{0}.zip" -f [guid]::NewGuid().ToString('N'))
$tempExe=$OutputPath+'.download'

function Write-ProgressState([int]$Percent,[string]$Phase,[string]$Message){
    $parent=Split-Path -Parent $ProgressPath
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ProgressPath,("{0}`t{1}`t{2}" -f $Percent,$Phase,$Message),[Text.UTF8Encoding]::new($true))
}
function Save-Result([bool]$Success,[string]$Message){
    $parent=Split-Path -Parent $ResultPath
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ResultPath,([pscustomobject]@{Success=$Success;Message=$Message;OutputPath=$OutputPath}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}

$client=$null
try{
    if(-not[IO.Path]::IsPathRooted($OutputPath) -or [IO.Path]::GetExtension($OutputPath) -ine '.exe'){throw 'Destination SRE invalide.'}
    $parent=Split-Path -Parent $OutputPath
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Le dossier Bureau est introuvable.'}
    Write-ProgressState 5 'Scaled Resolution Editor' 'Connexion à la source officielle ToastyX...'
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect=$true
    $client=[Net.Http.HttpClient]::new($handler)
    $client.Timeout=[TimeSpan]::FromMinutes(10)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 BASTOS-SRE/1.0')
    $response=$client.GetAsync($downloadUri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    [void]$response.EnsureSuccessStatusCode()
    $finalUri=$response.RequestMessage.RequestUri
    if($finalUri.Scheme -ne 'https' -or $finalUri.DnsSafeHost -notin @('www.monitortests.com','monitortests.com')){throw "Redirection SRE refusée : $($finalUri.AbsoluteUri)"}
    $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $output=[IO.File]::Open($tempZip,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{
        $buffer=New-Object byte[] 131072
        [int64]$received=0
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $output.Write($buffer,0,$read)
            $received+=$read
            Write-ProgressState 45 'Scaled Resolution Editor' ("{0:N1} Mo téléchargés depuis monitortests.com" -f ($received/1MB))
        }
    }finally{$output.Dispose();$input.Dispose();$response.Dispose()}
    if((Get-Item -LiteralPath $tempZip).Length -lt 100000){throw 'Archive SRE officielle anormalement petite.'}
    Write-ProgressState 65 'Scaled Resolution Editor' 'Vérification de l archive et de SRE.exe...'
    $archive=[IO.Compression.ZipFile]::OpenRead($tempZip)
    try{
        $entries=@($archive.Entries|Where-Object{[IO.Path]::GetFileName($_.FullName) -ieq 'SRE.exe' -and -not $_.FullName.Contains('..')})
        if($entries.Count -ne 1){throw 'L archive officielle ne contient pas un unique SRE.exe.'}
        if([int64]$entries[0].Length -ne $expectedExeLength){throw 'La taille de SRE.exe ne correspond pas à la version intégrée.'}
        Remove-Item -LiteralPath $tempExe -Force -ErrorAction SilentlyContinue
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$tempExe,$true)
    }finally{$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $tempExe -Algorithm SHA256).Hash
    if(-not[string]::Equals($hash,$expectedExeHash,[StringComparison]::OrdinalIgnoreCase)){throw 'Empreinte SHA-256 SRE.exe invalide.'}
    Write-ProgressState 90 'Scaled Resolution Editor' 'Copie vérifiée vers le Bureau...'
    Move-Item -LiteralPath $tempExe -Destination $OutputPath -Force
    Write-ProgressState 100 'Scaled Resolution Editor' 'SRE.exe est prêt sur le Bureau.'
    Save-Result $true 'Scaled Resolution Editor 1.0 telecharge depuis la source officielle et verifie.'
    exit 0
}catch{
    Save-Result $false $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
}finally{
    if($client){$client.Dispose()}
    Remove-Item -LiteralPath $tempZip,$tempExe -Force -ErrorAction SilentlyContinue
}
