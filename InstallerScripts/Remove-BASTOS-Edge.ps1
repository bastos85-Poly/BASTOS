[CmdletBinding()]
param(
    [ValidateRange(0,1800)]
    [int]$WaitForBrowserSeconds = 0,

    [switch]$AuditOnly,

    # Reserve au deploiement initial BASTOS : aucun navigateur n est requis,
    # mais WebView2 doit rester installe et verifie.
    [switch]$ForceWithoutBrowser,

    [string]$SelectionPath = 'C:\ProgramData\BASTOS-ISO\Browser-Selection.json',

    [string]$ResultPath = 'C:\ProgramData\BASTOS-ISO\Edge-Machine-Removal.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$errors = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$installedEdgeInventoryVerified = $false
$provisionedInventoryVerified = $false
$removed = [Collections.Generic.List[string]]::new()

function Write-BastosEdgeResult {
    param([Parameter(Mandatory)]$Result)
    if ($ResultPath) {
        $parent = Split-Path -Parent $ResultPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($ResultPath, ($Result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    }
    return $Result
}

function Get-BastosUserProfilePaths {
    $paths = [Collections.Generic.List[string]]::new()
    try {
        foreach ($profile in @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and $_.LocalPath })) {
            $paths.Add([IO.Path]::GetFullPath([string]$profile.LocalPath))
        }
    } catch {}
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($directory.Name -notin @('All Users','Default','Default User','Public')) { $paths.Add($directory.FullName) }
        }
    }
    return @($paths | Select-Object -Unique)
}

