param([string]$TestRoot,[switch]$VerifyOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

$version = '7.120.140'
$payload = Join-Path $PSScriptRoot 'BASTOS-7.120.140-Payload.zip'
$expectedPayloadHash = '__PAYLOAD_HASH__'
$expectedManifestHash = '__MANIFEST_HASH__'
$expectedExeHash = '__NATIVE_HASH__'
$expectedBuildHash = '__BUILD_HASH__'
if ($env:BASTOS_INSTALL_TESTROOT) { $TestRoot = $env:BASTOS_INSTALL_TESTROOT }

function Assert-ChildPath([string]$parent, [string]$path) {
    $base = [IO.Path]::GetFullPath($parent).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin hors de la destination : $full"
    }
    return $full
}

function Assert-PlainPath([string]$path) {
    for($cursor=[IO.Path]::GetFullPath($path);$cursor;$cursor=Split-Path -Parent $cursor) {
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Lien ou jonction refuse : $cursor"
        }
    }
}

Write-Host "Vérification de l'installateur BASTOS $version..."
if (-not (Test-Path -LiteralPath $payload -PathType Leaf) -or
    (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash -ne $expectedPayloadHash) {
    throw "L'archive intégrée est absente ou endommagée."
}

$parent = if ($TestRoot) {
    [IO.Path]::GetFullPath($TestRoot)
} else {
    Join-Path $env:LOCALAPPDATA 'Programs'
}
$parent = [IO.Path]::GetFullPath($parent).TrimEnd('\')
Assert-PlainPath $parent
if ($parent.Length -lt 12 -or $parent.Equals([IO.Path]::GetPathRoot($parent).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination trop large.'
}
$target = Assert-ChildPath $parent (Join-Path $parent 'BASTOS')
Assert-PlainPath $target
$stage = Assert-ChildPath $parent (Join-Path $parent ('BASTOS-stage-' + [guid]::NewGuid().ToString('N')))
$backup = Assert-ChildPath $parent (Join-Path $parent ('BASTOS-before-' + $version + '-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss')))
if ($TestRoot -and ([IO.Path]::GetFullPath($TestRoot).TrimEnd('\').Equals([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Le dossier de test doit être distinct du paquet.'
}
New-Item -ItemType Directory -Path $parent -Force | Out-Null

$zip = [IO.Compression.ZipFile]::OpenRead($payload)
try {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('/', '\')
        if (-not $name -or $name.StartsWith('\') -or $name.Contains(':') -or
            @($entry.FullName.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or
            -not $seen.Add($name)) {
            throw "Chemin interdit ou dupliqué dans l'archive : $name"
        }
        [void](Assert-ChildPath $stage (Join-Path $stage $name))
        if (($stage.Length + 1 + $name.Length) -ge 260) {
            throw 'Destination trop longue pour Windows PowerShell. Choisissez un dossier de test plus court.'
        }
    }
} finally { $zip.Dispose() }

try {
    [IO.Compression.ZipFile]::ExtractToDirectory($payload, $stage)
    $manifestPath = Join-Path $stage 'BASTOS-App-Manifest.json'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $expectedManifestHash) { throw 'Manifeste endommagé.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.BastosVersion -ne $version -or $manifest.Files.Count -ne '__FILE_COUNT__') { throw 'Version ou nombre de fichiers incorrect.' }
    $declared = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $manifest.Files) {
        $relative = [string]$item.Path
        if ($relative.StartsWith('\') -or $relative.StartsWith('/') -or $relative.Contains(':') -or
            @(($relative.Replace('\','/')).Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or
            -not $declared.Add($relative.Replace('\','/'))) {
            throw "Chemin interdit ou dupliqué dans le manifeste : $relative"
        }
        $file = Assert-ChildPath $stage (Join-Path $stage $relative)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$item.Sha256) {
            throw "Fichier absent ou altéré : $relative"
        }
    }
    $buildPath=Join-Path $stage 'BASTOS-Build.json'
    if((Get-FileHash -LiteralPath $buildPath).Hash -ne $expectedBuildHash){throw 'Metadonnees de construction alterees.'}
    $actual=@(Get-ChildItem -LiteralPath $stage -Recurse -File -Force)
    if($actual.Count -ne ($declared.Count+2)){throw 'Nombre de fichiers extraits incorrect.'}
    foreach($file in $actual){
        $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/')
        if($relative -notin @('BASTOS-App-Manifest.json','BASTOS-Build.json') -and -not $declared.Contains($relative)){throw "Fichier non declare : $relative"}
    }
    $exe = Join-Path $stage 'Bastos.Native\BASTOS-Native.exe'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedExeHash -or
        (Get-Item -LiteralPath $exe).VersionInfo.FileVersion -ne '7.120.140.0') { throw 'Exécutable incorrect.' }
    if($VerifyOnly){Write-Host "BASTOS $version verifie : $($manifest.Files.Count) fichiers manifestes. Aucune installation effectuee." -ForegroundColor Green;return}

    if (Test-Path -LiteralPath $target) {
        $running = @(Get-Process BASTOS-Native,BASTOS-Game -ErrorAction SilentlyContinue | Where-Object {
            ((-not $TestRoot) -and (-not $_.Path)) -or ($_.Path -and $_.Path.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase))
        })
        if ($running.Count) { throw 'Ferme BASTOS et son module de jeu avant de mettre à jour cette installation.' }
        if (Test-Path -LiteralPath $backup) { throw 'La sauvegarde de cette minute existe déjà.' }
        [void](Assert-ChildPath $parent $target)
        [void](Assert-ChildPath $parent $backup)
        [IO.Directory]::Move($target, $backup)
    }
    try { [IO.Directory]::Move($stage, $target) }
    catch {
        if (Test-Path -LiteralPath $backup) { [IO.Directory]::Move($backup, $target) }
        throw
    }
    $installedExe = Join-Path $target 'Bastos.Native\BASTOS-Native.exe'
    if ((Get-FileHash -LiteralPath $installedExe -Algorithm SHA256).Hash -ne $expectedExeHash) { throw 'Vérification finale impossible.' }
    if (-not $TestRoot) {
        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'BASTOS.lnk'))
        $shortcut.TargetPath = $installedExe
        $shortcut.WorkingDirectory = Split-Path -Parent $installedExe
        $oldIcon = ([string]$shortcut.IconLocation -replace ',\s*-?\d+$','').Trim('"')
        if (-not $oldIcon -or -not (Test-Path -LiteralPath $oldIcon -PathType Leaf) -or $oldIcon.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) {
            $icon = Join-Path $target 'Assets\Bastos-Desktop.ico'
            if (-not (Test-Path -LiteralPath $icon)) { $icon = Join-Path $target 'Assets\Bastos-App.ico' }
            $shortcut.IconLocation = $icon + ',0'
        }
        $shortcut.Save()
        # Request administrator consent once when opening Bastos, before workers run.
        $shortcutPath = Join-Path $desktop 'BASTOS.lnk'
        $shortcutBytes = [IO.File]::ReadAllBytes($shortcutPath)
        if ($shortcutBytes.Length -lt 76 -or [BitConverter]::ToUInt32($shortcutBytes, 0) -ne 76) { throw 'Format du raccourci BASTOS incorrect.' }
        $shortcutFlags = [BitConverter]::ToUInt32($shortcutBytes, 20) -bor 0x2000
        [BitConverter]::GetBytes([uint32]$shortcutFlags).CopyTo($shortcutBytes, 20)
        [IO.File]::WriteAllBytes($shortcutPath, $shortcutBytes)
        $registration='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BASTOS'
        New-Item -Path $registration -Force|Out-Null
        $values=@{DisplayName='BASTOS';DisplayVersion=$version;Publisher='BASTOS';InstallLocation=$target;DisplayIcon=(Join-Path $target 'Assets\Bastos-Desktop.ico');UninstallString=('"'+(Join-Path $target 'Bastos-Uninstall.exe')+'"');QuietUninstallString=('"'+(Join-Path $target 'Bastos-Uninstall.exe')+'" /silent');URLInfoAbout='https://github.com/bastos85-Poly/BASTOS'}
        foreach($name in $values.Keys){New-ItemProperty -Path $registration -Name $name -Value $values[$name] -PropertyType String -Force|Out-Null}
        foreach($name in @('NoModify','NoRepair')){New-ItemProperty -Path $registration -Name $name -Value 1 -PropertyType DWord -Force|Out-Null}
    }
    Write-Host "BASTOS $version installé dans $target" -ForegroundColor Green
    if (Test-Path -LiteralPath $backup) { Write-Host "Version précédente conservée dans $backup" }
} finally {
    if (Test-Path -LiteralPath $stage) {
        [void](Assert-ChildPath $parent $stage)
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

