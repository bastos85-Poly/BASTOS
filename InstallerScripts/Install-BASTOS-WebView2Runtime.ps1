[CmdletBinding()]
param(
    [string]$ResultPath,
    [string]$BootstrapperUri = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
    [string]$ProgressPath = '',
    [string]$OperationId = '',
    [switch]$DownloadOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$runtimeGuid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$evidence = @{ Status='Error'; Version=''; InstallerStarted=$false; InstallerExitCode=$null; ActionCompletionUnconfirmed=$false }
$partialPath = $null
$install = $null
$stage = 'Detection'
function Get-BastosWebView2Version {
    $versions = @()
    foreach ($path in @(
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$runtimeGuid",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\EdgeUpdate\Clients\$runtimeGuid",
        "Registry::HKEY_CURRENT_USER\Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\$runtimeGuid",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\EdgeUpdate\Clients\$runtimeGuid"
    )) {
        try {
            $text = (Get-ItemProperty -LiteralPath $path -Name pv -ErrorAction Stop).pv
            $version = $null
            if ($text -is [string] -and [version]::TryParse($text, [ref]$version) -and $version -gt [version]'0.0.0.0') { $versions += $version }
        } catch {}
    }
    $newest = $versions | Sort-Object -Descending | Select-Object -First 1
    if ($newest) { return $newest.ToString() }
    return $null
}
function Progress([int]$Percent,[string]$Phase,[string]$Message) {
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}
function Report([bool]$Success,[string]$Message) {
    if ($ResultPath) { Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $Success -Message $Message -Data $evidence }
}
try {
    if (-not $OperationId) { $OperationId = [guid]::NewGuid().ToString('N') }
    if ($OperationId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Identifiant d operation invalide.' }
    Progress 2 'Detection de WebView2' 'Lecture de la version enregistree dans Windows...'
    $installedVersion = Get-BastosWebView2Version
    if ($installedVersion -and -not $DownloadOnly) {
        $evidence.Status='AlreadyInstalled'; $evidence.Version=$installedVersion
        Report $true "WebView2 $installedVersion est deja detecte."
        exit 0
    }
    # Keep the bootstrapper link fixed to the documented Evergreen installer.
    if (-not [string]::Equals($BootstrapperUri,'https://go.microsoft.com/fwlink/p/?LinkId=2124703',[StringComparison]::OrdinalIgnoreCase)) {
        $evidence.ErrorCode='WEBVIEW2_LINK_REFUSED'
        throw 'Le lien du bootstrapper WebView2 ne correspond pas au lien officiel Microsoft autorise.'
    }
    # A previously launched bootstrapper can outlive its worker. Do not launch another one.
    if (-not $DownloadOnly) {
        $active = @(Get-Process -Name 'MicrosoftEdgeWebview2Setup' -ErrorAction SilentlyContinue)
        if ($active.Count -gt 0) {
            $evidence.Status='Pending'; $evidence.ActionCompletionUnconfirmed=$true; $evidence.ActiveInstallerIds=@($active | ForEach-Object { $_.Id })
            Report $false 'Une installation WebView2 est deja active.'
            exit 1
        }
    }
    $toolRoot = Join-Path $env:LOCALAPPDATA ('BASTOS\Tools\WebView2\' + $OperationId)
    [IO.Directory]::CreateDirectory($toolRoot) | Out-Null
    $installerPath = Join-Path $toolRoot 'MicrosoftEdgeWebview2Setup.exe'
    $partialPath = $installerPath + '.partial'
    Progress 10 'Telechargement de WebView2' 'Recuperation du bootstrapper Microsoft...'
    $stage='Download'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect = $true
    $client = [Net.Http.HttpClient]::new($handler)
    $cancel = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(5))
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('BASTOS-WebView2/1.0')
    try {
        $response = $client.GetAsync([uri]$BootstrapperUri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            $finalUri = $response.RequestMessage.RequestUri
            $hostName = $finalUri.DnsSafeHost.TrimEnd('.')
            if ($finalUri.Scheme -ne 'https' -or $finalUri.UserInfo -or -not $finalUri.IsDefaultPort -or
                -not ($hostName -eq 'microsoft.com' -or $hostName.EndsWith('.microsoft.com',[StringComparison]::OrdinalIgnoreCase) -or
                      $hostName -eq 'msedge.net' -or $hostName.EndsWith('.msedge.net',[StringComparison]::OrdinalIgnoreCase))) {
                throw 'La redirection du bootstrapper WebView2 ne mene pas a un domaine Microsoft autorise.'
            }
            $expected = $response.Content.Headers.ContentLength
            if ($null -eq $expected -or $expected -lt 1MB -or $expected -gt 20MB) { throw 'Taille annoncee du bootstrapper absente ou incorrecte.' }
            $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            try {
                $output = [IO.File]::Open($partialPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $input.CopyToAsync($output,81920,$cancel.Token).GetAwaiter().GetResult() | Out-Null; $output.Flush($true) }
                finally { $output.Dispose() }
            } finally { $input.Dispose() }
            if ((Get-Item -LiteralPath $partialPath).Length -ne $expected) { throw 'Taille du bootstrapper telecharge incorrecte.' }
            $evidence.FinalUrl=$finalUri.AbsoluteUri; $evidence.ExpectedLength=[long]$expected
        } finally { $response.Dispose() }
    } finally { $cancel.Dispose(); $client.Dispose(); $handler.Dispose() }
    [IO.File]::Move($partialPath,$installerPath)
    Progress 55 'Verification de la signature' 'Controle de la signature Microsoft et de l empreinte...'
    $stage='Signature'
    $signature = Get-AuthenticodeSignature -LiteralPath $installerPath
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Signature du bootstrapper WebView2 invalide : $($signature.Status)."
    }
    $evidence.Path=$installerPath; $evidence.FileLength=[long](Get-Item -LiteralPath $installerPath).Length
    $evidence.Sha256=Get-BastosFileSha256 -Path $installerPath
    $evidence.SignatureStatus=[string]$signature.Status; $evidence.SignerSubject=$signature.SignerCertificate.Subject
    if ($DownloadOnly) { $evidence.Status='Downloaded'; Report $true 'Bootstrapper Microsoft telecharge et signe, non execute.'; exit 0 }
    Progress 65 'Installation de WebView2' 'Installation silencieuse ; aucun arret force de l installateur...'
    $stage='Installation'
    $install = Start-Process -FilePath $installerPath -ArgumentList '/silent','/install' -PassThru -WindowStyle Hidden
    if (-not $install) { throw 'Windows n a pas retourne le processus de l installateur.' }
    $evidence.InstallerStarted=$true; $evidence.InstallerProcessId=$install.Id
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    do {
        $installedVersion = Get-BastosWebView2Version
        if ($installedVersion) { break }
        if ($install.HasExited -and $install.ExitCode -notin @(0,3010)) { throw "Installation WebView2 en echec (code $($install.ExitCode))." }
        Start-Sleep -Milliseconds 750
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($install.HasExited) { $evidence.InstallerExitCode=$install.ExitCode }
    if (-not $installedVersion) {
        # Edge Update may continue in a child after the bootstrapper exits.
        $evidence.Status='Pending'; $evidence.ActionCompletionUnconfirmed=$true
        Report $false 'Installation lancee mais sa fin et la presence de WebView2 ne sont pas confirmees.'
        exit 1
    }
    $evidence.Status='Installed'; $evidence.Version=$installedVersion
    Progress 98 'Verification de WebView2' 'Enregistrement de la version detectee...'
    Report $true "WebView2 $installedVersion est detecte apres installation."
    exit 0
} catch {
    $evidence.Status='Error'
    if (-not $evidence.ContainsKey('ErrorCode')) {
        $evidence.ErrorCode=switch($stage) { 'Download' {'WEBVIEW2_DOWNLOAD_FAILED'} 'Signature' {'WEBVIEW2_SIGNATURE_INVALID'} 'Installation' {'WEBVIEW2_INSTALL_FAILED'} default {'WEBVIEW2_DETECTION_FAILED'} }
    }
    if ($install) {
        $evidence.ActionCompletionUnconfirmed=$true
        try {
            if ($install.HasExited) {
                $evidence.InstallerExitCode=$install.ExitCode
                if ($install.ExitCode -notin @(0,3010)) { $evidence.ActionCompletionUnconfirmed=$false }
            }
        } catch { }
    }
    try { Report $false $_.Exception.Message } catch { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
} finally {
    if ($install) { $install.Dispose() }
    if ($partialPath -and [IO.File]::Exists($partialPath)) { [IO.File]::Delete($partialPath) }
}