function Get-BastosSelectedBrowserExecutable {
    param([Parameter(Mandatory)][ValidateSet('Chrome','Brave','Firefox','FirefoxNightly','Opera','Vivaldi')][string]$BrowserId)
    $candidates = [Collections.Generic.List[string]]::new()
    switch ($BrowserId) {
        'Chrome' {
            $candidates.Add((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')) }
        }
        'Brave' {
            $candidates.Add((Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe')) }
        }
        'Firefox' {
            $candidates.Add((Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox\firefox.exe')) }
        }
        'FirefoxNightly' {
            $candidates.Add((Join-Path $env:ProgramFiles 'Firefox Nightly\firefox.exe'))
            $candidates.Add((Join-Path $env:ProgramFiles 'Nightly\firefox.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Firefox Nightly\firefox.exe')) }
        }
        'Opera' {
            $candidates.Add((Join-Path $env:ProgramFiles 'Opera\launcher.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Opera\launcher.exe')) }
        }
        'Vivaldi' {
            $candidates.Add((Join-Path $env:ProgramFiles 'Vivaldi\Application\vivaldi.exe'))
            if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Vivaldi\Application\vivaldi.exe')) }
        }
    }
    foreach ($profilePath in @(Get-BastosUserProfilePaths)) {
        switch ($BrowserId) {
            'Chrome' { $candidates.Add((Join-Path $profilePath 'AppData\Local\Google\Chrome\Application\chrome.exe')) }
            'Brave' { $candidates.Add((Join-Path $profilePath 'AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe')) }
            'Firefox' { $candidates.Add((Join-Path $profilePath 'AppData\Local\Mozilla Firefox\firefox.exe')) }
            'FirefoxNightly' { $candidates.Add((Join-Path $profilePath 'AppData\Local\Firefox Nightly\firefox.exe')) }
            'Opera' { $candidates.Add((Join-Path $profilePath 'AppData\Local\Programs\Opera\opera.exe')) }
            'Vivaldi' { $candidates.Add((Join-Path $profilePath 'AppData\Local\Vivaldi\Application\vivaldi.exe')) }
        }
    }
    if($BrowserId -eq 'FirefoxNightly'){
        foreach($package in @(Get-AppxPackage -Name '*Firefox*Nightly*' -AllUsers -ErrorAction SilentlyContinue)){
            if($package.InstallLocation -and (Test-Path -LiteralPath $package.InstallLocation -PathType Container)){
                foreach($executable in @(Get-ChildItem -LiteralPath $package.InstallLocation -Filter 'firefox.exe' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1)){$candidates.Add($executable.FullName)}
            }
        }
    }
    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Get-BastosEdgeExecutablePaths {
    return @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe' }),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
}

function Get-BastosWebViewExecutablePaths {
    $roots = @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application' }),
        (Join-Path $env:ProgramFiles 'Microsoft\EdgeWebView\Application')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    $executables = @()
    foreach ($root in $roots) { $executables += @(Get-ChildItem -LiteralPath $root -Filter 'msedgewebview2.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) }
    return @($executables | Select-Object -Unique)
}

function Get-BastosEdgeUninstallEntries {
    $entries = @()
    foreach ($root in @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ([string]$item.DisplayName -cne 'Microsoft Edge') { continue }
                $entries += [pscustomobject]@{ RegistryPath=$key.PSPath; UninstallString=[string]$item.UninstallString }
            } catch {}
        }
    }
    return $entries
}

function ConvertFrom-BastosEdgeUninstallString {
    param([Parameter(Mandatory)][string]$Command)
    if ($Command -notmatch '^\s*"(?<exe>[^"]+\\Microsoft\\Edge\\Application\\[^\\]+\\Installer\\setup\.exe)"\s*(?<args>.*)$') { return $null }
    $executable = [IO.Path]::GetFullPath($Matches.exe)
    $arguments = [string]$Matches.args
    $trustedRoots = @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application' }),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application')
    ) | Where-Object { $_ }
    $trusted = $false
    foreach ($root in $trustedRoots) {
        if ($executable.StartsWith([IO.Path]::GetFullPath($root).TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { $trusted = $true; break }
    }
    if (-not $trusted -or $arguments -notmatch '(?i)(?:^|\s)--uninstall(?:\s|$)' -or $arguments -notmatch '(?i)(?:^|\s)--msedge(?:\s|$)') { return $null }
    if ($arguments -notmatch '(?i)(?:^|\s)--force-uninstall(?:\s|$)') { $arguments = ($arguments.Trim() + ' --force-uninstall') }
    return [pscustomobject]@{ Path=$executable; Arguments=$arguments.Trim() }
}

function Get-BastosEdgeInstallerCandidate {
    $installers = @()
    foreach ($applicationRoot in @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application' }),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }) {
        $installers += @(Get-ChildItem -LiteralPath $applicationRoot -Filter setup.exe -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -match '\\Microsoft\\Edge\\Application\\[^\\]+\\Installer\\setup\.exe$'
        })
    }
    $installer = $installers | Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending | Select-Object -First 1
    if (-not $installer) { return $null }
    return [pscustomobject]@{
        Path = $installer.FullName
        Arguments = '--uninstall --system-level --verbose-logging --force-uninstall --msedge'
    }
}

function Remove-BastosExactTree {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedPath)
    try {
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $expected = [IO.Path]::GetFullPath($ExpectedPath).TrimEnd('\')
        $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
        if (-not $full.Equals($expected,[StringComparison]::OrdinalIgnoreCase) -or $full.Equals($root,[StringComparison]::OrdinalIgnoreCase)) { throw "Chemin refuse : $full" }
        if (-not (Test-Path -LiteralPath $full)) { return }
        function Remove-BastosEdgeNode([string]$NodePath) {
            $item = Get-Item -LiteralPath $NodePath -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName,$false) } else { [IO.File]::Delete($item.FullName) }
                return
            }
            if ($item.PSIsContainer) {
                foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) { Remove-BastosEdgeNode -NodePath $child.FullName }
                [IO.File]::SetAttributes($item.FullName,[IO.FileAttributes]::Directory)
                [IO.Directory]::Delete($item.FullName,$false)
            } else {
                [IO.File]::SetAttributes($item.FullName,[IO.FileAttributes]::Normal)
                [IO.File]::Delete($item.FullName)
            }
        }
        Remove-BastosEdgeNode -NodePath $full
        $removed.Add($full)
    } catch { $errors.Add(("Suppression Edge impossible {0} : {1}" -f $Path,$_.Exception.Message)) }
}

