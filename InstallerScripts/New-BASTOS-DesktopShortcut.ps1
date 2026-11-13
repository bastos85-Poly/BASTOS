[CmdletBinding()]
param([string]$IdentityPath='', [switch]$CommonStartMenuOnly)
$ErrorActionPreference='Stop'
if(-not $IdentityPath){$IdentityPath=Join-Path $PSScriptRoot 'SetupDiagnostics-Identity.json'}

function Resolve-BastosShortcutApplication {
    param([Parameter(Mandatory)]$Identity)
    $windowsApplication=Join-Path $env:ProgramData 'BASTOS-ISO'
    $windowsBuild=Join-Path $windowsApplication 'BASTOS-Build.json'
    $windowsManifest=Join-Path $windowsApplication 'BASTOS-App-Manifest.json'
    if((Test-Path -LiteralPath $windowsBuild -PathType Leaf) -and (Test-Path -LiteralPath $windowsManifest -PathType Leaf)){
        $build=Get-Content -LiteralPath $windowsBuild -Raw -Encoding UTF8|ConvertFrom-Json
        if((Get-FileHash -LiteralPath $windowsManifest -Algorithm SHA256).Hash -ne [string]$build.AppManifestSha256){throw 'Application Windows : manifeste invalide.'}
        $manifest=Get-Content -LiteralPath $windowsManifest -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($entry in $manifest.Files){
            $relative=([string]$entry.Path).Replace('/','\')
            if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or @($relative.Split('\')|Where-Object{$_ -in @('.','..')}).Count){throw "Chemin interdit : $relative"}
            if((Get-FileHash -LiteralPath (Join-Path $windowsApplication $relative) -Algorithm SHA256).Hash -ne [string]$entry.Sha256){throw "Application Windows incomplete : $relative"}
        }
        return $windowsApplication
    }
    $partitionGuid=[guid]$Identity.RecoveryPartitionGuid
    $diskGuid=[guid]$Identity.WindowsDiskIdentity
    if($partitionGuid -eq [guid]::Empty -or $diskGuid -eq [guid]::Empty){throw 'Identites du disque Recovery absentes.'}
    $matches=@(foreach($volume in @(Get-Volume -FileSystemLabel BASTOS_RECOVERY -ErrorAction Stop)){
        if(-not $volume.DriveLetter -or $volume.FileSystem -ne 'NTFS'){continue}
        $partition=Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
        $disk=Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        if(([guid]$partition.Guid) -eq $partitionGuid -and ([guid]$disk.Guid) -eq $diskGuid){
            Join-Path (([string]$volume.DriveLetter)+':\') 'Application'
        }
    })
    if($matches.Count -ne 1){throw 'Application BASTOS introuvable sur la partition Recovery verifiee.'}
    return $matches[0]
}

function New-BastosDesktopShortcut {
    param([Parameter(Mandatory)][string]$ApplicationRoot,[Parameter(Mandatory)][string]$DesktopPath)
    $exe=Join-Path $ApplicationRoot 'Bastos.Native\BASTOS-Native.exe'
    $build=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'BASTOS-Build.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $build.NativeAppSha256){throw 'Executable BASTOS non conforme au manifeste.'}
    New-Item -ItemType Directory -Path $DesktopPath -Force|Out-Null
    $shortcutPath=Join-Path $DesktopPath 'BASTOS.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath=$exe
    $shortcut.WorkingDirectory=Split-Path -Parent $exe
    $shortcut.IconLocation=$exe+',0'
    $shortcut.Description='BASTOS — Réglages, logiciels et réinstallation'
    $shortcut.Save()
    $verified=$shell.CreateShortcut($shortcutPath)
    if($verified.TargetPath -ne $exe -or $verified.IconLocation -ne ($exe+',0')){throw 'Raccourci Bureau BASTOS non conforme.'}
    return $shortcutPath
}

$identity=Get-Content -LiteralPath $IdentityPath -Raw -Encoding UTF8|ConvertFrom-Json
$application=Resolve-BastosShortcutApplication -Identity $identity
if(-not $CommonStartMenuOnly){
    $desktop=[Environment]::GetFolderPath('DesktopDirectory')
    if([string]::IsNullOrWhiteSpace($desktop)){throw 'Bureau du compte local indisponible.'}
    $shortcut=New-BastosDesktopShortcut -ApplicationRoot $application -DesktopPath $desktop
}
$startMenu=[Environment]::GetFolderPath('CommonPrograms')
if([string]::IsNullOrWhiteSpace($startMenu)){throw 'Menu Demarrer commun indisponible.'}
$startShortcut=New-BastosDesktopShortcut -ApplicationRoot $application -DesktopPath $startMenu
if($CommonStartMenuOnly){
    Write-Output ('Raccourci BASTOS commun verifie avant la premiere connexion : '+$startShortcut)
    return
}
$logs=Join-Path $PSScriptRoot 'Logs'
New-Item -ItemType Directory -Path $logs -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $logs 'DesktopShortcut.ok'),$shortcut,[Text.UTF8Encoding]::new($false))
