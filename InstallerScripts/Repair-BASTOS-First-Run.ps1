[CmdletBinding()]
param(
    [switch]$MachineOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-DwordValue {
    param([string]$Path, [string]$Name, [int]$Expected)
    $actual = Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
    if ([int]$actual -ne $Expected) {
        throw "Valeur incorrecte pour $Path\$Name : $actual au lieu de $Expected."
    }
}

$kitRoot = Split-Path -Parent $PSCommandPath
$payloadRoot = Join-Path $kitRoot 'Payload'
$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$removalOptions = [pscustomobject]@{RemoveOneDrive=$true;DisableConsumerContent=$true}
$removalOptionsPath = Join-Path $profileRoot 'BASTOS-Removal-Options.json'
if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
    $removalOptions = Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($MachineOnly) {
    if (-not (Test-Administrator)) {
        throw 'La phase machine BASTOS doit etre executee avec l autorisation Windows.'
    }

    $payloadFiles = @(
        'BASTOS-Architecture.psm1',
        'Apply-Machine.ps1',
        'Apply-User.ps1',
        'Complete-BASTOS-UserSetup.ps1',
        'Configure-BASTOS-AfterInstall.ps1',
        'Clear-BASTOS-StandbyList.ps1',
        'Remove-BASTOS-OneDrive.ps1',
        'Remove-BASTOS-Edge.ps1',
        'Bastos.Native\BASTOS-Native.exe',
        'Initialize-BASTOS-Recovery.ps1',
        'VERSION.txt',
        'Configure-PUBG.ps1',
        'Download-BASTOS-WindowsIso.ps1',
        'Download-BASTOS-RadeonTool.ps1',
        'Download-BASTOS-Rufus.ps1',
        'Launch-BASTOS-Rufus.ps1',
        'Invoke-BASTOS-Protected.ps1',
        'Invoke-BASTOS-GraphicsOptimization.ps1'
    )
    $kitFiles = @('Build-BASTOS-ISO.ps1','autounattend.xml','Remove-Appx.txt','Profile.json')
    $assetFiles = @('Bastos-App.ico','Bastos-Logo-Dark-UI.png')
    $resourceDirectories = @('Graphics-Optimizations','WebView2')
    foreach ($fileName in $payloadFiles) {
        $required = Join-Path $payloadRoot $fileName
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Fichier de reparation absent : $required"
        }
    }
    foreach ($fileName in $kitFiles) {
        $required = Join-Path $kitRoot $fileName
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Fichier de reparation absent : $required" }
    }
    foreach ($fileName in $assetFiles) {
        $required = Join-Path $payloadRoot "Assets\$fileName"
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Ressource BASTOS absente : $required" }
    }
    foreach ($directoryName in $resourceDirectories) {
        $required = Join-Path $payloadRoot $directoryName
        if (-not (Test-Path -LiteralPath $required -PathType Container)) { throw "Dossier BASTOS absent : $required" }
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    foreach ($fileName in $payloadFiles) {
        $destination = Join-Path $profileRoot $fileName
        $destinationParent = Split-Path -Parent $destination
        if ($destinationParent) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $payloadRoot $fileName) -Destination $destination -Force
    }
    foreach ($fileName in $kitFiles) {
        Copy-Item -LiteralPath (Join-Path $kitRoot $fileName) -Destination $profileRoot -Force
    }
    $profileAssets = Join-Path $profileRoot 'Assets'
    New-Item -ItemType Directory -Path $profileAssets -Force | Out-Null
    foreach ($fileName in $assetFiles) {
        Copy-Item -LiteralPath (Join-Path $payloadRoot "Assets\$fileName") -Destination $profileAssets -Force
    }
    foreach ($directoryName in $resourceDirectories) {
        $sourceDirectory = Join-Path $payloadRoot $directoryName
        $destinationDirectory = Join-Path $profileRoot $directoryName
        if ([IO.Path]::GetFullPath($sourceDirectory).TrimEnd('\') -ne [IO.Path]::GetFullPath($destinationDirectory).TrimEnd('\')) {
            $destinationParent = Split-Path -Parent $destinationDirectory
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            Copy-Item -LiteralPath $sourceDirectory -Destination $destinationParent -Recurse -Force
        }
    }

    Write-Host 'Reapplication du profil machine BASTOS...'
    & (Join-Path $profileRoot 'Apply-Machine.ps1') -SkipUserRunOnce -Force
    if (-not (Test-Path -LiteralPath (Join-Path $profileRoot 'MachineProfileApplied.ok'))) {
        throw 'Le marqueur MachineProfileApplied.ok n a pas ete cree. Consulte Logs\Apply-Machine.log.'
    }
    Assert-DwordValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -Expected 1
    Write-Host 'Phase machine terminee.' -ForegroundColor Green
    exit 0
}

if (Test-Administrator) {
    throw 'Cette fenetre est deja administrateur. Ferme-la puis lance Reparer-BASTOS-apres-installation.cmd par un double-clic normal, sans choisir Executer en tant qu administrateur.'
}

Write-Host 'BASTOS va demander une autorisation Windows uniquement pour la phase machine.'
$arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-MachineOnly')
$elevated = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
if ($elevated.ExitCode -ne 0) {
    throw "La phase machine BASTOS a echoue avec le code $($elevated.ExitCode)."
}

$userScript = Join-Path $profileRoot 'Apply-User.ps1'
if (-not (Test-Path -LiteralPath $userScript -PathType Leaf)) {
    throw "Le script utilisateur actualise est absent : $userScript"
}

Write-Host 'Reapplication du profil utilisateur dans la session Windows normale...'
& $userScript -Force
if (-not (Test-Path -LiteralPath (Join-Path $profileRoot 'UserProfileApplied.ok'))) {
    throw 'Le marqueur UserProfileApplied.ok n a pas ete cree. Consulte Logs\Apply-User.log.'
}
Assert-DwordValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Expected 1
if ($removalOptions.DisableConsumerContent) {
    Assert-DwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Expected 0
}
foreach ($mouseSetting in @('MouseSpeed','MouseThreshold1','MouseThreshold2')) {
    $actualMouseSetting = [string](Get-ItemPropertyValue -LiteralPath 'HKCU:\Control Panel\Mouse' -Name $mouseSetting -ErrorAction Stop)
    if ($actualMouseSetting -ne '0') { throw "La precision du pointeur reste active : $mouseSetting=$actualMouseSetting." }
}
$directXSettings = [string](Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings' -ErrorAction Stop)
if ($directXSettings -notmatch '(^|;)SwapEffectUpgradeEnable=1;') {
    throw 'Le reglage DirectX utilisateur n a pas ete applique.'
}

Write-Host ''
Write-Host 'Reparation terminee : profils machine et utilisateur verifies.' -ForegroundColor Green
Write-Host 'Les pilotes sont exclus des mises a jour qualite Windows Update.' -ForegroundColor Green
Write-Host 'Aucun reformatage n est necessaire.' -ForegroundColor Green
