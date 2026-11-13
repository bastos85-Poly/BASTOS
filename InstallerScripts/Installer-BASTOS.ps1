[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [string]$TestRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop

$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$manifestPath = Join-Path $kitRoot 'MANIFEST.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'MANIFEST.json est absent du kit.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.Schema -ne 1 -or [string]$manifest.Version -ne '7.120') {
    throw 'Version ou format du kit de restauration incorrect.'
}

$kitPrefix = $kitRoot + '\'
$entries = @($manifest.Files)
$known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $entries) {
    $relative = [string]$entry.Path
    if (-not $relative -or $relative.StartsWith('/') -or $relative.Contains('\') -or
        $relative.Contains(':') -or $relative -match '(^|/)\.\.?(/|$)') {
        throw "Chemin interdit dans le manifeste : $relative"
    }
    if ($relative -match '^Payload/Preferences/Software/Portable/RadeonTuner(/|$)') {
        throw 'Radeon Tuner doit etre installe manuellement depuis le catalogue BASTOS.'
    }
    if (-not $known.Add($relative)) { throw "Entrée dupliquée : $relative" }
    $file = [IO.Path]::GetFullPath((Join-Path $kitRoot $relative.Replace('/', '\')))
    if (-not $file.StartsWith($kitPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Fichier absent ou hors du kit : $relative"
    }
    $item = Get-Item -LiteralPath $file -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Lien de fichier refusé : $relative" }
    if ([int64]$item.Length -ne [int64]$entry.Length -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$entry.Sha256) {
        throw "Empreinte incorrecte : $relative"
    }
}
$actual = @(Get-ChildItem -LiteralPath $kitRoot -Recurse -File -Force |
    Where-Object { $_.FullName -ne $manifestPath })
if ($actual.Count -ne $entries.Count) {
    throw "Contenu du kit différent du manifeste : $($actual.Count) fichiers au lieu de $($entries.Count)."
}
$appSource = Join-Path $kitRoot 'Payload\Application'
$exeSource = Join-Path $appSource 'Bastos.Native\BASTOS-Native.exe'
if ((Get-Content -LiteralPath (Join-Path $appSource 'VERSION.txt') -Raw).Trim() -ne '7.120' -or
    (Get-Item -LiteralPath $exeSource).VersionInfo.FileVersion -ne '7.120.3.0') {
    throw 'Le programme du kit ne correspond pas à la version 7.120.'
}
Write-Host "Kit BASTOS 7.120 vérifié : $($entries.Count) fichiers et leurs SHA-256." -ForegroundColor Green
if ($VerifyOnly) { return }

if (-not $TestRoot) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $quoted = '"' + $MyInvocation.MyCommand.Path.Replace('"', '') + '"'
        $elevated = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $quoted" `
            -Verb RunAs -Wait -PassThru
        if ($elevated.ExitCode -ne 0) { throw "L'installation administrateur a échoué (code $($elevated.ExitCode))." }
        return
    }
}

function Copy-VerifiedSection {
    param([string]$Section,[string]$Destination,[string]$BackupName)
    $prefix = "Payload/$Section/"
    $sectionEntries = @($entries | Where-Object { ([string]$_.Path).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    if ($sectionEntries.Count -eq 0) { return }
    $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($destinationFull.Length -lt 8) { throw "Destination trop courte : $Destination" }
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
    if ((Get-Item -LiteralPath $destinationFull -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Destination redirigée refusée : $destinationFull"
    }
    $destinationPrefix = $destinationFull + '\'
    foreach ($entry in $sectionEntries) {
        $relative = ([string]$entry.Path).Substring($prefix.Length).Replace('/', '\')
        $source = Join-Path $kitRoot ([string]$entry.Path).Replace('/', '\')
        $target = [IO.Path]::GetFullPath((Join-Path $destinationFull $relative))
        if (-not $target.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Destination hors du dossier BASTOS : $target"
        }
        $parent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $check = $parent
        while ($check.Length -ge $destinationFull.Length) {
            if ((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Jonction de dossier refusée : $check"
            }
            if ($check.Equals($destinationFull, [StringComparison]::OrdinalIgnoreCase)) { break }
            $check = Split-Path -Parent $check
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq [string]$entry.Sha256) { continue }
            $previous = Join-Path (Join-Path $backupRoot $BackupName) $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $previous) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $previous -Force
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne [string]$entry.Sha256) {
            throw "Copie incomplète : $target"
        }
    }
    Write-Host "$BackupName : $($sectionEntries.Count) fichiers contrôlés."
}

if ($TestRoot) {
    $testFull = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\')
    if ($testFull.Length -lt 12 -or $testFull.Equals($kitRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $testFull.StartsWith($kitPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Le dossier de test doit être distinct du kit.'
    }
    $systemRoot = Join-Path $testFull 'ProgramData\BASTOS-ISO'
    $userRoot = Join-Path $testFull 'LocalAppData\BASTOS'
    $localPrograms = Join-Path $testFull 'LocalAppData\Programs\BASTOS'
    $exfilRoot = Join-Path $testFull 'LocalAppData\EXFIL'
    $exfilStateRoot = Join-Path $testFull 'Roaming\exfil-v2'
    $desktop = Join-Path $testFull 'Desktop'
    $recoveryTargets = @(
        (Join-Path $testFull 'Recovery\Application'),
        (Join-Path $testFull 'Recovery\sources\$OEM$\$1\ProgramData\BASTOS-ISO')
    )
    $backupRoot = Join-Path $testFull 'Previous'
} else {
    $running = @(Get-Process BASTOS-Native -ErrorAction SilentlyContinue)
    foreach ($process in $running) {
        [void]$process.CloseMainWindow()
        [void]$process.WaitForExit(10000)
        if (-not $process.HasExited) { throw 'Ferme BASTOS avant la restauration.' }
    }
    $systemRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'BASTOS-ISO'
    $userRoot = Join-Path $env:LOCALAPPDATA 'BASTOS'
    $localPrograms = Join-Path $env:LOCALAPPDATA 'Programs\BASTOS'
    $exfilRoot = Join-Path $env:LOCALAPPDATA 'EXFIL'
    $exfilStateRoot = Join-Path $env:APPDATA 'exfil-v2'
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    $recoveryTargets = @()
    try {
        $drive = [IO.DriveInfo]::new('D:\')
        if ($drive.IsReady -and $drive.DriveType -eq [IO.DriveType]::Fixed -and
            $drive.VolumeLabel -eq 'BASTOS_RECOVERY') {
            $recoveryTargets = @(
                'D:\Application',
                'D:\sources\$OEM$\$1\ProgramData\BASTOS-ISO'
            )
        }
    } catch {}
    $backupRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) (
        'BASTOS-Restore-Backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
Copy-VerifiedSection 'Application' $systemRoot 'ProgramData'
Copy-VerifiedSection 'Application' $localPrograms 'LocalPrograms'
for ($index=0; $index -lt $recoveryTargets.Count; $index++) {
    Copy-VerifiedSection 'Application' $recoveryTargets[$index] ("Recovery-$index")
}
Copy-VerifiedSection 'Preferences' $userRoot 'Preferences'
Copy-VerifiedSection 'Dependencies/EXFIL' $exfilRoot 'EXFIL'
Copy-VerifiedSection 'Dependencies/exfil-v2' $exfilStateRoot 'EXFIL-State'

if (-not $TestRoot) {
    $powerLauncher = Join-Path $systemRoot 'Bastos.Native\BASTOS-Native.exe'
    $powerSetup = Start-Process -FilePath $powerLauncher -ArgumentList @('--native-worker','power-install') -WindowStyle Hidden -Wait -PassThru
    if ($powerSetup.ExitCode -ne 0) { throw "Installation des plans Bastos en echec (code $($powerSetup.ExitCode))." }
    Write-Host 'Plans Normal, Performances elevees et Zoic AMD installes. Plan actif conserve.' -ForegroundColor Green
}

if (-not $TestRoot) {
    $appTarget = if ($recoveryTargets.Count -gt 0) {
        Join-Path $recoveryTargets[0] 'Bastos.Native\BASTOS-Native.exe'
    } else {
        Join-Path $localPrograms 'Bastos.Native\BASTOS-Native.exe'
    }
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $desktop 'BASTOS.lnk'))
    $shortcut.TargetPath = $appTarget
    $shortcut.WorkingDirectory = Split-Path -Parent $appTarget
    $shortcut.IconLocation = "$appTarget,0"
    $shortcut.Save()
}
Write-Host "BASTOS 7.120 restauré. Sauvegarde des fichiers remplacés : $backupRoot" -ForegroundColor Green
if ($recoveryTargets.Count -eq 0 -and -not $TestRoot) {
    Write-Host 'Partition BASTOS_RECOVERY absente : installation sur C: uniquement.' -ForegroundColor Yellow
}