function Remove-BastosEdgeOwnedRemnants {
    foreach ($profilePath in @(Get-BastosUserProfilePaths)) {
        $edgeData = Join-Path $profilePath 'AppData\Local\Microsoft\Edge'
        Remove-BastosExactTree -Path $edgeData -ExpectedPath $edgeData
        foreach ($shortcut in @(
            (Join-Path $profilePath 'Desktop\Microsoft Edge.lnk'),
            (Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'),
            (Join-Path $profilePath 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk')
        )) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }
    }
    foreach ($shortcut in @(
        (Join-Path $env:Public 'Desktop\Microsoft Edge.lnk'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
    )) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }

    foreach ($hive in @(Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' })) {
        $key = "Registry::$($hive.Name)\Software\Microsoft\Edge"
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue; $removed.Add($key) }
    }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Edge','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge')) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue; $removed.Add($key) }
    }
    foreach ($entry in @(Get-BastosEdgeUninstallEntries)) {
        if (Test-Path -LiteralPath $entry.RegistryPath) { Remove-Item -LiteralPath $entry.RegistryPath -Recurse -Force -ErrorAction SilentlyContinue; $removed.Add($entry.RegistryPath) }
    }
    foreach ($edgeRoot in @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge' }),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge')
    ) | Where-Object { $_ }) { Remove-BastosExactTree -Path $edgeRoot -ExpectedPath $edgeRoot }

    # Retire uniquement l'enregistrement du navigateur Edge Stable afin d'éviter
    # une icône fantôme. DevToolsClient et WebView2 restent enregistrés.
    $edgePackages = @()
    try {
        $edgePackages = @(Get-AppxPackage -AllUsers -Name 'Microsoft.MicrosoftEdge.Stable' -ErrorAction Stop)
        $script:installedEdgeInventoryVerified = $true
    } catch { $errors.Add(("Inventaire des enregistrements Edge Stable impossible : {0}" -f $_.Exception.Message)) }
    foreach ($package in $edgePackages) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $removed.Add("AppX:$($package.PackageFullName)")
        } catch { $errors.Add(("Suppression de l enregistrement Edge Stable impossible : {0}" -f $_.Exception.Message)) }
    }
    $provisionedPackages = @()
    try {
        $provisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'Microsoft.MicrosoftEdge.Stable' })
        $script:provisionedInventoryVerified = $true
    } catch {
        $warnings.Add(("Inventaire des paquets Edge provisionnes indisponible, verification des fichiers poursuivie : {0}" -f $_.Exception.Message))
    }
    foreach ($provisioned in $provisionedPackages) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -AllUsers -ErrorAction Stop | Out-Null
            $removed.Add("Provisioned:$($provisioned.PackageName)")
        } catch { $errors.Add(("Suppression du provisionnement Edge Stable impossible : {0}" -f $_.Exception.Message)) }
    }
    if ($script:installedEdgeInventoryVerified) {
        try {
            if (@(Get-AppxPackage -AllUsers -Name 'Microsoft.MicrosoftEdge.Stable' -ErrorAction Stop).Count -gt 0) {
                $errors.Add('Un enregistrement Edge Stable reste present.')
            }
        } catch {
            $script:installedEdgeInventoryVerified = $false
            $errors.Add(("Verification finale des enregistrements Edge impossible : {0}" -f $_.Exception.Message))
        }
    }
}

if (-not $ForceWithoutBrowser -and -not (Test-Path -LiteralPath $selectionPath -PathType Leaf)) {
    return Write-BastosEdgeResult ([pscustomobject]@{ Success=$true; Action='EdgeConserveSelectionAbsente'; BrowserVerified=$false; EdgeRemaining=@(Get-BastosEdgeExecutablePaths); WebViewRemaining=@(Get-BastosWebViewExecutablePaths); Errors=@(); CheckedUtc=[DateTime]::UtcNow.ToString('o') })
}
$selection = if($ForceWithoutBrowser){$null}else{Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8 | ConvertFrom-Json}
$browserId = if($ForceWithoutBrowser){'None'}else{[string]$selection.Id}
if ($browserId -eq 'Edge') {
    return Write-BastosEdgeResult ([pscustomobject]@{ Success=$true; Action='EdgeConserve'; SelectedBrowser='Edge'; BrowserVerified=[bool](@(Get-BastosEdgeExecutablePaths).Count); EdgeRemaining=@(Get-BastosEdgeExecutablePaths); WebViewRemaining=@(Get-BastosWebViewExecutablePaths); Errors=@(); CheckedUtc=[DateTime]::UtcNow.ToString('o') })
}
if ($browserId -notin @('None','Chrome','Brave','Firefox','FirefoxNightly','Opera','Vivaldi')) { throw "Selection navigateur inconnue : $browserId" }

