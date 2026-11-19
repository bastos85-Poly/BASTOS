[CmdletBinding()]
param(
    [ValidateSet('x64','x86')]
    [string]$Architecture = 'x64',

    [Parameter(Mandatory)]
    [ValidateLength(2, 80)]
    [string]$Language,

    [ValidateLength(2, 80)]
    [string]$LanguageDisplay = $Language,

    [string]$DownloadDirectory,

    [string]$ResultPath,

    [ValidateSet('RetailCurrent','Retail25H2','Windows10Current','Insider26H2')]
    [string]$Release = 'RetailCurrent',

    [string]$CancelPath,

    [switch]$LinkOnly,

    [switch]$InterceptDownloadTest,

    [switch]$Hidden,

    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Le chemin des modules peut contenir PowerShell 7 avant Windows PowerShell.
# Charger explicitement la version native pour verifier les signatures Microsoft.
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$progressMirrorRoot = Join-Path $env:LOCALAPPDATA 'BASTOS'
$progressMirrorPath = Join-Path $progressMirrorRoot 'WindowsIso-DownloadProgress.json'
$script:AvailableLanguages=@()

function Write-BastosIsoResult {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Uri,
        [string]$FilePath,
        [long]$Bytes = 0,
        [long]$TotalBytes = 0
    )
    $result = [ordered]@{
        Status = $Status
        Message = $Message
        Architecture = $Architecture
        Language = $Language
        LanguageDisplay = $LanguageDisplay
        Release = $Release
        Uri = $Uri
        FilePath = $FilePath
        Bytes = $Bytes
        TotalBytes = $TotalBytes
        AvailableLanguages = @($script:AvailableLanguages)
        WorkerPid = $PID
        Date = (Get-Date).ToString('o')
    }
    $json = $result | ConvertTo-Json -Depth 4
    if ($ResultPath) {
        $parent = Split-Path -Parent $ResultPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        # Publier chaque instantané de manière atomique : l'interface ne doit
        # jamais lire un JSON tronqué pendant les nombreux événements de progression.
        $temporaryResult = "$ResultPath.$([guid]::NewGuid().ToString('N')).tmp"
        [IO.File]::WriteAllText($temporaryResult, $json, [Text.UTF8Encoding]::new($true))
        if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
            # PowerShell transforme parfois $null en chemin vide pour la surcharge
            # Replace(..., backup, ...), ce qui provoque "Le chemin d'accès n'a
            # pas une forme correcte". Fournir un vrai chemin de sauvegarde
            # temporaire conserve la publication atomique sans cette ambiguite.
            $backupResult = "$ResultPath.$([guid]::NewGuid().ToString('N')).bak"
            try {
                [IO.File]::Replace($temporaryResult,$ResultPath,$backupResult,$true)
            } finally {
                Remove-Item -LiteralPath $backupResult -Force -ErrorAction SilentlyContinue
            }
        } else {
            Move-Item -LiteralPath $temporaryResult -Destination $ResultPath -Force
        }
    }
    try {
        if(-not (Test-Path -LiteralPath $progressMirrorRoot -PathType Container)){
            New-Item -ItemType Directory -Path $progressMirrorRoot -Force | Out-Null
        }
        # Miroir simple et prévisible lu par l'interface. Il reste disponible
        # même si le fichier de résultat temporaire est remplacé ou supprimé.
        $mirrorStream=[IO.FileStream]::new(
            $progressMirrorPath,
            [IO.FileMode]::Create,
            [IO.FileAccess]::Write,
            [IO.FileShare]::ReadWrite
        )
        try{
            $mirrorBytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
            $mirrorStream.Write($mirrorBytes,0,$mirrorBytes.Length)
            $mirrorStream.Flush($true)
        }finally{$mirrorStream.Dispose()}
    } catch {}
    Write-Output $json
}

function Test-BastosMicrosoftUri {
    param([Parameter(Mandatory)][string]$Uri)
    try {
        $parsed = [Uri]$Uri
        if (-not $parsed.IsAbsoluteUri -or $parsed.Scheme -ne 'https') { return $false }
        $dnsHost = $parsed.DnsSafeHost.ToLowerInvariant()
        return $dnsHost -eq 'microsoft.com' -or $dnsHost.EndsWith('.microsoft.com')
    } catch {
        return $false
    }
}

function Test-BastosMicrosoftSignInUri {
    param([Parameter(Mandatory)][string]$Uri)
    try {
        $parsed = [Uri]$Uri
        if (-not $parsed.IsAbsoluteUri -or $parsed.Scheme -ne 'https') { return $false }
        $dnsHost = $parsed.DnsSafeHost.ToLowerInvariant()
        return $dnsHost -eq 'microsoft.com' -or $dnsHost.EndsWith('.microsoft.com') -or
            $dnsHost -eq 'live.com' -or $dnsHost.EndsWith('.live.com') -or
            $dnsHost -eq 'microsoftonline.com' -or $dnsHost.EndsWith('.microsoftonline.com')
    } catch {
        return $false
    }
}

function Get-BastosDownloadsDirectory {
    if ($DownloadDirectory) {
        return [IO.Path]::GetFullPath($DownloadDirectory)
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        $knownFolder = $shell.Namespace('shell:Downloads')
        if ($knownFolder -and $knownFolder.Self -and $knownFolder.Self.Path) {
            return [string]$knownFolder.Self.Path
        }
    } catch {}
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Get-BastosIsoOutputPath {
    param([Parameter(Mandatory)][string]$Uri)
    $directory = Get-BastosDownloadsDirectory
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $parsed = [Uri]$Uri
    $fileName = [Uri]::UnescapeDataString([IO.Path]::GetFileName($parsed.AbsolutePath))
    if (-not $fileName -or [IO.Path]::GetExtension($fileName) -ne '.iso') {
        $safeLanguage = ($Language -replace '[^A-Za-z0-9]+','-').Trim('-')
        $releaseName = if ($Release -eq 'Insider26H2') { 'Insider' } else { 'Public' }
        $fileName = "Windows11-$releaseName-$safeLanguage-$Architecture.iso"
    }
    $fileName = [string]::Join('_', $fileName.Split([IO.Path]::GetInvalidFileNameChars()))
    $candidate = Join-Path $directory $fileName
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [IO.Path]::GetExtension($fileName)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $counter = 0
    do {
        $suffix = if ($counter -eq 0) { $timestamp } else { "$timestamp-$counter" }
        $candidate = Join-Path $directory "$stem-$suffix$extension"
        $counter++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Assert-BastosWebView2Files {
    $webViewRoot = Join-Path $PSScriptRoot 'WebView2'
    $required = @(
        'Microsoft.Web.WebView2.Core.dll',
        'Microsoft.Web.WebView2.WinForms.dll',
        'WebView2Loader.dll'
    )
    foreach ($fileName in $required) {
        $path = Join-Path $webViewRoot $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Composant WebView2 manquant : $path"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?i)Microsoft') {
            throw "Composant WebView2 refuse : signature Microsoft invalide pour $fileName."
        }
    }
    return $webViewRoot
}

function Remove-BastosWebView2SessionFolder {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $expectedPrefix = $tempRoot + '\BASTOS-WebView2-WindowsIso-'
        if (-not $fullPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.Length -le ($expectedPrefix.Length + 20)) {
            return
        }
        if (Test-Path -LiteralPath $fullPath -PathType Container) {
            Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

if ($Language -notmatch '^[A-Za-z() -]+$') {
    throw 'La langue demandee contient un caractere non autorise.'
}
if ($Architecture -ne 'x64' -and $Release -ne 'Windows10Current') {
    throw 'Ce prototype BASTOS prend uniquement en charge ISO Windows 11 x64.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$streamingDownloaderSource = @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

public sealed class BastosStreamingDownloader : IDisposable
{
    private readonly HttpClient client;
    private readonly CancellationTokenSource cancellation = new CancellationTokenSource();
    private long bytesReceived;
    private long totalBytes;
    private Task worker;

    public bool IsCompleted { get; private set; }
    public bool Succeeded { get; private set; }
    public bool WasCancelled { get; private set; }
    public string ErrorMessage { get; private set; }
    public long BytesReceived { get { return Interlocked.Read(ref bytesReceived); } }
    public long TotalBytes { get { return Interlocked.Read(ref totalBytes); } }

    public BastosStreamingDownloader()
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        var handler = new HttpClientHandler();
        handler.AllowAutoRedirect = true;
        handler.AutomaticDecompression = DecompressionMethods.None;
        client = new HttpClient(handler);
        client.Timeout = Timeout.InfiniteTimeSpan;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0");
        client.DefaultRequestHeaders.Referrer =
            new Uri("https://www.microsoft.com/software-download/windows11");
    }

    public void Start(string uri, string destinationPath)
    {
        if (worker != null) throw new InvalidOperationException("Le téléchargement est déjà lancé.");
        worker = DownloadAsync(new Uri(uri), destinationPath, cancellation.Token);
    }

    private async Task DownloadAsync(Uri uri, string destinationPath, CancellationToken token)
    {
        try
        {
            using (var response = await client.GetAsync(
                uri, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();
                if (response.Content.Headers.ContentLength.HasValue)
                    Interlocked.Exchange(ref totalBytes, response.Content.Headers.ContentLength.Value);

                using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                using (var output = new FileStream(
                    destinationPath, FileMode.Create, FileAccess.Write, FileShare.Read,
                    1024 * 1024, true))
                {
                    var buffer = new byte[1024 * 1024];
                    while (true)
                    {
                        int read = await input.ReadAsync(buffer, 0, buffer.Length, token)
                            .ConfigureAwait(false);
                        if (read <= 0) break;
                        await output.WriteAsync(buffer, 0, read, token).ConfigureAwait(false);
                        Interlocked.Add(ref bytesReceived, read);
                    }
                    await output.FlushAsync(token).ConfigureAwait(false);
                }
            }
            Succeeded = true;
        }
        catch (OperationCanceledException)
        {
            WasCancelled = true;
            ErrorMessage = "Téléchargement annulé.";
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsCompleted = true;
        }
    }

    public void Cancel()
    {
        cancellation.Cancel();
    }

    public void Dispose()
    {
        cancellation.Cancel();
        client.Dispose();
        cancellation.Dispose();
    }
}
'@
Add-Type -TypeDefinition $streamingDownloaderSource -ReferencedAssemblies 'System.Net.Http.dll'

$webViewRoot = Assert-BastosWebView2Files
Add-Type -Path (Join-Path $webViewRoot 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $webViewRoot 'Microsoft.Web.WebView2.WinForms.dll')

$form = New-Object Windows.Forms.Form
$releaseDisplay = if ($Release -eq 'Insider26H2') { 'Windows 11 Insider' } elseif($Release -eq 'Windows10Current') {'Windows 10 - version publique actuelle'} else { 'Windows 11 - version publique actuelle' }
$insiderDownloadPageUri = 'https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso'
$officialPageUri = if ($Release -eq 'Insider26H2') {
    $insiderDownloadPageUri
} else {
    if($Release -eq 'Windows10Current'){'https://www.microsoft.com/en-us/software-download/windows10ISO'}else{'https://www.microsoft.com/fr-fr/software-download/windows11#SoftwareDownload_Edition'}
}
$form.Text = "BASTOS - ISO $releaseDisplay officielle"
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object Drawing.Size(900,650)
$form.Size = New-Object Drawing.Size(1100,780)
$form.BackColor = [Drawing.Color]::FromArgb(9,10,18)
$form.ForeColor = [Drawing.Color]::White
$form.ShowIcon = $false

$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Dock = 'Top'
$statusPanel.Height = 58
$statusPanel.BackColor = [Drawing.Color]::FromArgb(17,18,28)
$form.Controls.Add($statusPanel)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Text = "Connexion a Microsoft pour $releaseDisplay $Architecture - $LanguageDisplay..."
$statusLabel.Dock = 'Fill'
$statusLabel.Padding = New-Object Windows.Forms.Padding(16,10,16,8)
$statusLabel.Font = New-Object Drawing.Font('Segoe UI Semibold',10)
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(69,200,255)
$statusPanel.Controls.Add($statusLabel)

$bottomPanel = New-Object Windows.Forms.Panel
$bottomPanel.Dock = 'Bottom'
$bottomPanel.Height = 48
$bottomPanel.BackColor = [Drawing.Color]::FromArgb(17,18,28)
$form.Controls.Add($bottomPanel)

$officialButton = New-Object Windows.Forms.Button
$officialButton.Text = 'Recharger la source Microsoft'
$officialButton.Size = New-Object Drawing.Size(250,30)
$officialButton.Location = New-Object Drawing.Point(12,9)
$officialButton.FlatStyle = 'Flat'
$officialButton.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(40,42,58)
$officialButton.BackColor = [Drawing.Color]::FromArgb(24,25,37)
$officialButton.ForeColor = [Drawing.Color]::White
$officialButton.Add_Click({
    $webView.CoreWebView2.Navigate($officialPageUri)
})
$bottomPanel.Controls.Add($officialButton)

$closeButton = New-Object Windows.Forms.Button
$closeButton.Text = 'Fermer'
$closeButton.Size = New-Object Drawing.Size(100,30)
$closeButton.Anchor = 'Top,Right'
$closeButton.Location = New-Object Drawing.Point(($form.ClientSize.Width - 122),9)
$closeButton.FlatStyle = 'Flat'
$closeButton.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(40,42,58)
$closeButton.BackColor = [Drawing.Color]::FromArgb(24,25,37)
$closeButton.ForeColor = [Drawing.Color]::White
$closeButton.Add_Click({ $form.Close() })
$bottomPanel.Controls.Add($closeButton)

$webView = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$webView.Dock = 'Fill'
$creation = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
# Une session WebView2 temporaire évite qu'un ancien compte ou une ancienne
# sélection Insider saute l'étape de connexion et le choix manuel de l'édition.
$webViewSessionFolder = Join-Path $env:TEMP ("BASTOS-WebView2-WindowsIso-{0}" -f [guid]::NewGuid().ToString('N'))
$creation.UserDataFolder = $webViewSessionFolder
$webView.CreationProperties = $creation
$form.Controls.Add($webView)
$webView.SendToBack()

if ($Hidden -and $Release -ne 'Insider26H2') {
    $form.ShowInTaskbar = $false
    $form.Opacity = 0
}

$script:Phase = 'Initializing'
$script:AutomationReady = $false
$script:AutomationTask = $null
$script:NavigationRetries = 0
$script:NextScriptAt = [datetime]::MinValue
$script:AutomationStartedAt = Get-Date
$script:PendingDownloadUri = $null
$script:PendingDownloadPath = $null
$script:PartialDownloadPath = $null
$script:StreamingDownloader = $null
$script:DownloadOperation = $null
$script:ClosingProgrammatically = $false
$script:FinalResultWritten = $false
$script:LastProgressPublishAt = [datetime]::MinValue
$script:LastInteractiveStatus = ''
$script:SignInNavigationStarted = $false
$script:MeClickTask = $null
$script:MeClickStep = 0
$script:MeClickPayloads = @()

function Set-BastosIsoStatus {
    param([string]$Text,[Drawing.Color]$Color = [Drawing.Color]::FromArgb(69,200,255))
    $statusLabel.Text = $Text
    $statusLabel.ForeColor = $Color
    $statusLabel.Refresh()
}

function Complete-BastosIsoWorker {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Uri,
        [string]$FilePath,
        [long]$Bytes = 0,
        [long]$TotalBytes = 0,
        [switch]$Close
    )
    Write-BastosIsoResult -Status $Status -Message $Message -Uri $Uri -FilePath $FilePath -Bytes $Bytes -TotalBytes $TotalBytes
    if ($Status -in @('Completed','Error','Interrupted','Cancelled','Timeout','MicrosoftError','SentinelRejected','DownloadIntercepted','LinkReady')) {
        $script:FinalResultWritten = $true
    }
    if ($Close) {
        $script:ClosingProgrammatically = $true
        $form.Close()
    }
}

$languageJson = $Language | ConvertTo-Json -Compress
$releaseJson = $Release | ConvertTo-Json -Compress
$architectureJson = $Architecture | ConvertTo-Json -Compress
$automationScript = @"
(function () {
    const requestedLanguage = $languageJson;
    const requestedRelease = $releaseJson;
    const requestedArchitecture = $architectureJson;
    const state = window.__bastosIsoAutomation || {
        stage: 'warmup',
        startedAt: Date.now(),
        stageStartedAt: Date.now(),
        signInClicked: false
    };
    window.__bastosIsoAutomation = state;
    const reply = (status, message, extra) => JSON.stringify(Object.assign({
        status: status,
        message: message,
        stage: state.stage
    }, extra || {}));
    const isVisible = element => {
        if (!element) return false;
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect ? element.getBoundingClientRect() : null;
        return style.display !== 'none' && style.visibility !== 'hidden' &&
            (!rect || (rect.width > 0 && rect.height > 0));
    };
    const visibleError = Array.from(document.querySelectorAll('#errorModalMessage'))
        .find(element => isVisible(element) && element.textContent.trim().length > 0);
    if (visibleError && state.stage === 'link') {
        return reply('site-error', visibleError.textContent.trim());
    }
    if (state.stage === 'warmup') {
        if ((Date.now() - state.startedAt) < 8000) {
            return reply('warming-up', 'Initialisation de la validation Microsoft...');
        }
        state.stage = 'edition';
        state.stageStartedAt = Date.now();
    }
    if (state.stage === 'edition') {
        // Après le clic manuel sur Confirmer, Microsoft remplace le choix de
        // l'édition par celui de la langue. Microsoft conserve toutefois les
        // deux formulaires dans le DOM et masque celui qui n'est pas actif :
        // ne changer d'étape que lorsque le formulaire langue est réellement
        // visible, sinon BASTOS annonce à tort que la langue est absente.
        const languageSelect = document.querySelector('#product-languages');
        const languageButton = document.querySelector('#submit-sku');
        const editionSelect = document.querySelector('#product-edition');
        if (isVisible(languageSelect) && isVisible(languageButton) && !isVisible(editionSelect)) {
            state.stage = 'language';
            state.stageStartedAt = Date.now();
        }
    }
    if (state.stage === 'edition') {
        const select = document.querySelector('#product-edition');
        const button = document.querySelector('#submit-product-edition');
        if (!select || !button) {
            if (requestedRelease === 'Insider26H2') {
                const currentHost = (window.location.hostname || '').toLowerCase();
                const currentPath = window.location.pathname || '';
                const isOfficialDownloadPage = (currentHost === 'microsoft.com' || currentHost.endsWith('.microsoft.com')) &&
                    /\/software-download\/windowsinsiderpreviewiso/i.test(currentPath);
                // Ne jamais automatiser les pages d'identification. Elles
                // contiennent aussi « Sign-in options » et « Create account ».
                if (!isOfficialDownloadPage) {
                    return reply('waiting-signin', 'Connecte-toi avec le compte inscrit au programme Windows Insider.', {
                        href: window.location.href
                    });
                }
                const meContainer = document.querySelector('#meControl');
                if (meContainer) {
                    const rawSettings = meContainer.getAttribute('data-signinsettings') || '';
                    if (rawSettings) {
                        try {
                            const settings = JSON.parse(rawSettings);
                            const msa = settings && settings.rpData && settings.rpData.msaInfo;
                            const signInUri = msa && (msa.signInUrl || msa.meUrl);
                            if (signInUri) {
                                return reply('signin-uri-ready', 'Adresse officielle de connexion Microsoft détectée.', {
                                    href: new URL(signInUri, window.location.href).href
                                });
                            }
                        } catch (_) {}
                    }
                }
                // Le contrôle actuellement visible peut être généré sans les
                // anciens identifiants ni data-signinsettings. Repérer alors
                // son libellé « ME » et transmettre son centre à WebView2 pour
                // un véritable événement souris via le protocole DevTools.
                const meLabel = Array.from(document.querySelectorAll('*'))
                    .filter(item => {
                        if (!isVisible(item)) return false;
                        const text = (item.textContent || '').trim().replace(/\s+/g, ' ');
                        const rect = item.getBoundingClientRect();
                        return text === 'ME' && rect.right > (window.innerWidth * 0.65) && rect.top < 360;
                    })
                    .sort((left, right) => {
                        const a = left.getBoundingClientRect();
                        const b = right.getBoundingClientRect();
                        return (a.width * a.height) - (b.width * b.height);
                    })[0];
                if (meLabel) {
                    const rect = meLabel.getBoundingClientRect();
                    return reply('me-control-ready', 'Contrôle Microsoft ME détecté.', {
                        x: Math.round(rect.left + rect.width / 2),
                        y: Math.round(rect.top + rect.height / 2)
                    });
                }
                // Microsoft utilise actuellement deux générations du contrôle
                // de compte : l'ancien lien mectrl et le conteneur moderne
                // #meControl dont .msame_Header affiche le cercle « ME ».
                const accountTrigger = document.querySelector('#mectrl_main_trigger') ||
                    document.querySelector('#meControl .msame_Header');
                const signIn = [accountTrigger].concat(Array.from(document.querySelectorAll('a[href]'))).find(item => {
                    if (!item) return false;
                    const text = (item.textContent || '').trim().replace(/\s+/g, ' ');
                    const label = ((item.getAttribute && item.getAttribute('aria-label')) || '').trim();
                    const title = ((item.getAttribute && item.getAttribute('title')) || '').trim();
                    const href = item.href || '';
                    const modernMeControl = item.classList && item.classList.contains('msame_Header');
                    const microsoftAccountControl = modernMeControl || (item.id === 'mectrl_main_trigger' &&
                        (/sign\s*in|se\s*connecter/i.test(label + ' ' + title) || /\/onerf\/signin|wsignin|login\.live\.com/i.test(href)));
                    return isVisible(item) && (microsoftAccountControl || /^(sign\s*in|se\s*connecter)$/i.test(text));
                });
                if (signIn && !state.signInClicked) {
                    state.signInClicked = true;
                    signIn.click();
                    return reply('opening-signin', 'Ouverture de la connexion Microsoft Insider...');
                }
                return reply('waiting-signin', 'Connecte-toi avec le compte inscrit au programme Windows Insider.', {
                    href: window.location.href
                });
            }
            return reply('waiting-edition', 'Chargement du choix ISO...');
        }
        const candidates = Array.from(select.options).filter(item => item.value && item.value !== 'null');
        if (requestedRelease === 'Insider26H2') {
            const selected = candidates.find(item => item.selected);
            return reply('awaiting-user-edition', selected
                ? 'Édition choisie : ' + selected.textContent.trim() + '. Clique sur Confirmer pour continuer.'
                : 'Choisis l’édition ou le build Windows 11, puis clique sur Confirmer.');
        }
        const option = candidates[0];
        if (!option) {
            return reply('no-edition', 'Aucune ISO Windows 11 x64 disponible sur la page Microsoft.');
        }
        select.value = option.value;
        select.dispatchEvent(new Event('input', { bubbles: true }));
        select.dispatchEvent(new Event('change', { bubbles: true }));
        button.click();
        state.stage = 'language';
        state.stageStartedAt = Date.now();
        return reply('edition-selected', option.textContent.trim());
    }
    if (state.stage === 'language') {
        const select = document.querySelector('#product-languages');
        const button = document.querySelector('#submit-sku');
        if (!isVisible(select) || !isVisible(button) || select.options.length < 2) {
            return reply('waiting-language', 'Microsoft prepare la liste des langues...');
        }
        const option = Array.from(select.options).find(item => {
            if (!item.value || item.value === 'null') return false;
            try {
                const value = JSON.parse(item.value);
                return value.language === requestedLanguage;
            } catch (_) {
                return false;
            }
        });
        if (!option) {
            const available = Array.from(select.options)
                .filter(item => item.value && item.value !== 'null')
                .map(item => item.textContent.trim());
            return reply('language-not-found', 'Langue non proposee par Microsoft.', { available: available });
        }
        select.value = option.value;
        select.dispatchEvent(new Event('input', { bubbles: true }));
        select.dispatchEvent(new Event('change', { bubbles: true }));
        button.click();
        state.stage = 'link';
        state.stageStartedAt = Date.now();
        const offered = Array.from(select.options).filter(item => item.value && item.value !== 'null').map(item => {
            try { return JSON.parse(item.value).language; } catch (_) { return ''; }
        }).filter(Boolean);
        return reply('language-selected', option.textContent.trim(), { available: offered });
    }
    if (state.stage === 'link') {
        const links = Array.from(document.querySelectorAll('a[href^="https://"][href*=".iso"]'));
        const architecture = requestedArchitecture === 'x86' ? /_(?:x86|x32)[^/]*\.iso/i : /_x64[^/]*\.iso/i;
        const link = links.find(item => architecture.test(item.href));
        if (link && link.href) {
            state.stage = 'done';
            return reply('link-ready', 'Lien ISO genere par Microsoft.', {
                href: link.href,
                text: link.textContent.trim()
            });
        }
        const error = Array.from(document.querySelectorAll('#errorModalMessage'))
            .find(element => isVisible(element) && element.textContent.trim().length > 0);
        if (error) {
            return reply('site-error', error.textContent.trim());
        }
        return reply('waiting-link', 'Microsoft genere le lien temporaire...');
    }
    return reply('done', 'Automatisation terminee.');
})();
"@

$automationTimer = New-Object Windows.Forms.Timer
$automationTimer.Interval = 200
$automationTimer.Add_Tick({
    if($script:Phase -eq 'Initializing' -and ((Get-Date)-$script:AutomationStartedAt).TotalSeconds -ge $TimeoutSeconds){
        $script:Phase='Error';Complete-BastosIsoWorker -Status 'Timeout' -Message 'Le delai de connexion Microsoft est depasse.' -Close;return
    }
    if($CancelPath -and (Test-Path -LiteralPath $CancelPath)){
        if($script:StreamingDownloader){$script:StreamingDownloader.Cancel()}
        else{$script:Phase='Cancelled';Complete-BastosIsoWorker -Status 'Cancelled' -Message 'Telechargement ISO annule.' -Close;return}
    }
    if ($script:Phase -eq 'Downloading' -and $script:StreamingDownloader) {
        if (((Get-Date) - $script:LastProgressPublishAt).TotalMilliseconds -ge 200) {
            try {
                $received = [long]$script:StreamingDownloader.BytesReceived
                $total = [long]$script:StreamingDownloader.TotalBytes
                Write-BastosIsoResult -Status 'Downloading' -Message 'Telechargement ISO Windows 11 en cours.' -Uri $script:PendingDownloadUri -FilePath $script:PendingDownloadPath -Bytes $received -TotalBytes $total
                $script:LastProgressPublishAt = Get-Date
            } catch {}
        }
        if($script:StreamingDownloader.IsCompleted){
            $received=[long]$script:StreamingDownloader.BytesReceived
            $total=[long]$script:StreamingDownloader.TotalBytes
            if($script:StreamingDownloader.Succeeded -and
                $script:PartialDownloadPath -and
                (Test-Path -LiteralPath $script:PartialDownloadPath -PathType Leaf)){
                try{
                    Move-Item -LiteralPath $script:PartialDownloadPath -Destination $script:PendingDownloadPath -Force
                    $bytes=[long](Get-Item -LiteralPath $script:PendingDownloadPath -ErrorAction Stop).Length
                    $script:Phase='Completed'
                    Set-BastosIsoStatus "Telechargement termine : $($script:PendingDownloadPath)" ([Drawing.Color]::FromArgb(22,212,154))
                    Complete-BastosIsoWorker -Status 'Completed' -Message 'ISO Windows 11 officielle telechargee en flux continu.' -Uri $script:PendingDownloadUri -FilePath $script:PendingDownloadPath -Bytes $bytes -TotalBytes $(if($total -gt 0){$total}else{$bytes}) -Close
                    if(-not $Hidden){
                        [Windows.Forms.MessageBox]::Show("ISO Windows 11 telechargee :`r`n$($script:PendingDownloadPath)",'Telechargement termine','OK','Information')|Out-Null
                        Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $script:PendingDownloadPath)
                    }
                }catch{
                    $script:Phase='Error'
                    Complete-BastosIsoWorker -Status 'Error' -Message "Finalisation du fichier ISO impossible : $($_.Exception.Message)" -Uri $script:PendingDownloadUri -FilePath $script:PendingDownloadPath -Bytes $received -TotalBytes $total -Close
                }
            }else{
                $script:Phase='Error'
                $reason=if($script:StreamingDownloader.ErrorMessage){[string]$script:StreamingDownloader.ErrorMessage}else{'Le transfert HTTP Microsoft a échoué.'}
                Remove-Item -LiteralPath $script:PartialDownloadPath -Force -ErrorAction SilentlyContinue
                Complete-BastosIsoWorker -Status 'Interrupted' -Message $reason -Uri $script:PendingDownloadUri -FilePath $script:PendingDownloadPath -Bytes $received -TotalBytes $total -Close
            }
        }
        return
    }
    if ($script:Phase -ne 'Automating' -or -not $script:AutomationReady) { return }
    if ($null -ne $script:MeClickTask) {
        if(-not $script:MeClickTask.IsCompleted){ return }
        try {
            [void]$script:MeClickTask.GetAwaiter().GetResult()
            $script:MeClickStep++
            if($script:MeClickStep -lt $script:MeClickPayloads.Count){
                $payload=[string]$script:MeClickPayloads[$script:MeClickStep]
                $script:MeClickTask=$webView.CoreWebView2.CallDevToolsProtocolMethodAsync('Input.dispatchMouseEvent',$payload)
            } else {
                $script:MeClickTask=$null
                $script:MeClickPayloads=@()
                $script:LastInteractiveStatus='SigningIn'
                Set-BastosIsoStatus 'Ouverture directe du formulaire Sign In Microsoft...'
                Complete-BastosIsoWorker -Status 'SigningIn' -Message 'Le contrôle Microsoft ME a été activé automatiquement.'
            }
        } catch {
            $script:MeClickTask=$null
            $script:MeClickPayloads=@()
            $script:SignInNavigationStarted=$false
            Set-BastosIsoStatus "Activation du contrôle Microsoft impossible : $($_.Exception.Message)" ([Drawing.Color]::FromArgb(245,188,78))
        }
        return
    }
    if (((Get-Date) - $script:AutomationStartedAt).TotalSeconds -ge $TimeoutSeconds) {
        $script:Phase = 'Manual'
        Set-BastosIsoStatus 'Le delai Microsoft est depasse. Tu peux terminer manuellement dans la page officielle affichee.' ([Drawing.Color]::FromArgb(245,188,78))
        if ($Hidden -or $LinkOnly -or $InterceptDownloadTest) {
            Complete-BastosIsoWorker -Status 'Timeout' -Message 'Le delai de generation du lien Microsoft est depasse.' -Close
        }
        return
    }
    if ($null -eq $script:AutomationTask) {
        if((Get-Date) -lt $script:NextScriptAt){return}
        $script:AutomationTask = $webView.ExecuteScriptAsync($automationScript)
        return
    }
    if (-not $script:AutomationTask.IsCompleted) { return }
    try {
        $outerJson = $script:AutomationTask.GetAwaiter().GetResult()
        # WebView2 returns JSON null while Microsoft replaces/navigates its page.
        # This is not a failed request; wait for the next completed document.
        if([string]::IsNullOrWhiteSpace($outerJson) -or $outerJson -eq 'null'){$script:AutomationTask=$null;return}
        $innerJson = $outerJson | ConvertFrom-Json
        if([string]::IsNullOrWhiteSpace($innerJson)){$script:AutomationTask=$null;return}
        $step = $innerJson | ConvertFrom-Json
        $script:AutomationTask = $null
        switch ([string]$step.status) {
            'warming-up' {
                Set-BastosIsoStatus 'Initialisation de la validation Microsoft...'
            }
            'waiting-edition' {
                Set-BastosIsoStatus 'Chargement du formulaire ISO Windows 11...'
            }
            'opening-signin' {
                Set-BastosIsoStatus 'Ouverture de la connexion Microsoft Insider...'
                if($script:LastInteractiveStatus -ne 'SigningIn'){
                    $script:LastInteractiveStatus='SigningIn'
                    Complete-BastosIsoWorker -Status 'SigningIn' -Message 'Entre ton identifiant et ton mot de passe Microsoft dans la page officielle.'
                }
            }
            'signin-uri-ready' {
                $uri = [string]$step.href
                if (-not (Test-BastosMicrosoftSignInUri -Uri $uri)) {
                    $script:Phase = 'Manual'
                    Set-BastosIsoStatus 'Adresse de connexion Microsoft refusée par le contrôle de sécurité.' ([Drawing.Color]::FromArgb(232,93,106))
                    Complete-BastosIsoWorker -Status 'Error' -Message 'Adresse de connexion Microsoft non autorisée.' -Uri $uri
                    return
                }
                if($script:SignInNavigationStarted){ return }
                $script:SignInNavigationStarted = $true
                Set-BastosIsoStatus 'Ouverture directe du formulaire Sign in Microsoft...'
                if($script:LastInteractiveStatus -ne 'SigningIn'){
                    $script:LastInteractiveStatus='SigningIn'
                    Complete-BastosIsoWorker -Status 'SigningIn' -Message 'Ouverture directe du formulaire d adresse e-mail Microsoft.' -Uri $uri
                }
                $webView.CoreWebView2.Navigate($uri)
            }
            'me-control-ready' {
                if($script:SignInNavigationStarted){ return }
                $x = [int]$step.x
                $y = [int]$step.y
                if($x -lt 0 -or $y -lt 0 -or $x -ge $webView.ClientSize.Width -or $y -ge $webView.ClientSize.Height){
                    Set-BastosIsoStatus 'Position du contrôle Microsoft ME invalide.' ([Drawing.Color]::FromArgb(245,188,78))
                    return
                }
                $script:SignInNavigationStarted = $true
                $moved = @{type='mouseMoved';x=$x;y=$y;button='none';buttons=0} | ConvertTo-Json -Compress
                $pressed = @{type='mousePressed';x=$x;y=$y;button='left';buttons=1;clickCount=1} | ConvertTo-Json -Compress
                $released = @{type='mouseReleased';x=$x;y=$y;button='left';buttons=0;clickCount=1} | ConvertTo-Json -Compress
                # Enchaîner déplacement, pression et relâchement sur plusieurs
                # ticks garantit l'ordre sans bloquer le thread WinForms.
                $script:MeClickPayloads=@($moved,$pressed,$released)
                $script:MeClickStep=0
                $script:MeClickTask=$webView.CoreWebView2.CallDevToolsProtocolMethodAsync('Input.dispatchMouseEvent',$moved)
                Set-BastosIsoStatus 'Activation automatique du contrôle Microsoft ME...'
            }
            'waiting-signin' {
                Set-BastosIsoStatus 'Connecte-toi avec ton compte Microsoft inscrit au programme Windows Insider.'
                if($script:LastInteractiveStatus -ne 'AwaitingSignIn'){
                    $script:LastInteractiveStatus='AwaitingSignIn'
                    Complete-BastosIsoWorker -Status 'AwaitingSignIn' -Message 'Connexion Microsoft Insider requise dans la fenêtre ouverte.' -Uri ([string]$step.href)
                }
            }
            'awaiting-user-edition' {
                Set-BastosIsoStatus ([string]$step.message)
                if($script:LastInteractiveStatus -ne 'AwaitingEditionSelection'){
                    $script:LastInteractiveStatus='AwaitingEditionSelection'
                    Complete-BastosIsoWorker -Status 'AwaitingEditionSelection' -Message ([string]$step.message)
                }
            }
            'edition-selected' {
                Set-BastosIsoStatus "ISO selectionnee : $($step.message). Chargement des langues..."
            }
            'waiting-language' {
                Set-BastosIsoStatus 'Microsoft prepare la liste des langues...'
            }
            'language-selected' {
                $script:AvailableLanguages=@($step.available)
                Set-BastosIsoStatus "Langue selectionnee : $LanguageDisplay. Generation du lien temporaire..."
            }
            'waiting-link' {
                Set-BastosIsoStatus 'Microsoft genere le lien ISO temporaire...'
            }
            'link-ready' {
                $uri = [string]$step.href
                if (-not (Test-BastosMicrosoftUri -Uri $uri)) {
                    throw "Microsoft a renvoye un domaine non autorise : $uri"
                }
                $script:PendingDownloadUri = $uri
                $script:PendingDownloadPath = Get-BastosIsoOutputPath -Uri $uri
                if ($LinkOnly) {
                    $script:Phase = 'Completed'
                    Complete-BastosIsoWorker -Status 'LinkReady' -Message 'Lien ISO officiel genere sans lancer le telechargement.' -Uri $uri -FilePath $script:PendingDownloadPath -Close
                    return
                }
                $script:Phase = 'StartingDownload'
                Set-BastosIsoStatus "Lien Microsoft obtenu. Demarrage du telechargement vers $($script:PendingDownloadPath)..."
                $webView.CoreWebView2.Navigate($uri)
            }
            { $_ -in @('site-error','language-not-found','no-edition') } {
                $message = [string]$step.message
                $script:Phase = 'Manual'
                Set-BastosIsoStatus "Automatisation interrompue : $message Tu peux terminer manuellement dans la page affichee." ([Drawing.Color]::FromArgb(245,188,78))
                if ($Hidden -or $LinkOnly -or $InterceptDownloadTest) {
                    $status = if($message -match '715-123130|Sentinel|pas autorises|not authorized'){'SentinelRejected'}else{'MicrosoftError'}
                    Complete-BastosIsoWorker -Status $status -Message $message -Close
                }
            }
        }
    } catch {
        $script:AutomationTask = $null
        if($_.Exception.Message -match 'CoreWebView2.*uninitialized|navigation|document' -and $script:NavigationRetries -lt 10){
            $script:NavigationRetries++;$script:NextScriptAt=(Get-Date).AddSeconds(1);return
        }
        $script:Phase = 'Manual'
        Set-BastosIsoStatus "Automatisation impossible : $($_.Exception.Message). La page officielle reste utilisable manuellement." ([Drawing.Color]::FromArgb(245,188,78))
        if ($Hidden -or $LinkOnly -or $InterceptDownloadTest) {
            Complete-BastosIsoWorker -Status 'Error' -Message $_.Exception.Message -Close
        }
    }
})

$webView.Add_CoreWebView2InitializationCompleted({
    param($sender,$eventArgs)
    if (-not $eventArgs.IsSuccess) {
        $message = "Initialisation WebView2 impossible : $($eventArgs.InitializationException.Message)"
        Set-BastosIsoStatus $message ([Drawing.Color]::FromArgb(232,93,106))
        Complete-BastosIsoWorker -Status 'Error' -Message $message -Close
        return
    }
    $sender.CoreWebView2.Settings.AreDevToolsEnabled = $false
    $sender.CoreWebView2.Settings.IsStatusBarEnabled = $true
    if($Release -eq 'Windows10Current'){
        # Microsoft's public Windows 10 ISO page is presented to non-Windows clients.
        $sender.CoreWebView2.Settings.UserAgent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
    }
    $sender.CoreWebView2.Add_NewWindowRequested({
        param($coreSender,$newWindowArgs)
        # Microsoft ouvre normalement la connexion dans une nouvelle fenêtre.
        # La réutiliser dans le WebView BASTOS empêche les fenêtres Sign in / création
        # de compte de se multiplier pendant les redirections d'authentification.
        $newWindowArgs.Handled = $true
        $uri = [string]$newWindowArgs.Uri
        try {
            $parsed = [Uri]$uri
            $hostName = $parsed.DnsSafeHost.ToLowerInvariant()
            $allowed = $parsed.Scheme -eq 'https' -and (
                $hostName -eq 'microsoft.com' -or $hostName.EndsWith('.microsoft.com') -or
                $hostName -eq 'live.com' -or $hostName.EndsWith('.live.com') -or
                $hostName -eq 'microsoftonline.com' -or $hostName.EndsWith('.microsoftonline.com'))
            if ($allowed) {
                $coreSender.Navigate($uri)
            } else {
                Set-BastosIsoStatus "Fenêtre externe bloquée pendant la connexion : $hostName" ([Drawing.Color]::FromArgb(245,188,78))
            }
        } catch {
            Set-BastosIsoStatus 'Fenêtre externe invalide bloquée pendant la connexion.' ([Drawing.Color]::FromArgb(245,188,78))
        }
    })
    $sender.CoreWebView2.Add_DownloadStarting({
        param($coreSender,$downloadArgs)
        $uri = [string]$downloadArgs.DownloadOperation.Uri
        if (-not (Test-BastosMicrosoftUri -Uri $uri)) {
            $downloadArgs.Cancel = $true
            $message = "Telechargement refuse : domaine non Microsoft ($uri)."
            Set-BastosIsoStatus $message ([Drawing.Color]::FromArgb(232,93,106))
            Complete-BastosIsoWorker -Status 'Error' -Message $message -Uri $uri
            return
        }
        if ($InterceptDownloadTest) {
            $downloadArgs.Cancel = $true
            $script:Phase = 'Completed'
            Complete-BastosIsoWorker -Status 'DownloadIntercepted' -Message 'Le demarrage du telechargement ISO a ete intercepte avec succes sans telecharger le fichier complet.' -Uri $uri -FilePath $script:PendingDownloadPath -Close
            return
        }
        if (-not $script:PendingDownloadPath) {
            $script:PendingDownloadPath = Get-BastosIsoOutputPath -Uri $uri
        }
        # WebView2 sert uniquement à obtenir le lien temporaire Microsoft.
        # Le transfert lui-même est repris par BASTOS afin de disposer des
        # octets réellement reçus et d une jauge fiable sur chaque machine.
        $downloadArgs.Cancel = $true
        $script:PartialDownloadPath = "$($script:PendingDownloadPath).bastos-download"
        Remove-Item -LiteralPath $script:PartialDownloadPath -Force -ErrorAction SilentlyContinue
        $script:StreamingDownloader = [BastosStreamingDownloader]::new()
        $script:StreamingDownloader.Start($uri,$script:PartialDownloadPath)
        $script:Phase = 'Downloading'
        if($Release -eq 'Insider26H2'){
            $form.ShowInTaskbar = $false
            $form.Hide()
        }
        Set-BastosIsoStatus "Telechargement en cours : $($script:PendingDownloadPath)"
        Complete-BastosIsoWorker -Status 'DownloadStarted' -Message 'Le transfert direct BASTOS depuis Microsoft a commence.' -Uri $uri -FilePath $script:PendingDownloadPath
    })
    $sender.CoreWebView2.Navigate($officialPageUri)
})

$webView.Add_NavigationCompleted({
    param($sender,$eventArgs)
    if ($script:Phase -eq 'Initializing') {
        if (-not $eventArgs.IsSuccess) {
            $message = "Navigation Microsoft impossible : $($eventArgs.WebErrorStatus)"
            Set-BastosIsoStatus $message ([Drawing.Color]::FromArgb(232,93,106))
            Complete-BastosIsoWorker -Status 'Error' -Message $message -Close
            return
        }
        $script:Phase = 'Automating'
        $script:AutomationReady = $true
        $script:AutomationStartedAt = Get-Date
        if ($Release -eq 'Insider26H2') {
            Set-BastosIsoStatus "Connecte-toi au programme Windows Insider. Choisis ensuite toi-même l'édition Windows 11 ; BASTOS sélectionnera $LanguageDisplay et reprendra le téléchargement."
            Complete-BastosIsoWorker -Status 'AwaitingSignIn' -Message 'Page officielle Windows Insider ouverte. Connexion Microsoft requise avant le choix manuel de l edition.'
        } else {
            Set-BastosIsoStatus "Page Microsoft chargee. Selection automatique de $releaseDisplay $Architecture et $LanguageDisplay..."
        }
    }
})

$form.Add_Shown({
    $automationTimer.Start()
    [void]$webView.EnsureCoreWebView2Async()
})

$form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($script:ClosingProgrammatically) { return }
    if ($script:Phase -eq 'Downloading' -and $script:StreamingDownloader) {
        $answer = [Windows.Forms.MessageBox]::Show('Un telechargement ISO est en cours. L annuler et fermer ?', 'Telechargement en cours', 'YesNo', 'Warning')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            $eventArgs.Cancel = $true
            return
        }
        try { $script:StreamingDownloader.Cancel() } catch {}
    }
})

try {
    [void]$form.ShowDialog()
} finally {
    $automationTimer.Stop()
    $automationTimer.Dispose()
    if($script:StreamingDownloader){$script:StreamingDownloader.Dispose()}
    if($script:Phase -ne 'Completed' -and $script:PartialDownloadPath){
        Remove-Item -LiteralPath $script:PartialDownloadPath -Force -ErrorAction SilentlyContinue
    }
    $webView.Dispose()
    $form.Dispose()
    Start-Sleep -Milliseconds 150
    Remove-BastosWebView2SessionFolder -Path $webViewSessionFolder
}