$browserExecutable = $null
if(-not $ForceWithoutBrowser){
    $deadline = (Get-Date).AddSeconds($WaitForBrowserSeconds)
    do {
        $browserExecutable = Get-BastosSelectedBrowserExecutable -BrowserId $browserId
        if ($browserExecutable -or (Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 5
    } while ($true)
}

$edgeBefore = @(Get-BastosEdgeExecutablePaths)
$webViewBefore = @(Get-BastosWebViewExecutablePaths)
if (-not $ForceWithoutBrowser -and -not $browserExecutable) {
    return Write-BastosEdgeResult ([pscustomobject]@{ Success=$false; Deferred=$true; Action='AttenteNavigateur'; SelectedBrowser=$browserId; BrowserVerified=$false; EdgeRemaining=$edgeBefore; WebViewRemaining=$webViewBefore; Errors=@('Le navigateur choisi n est pas encore installe.'); CheckedUtc=[DateTime]::UtcNow.ToString('o') })
}
if ($AuditOnly) {
    $edgeRemaining = @(Get-BastosEdgeExecutablePaths)
    $webViewRemaining = @(Get-BastosWebViewExecutablePaths)
    return Write-BastosEdgeResult ([pscustomobject]@{ Success=($edgeRemaining.Count -eq 0 -and $webViewRemaining.Count -gt 0); Action='Audit'; SelectedBrowser=$browserId; BrowserVerified=[bool](-not $ForceWithoutBrowser); BrowserExecutable=$browserExecutable; EdgeRemaining=$edgeRemaining; WebViewRemaining=$webViewRemaining; Errors=@(); CheckedUtc=[DateTime]::UtcNow.ToString('o') })
}

if ($webViewBefore.Count -eq 0) {
    return Write-BastosEdgeResult ([pscustomobject]@{ Success=$false; Action='WebViewAbsentAvantNettoyage'; SelectedBrowser=$browserId; EdgeRemaining=$edgeBefore; WebViewRemaining=$webViewBefore; Errors=@('WebView2 doit etre installe avant de supprimer Edge. Aucun nettoyage effectue.'); Warnings=@(); CheckedUtc=[DateTime]::UtcNow.ToString('o') })
}

if ($edgeBefore.Count -gt 0) {
    $entries = @(Get-BastosEdgeUninstallEntries)
    $candidate = $null
    foreach ($entry in $entries) {
        $parsed = ConvertFrom-BastosEdgeUninstallString -Command $entry.UninstallString
        if ($parsed -and (Test-Path -LiteralPath $parsed.Path -PathType Leaf)) { $candidate = $parsed; break }
    }
    if (-not $candidate) {
        $candidate = Get-BastosEdgeInstallerCandidate
    }
    if (-not $candidate) {
        $warnings.Add('Le programme de desinstallation officiel de Microsoft Edge est introuvable; nettoyage cible tente directement.')
    } else {
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        try {
            $process = Start-Process -FilePath $candidate.Path -ArgumentList $candidate.Arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
            if (-not $process.WaitForExit(300000)) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $warnings.Add('La desinstallation Microsoft Edge a depasse cinq minutes.')
            } elseif ($process.ExitCode -ne 0) { $warnings.Add(("La desinstallation Microsoft Edge a retourne le code {0}." -f $process.ExitCode)) }
        } catch { $warnings.Add(("La desinstallation Microsoft Edge a echoue : {0}" -f $_.Exception.Message)) }
        $verifyDeadline = (Get-Date).AddSeconds(90)
        while (@(Get-BastosEdgeExecutablePaths).Count -gt 0 -and (Get-Date) -lt $verifyDeadline) { Start-Sleep -Seconds 3 }
    }
}

# Le script de reference force aussi la suppression des fichiers restants. BASTOS limite
# strictement cette passe aux dossiers Microsoft\Edge, donnees Edge et raccourcis Edge.
# EdgeWebView, EdgeUpdate et le dossier Microsoft parent ne sont jamais vises.
Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$desktopPolicy = Join-Path $PSScriptRoot 'Set-BASTOS-EdgeDesktopPolicy.ps1'
if (Test-Path -LiteralPath $desktopPolicy -PathType Leaf) {
    try { & $desktopPolicy | Out-Null }
    catch { $errors.Add(("Politique des raccourcis Edge non appliquee : {0}" -f $_.Exception.Message)) }
} else {
    $errors.Add('Politique des raccourcis Edge absente du paquet BASTOS.')
}
Remove-BastosEdgeOwnedRemnants
$edgeRemaining = @(Get-BastosEdgeExecutablePaths)
$webViewRemaining = @(Get-BastosWebViewExecutablePaths)
$webViewPreserved = $webViewRemaining.Count -gt 0
if ($edgeRemaining.Count -gt 0) { $errors.Add(('Microsoft Edge reste present : {0}' -f ($edgeRemaining -join ', '))) }
if (-not $webViewPreserved) { $errors.Add('WebView2 est absent apres la passe Edge; BASTOS refuse cet etat.') }
$success = $edgeRemaining.Count -eq 0 -and $webViewPreserved -and $installedEdgeInventoryVerified -and $errors.Count -eq 0
if ($success -and (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
    Unregister-ScheduledTask -TaskName 'BASTOS-Remove-Edge' -Confirm:$false -ErrorAction SilentlyContinue
}
return Write-BastosEdgeResult ([pscustomobject]@{
    Success=$success
    Action='EdgeSupprime'
    SelectedBrowser=$browserId
    BrowserVerified=[bool](-not $ForceWithoutBrowser)
    BrowserExecutable=$browserExecutable
    EdgePresentBefore=$edgeBefore
    EdgeRemaining=$edgeRemaining
    WebViewPresentBefore=$webViewBefore
    WebViewRemaining=$webViewRemaining
    WebViewPreserved=$webViewPreserved
    Removed=@($removed)
    Errors=@($errors)
    Warnings=@($warnings)
    InstalledEdgeInventoryVerified=$installedEdgeInventoryVerified
    ProvisionedInventoryVerified=$provisionedInventoryVerified
    CheckedUtc=[DateTime]::UtcNow.ToString('o')
})
