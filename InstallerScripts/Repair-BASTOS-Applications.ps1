[CmdletBinding()]
param(
    [switch]$MachineOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-BastosAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Repair-BastosGamingServices {
    $presentBefore = @(Get-AppxPackage -AllUsers -Name 'Microsoft.GamingServices' -ErrorAction SilentlyContinue).Count -gt 0
    $attempted = $false
    $exitCode = $null
    $errorMessage = ''
    if (-not $presentBefore) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($winget -and $winget.Source) {
            $attempted = $true
            try {
                $arguments = 'install --id 9MWPM2CQNLHN --exact --source msstore --force --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
                $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
                if (-not $process.WaitForExit(300000)) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    $errorMessage = 'Installation Gaming Services interrompue apres cinq minutes.'
                } else { $exitCode = $process.ExitCode }
            } catch { $errorMessage = $_.Exception.Message }
            Start-Sleep -Seconds 8
        } else { $errorMessage = 'WinGet indisponible dans la phase administrateur.' }
    }
    $presentAfter = @(Get-AppxPackage -AllUsers -Name 'Microsoft.GamingServices' -ErrorAction SilentlyContinue).Count -gt 0
    $status = [pscustomobject]@{
        Success=$presentAfter
        PresentBefore=$presentBefore
        Attempted=$attempted
        ExitCode=$exitCode
        Error=$errorMessage
        CheckedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $profileRoot 'Xbox-GamingServices-Repair.json'),($status | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    if ($presentAfter) { Write-Host 'Gaming Services est present pour Xbox et Game Pass.' -ForegroundColor Green }
    else { Write-Warning 'Gaming Services reste absent. Ouvre ensuite application Xbox et accepte son installation Microsoft Store si elle est proposee.' }
}

$kitRoot = Split-Path -Parent $PSCommandPath
$payloadRoot = Join-Path $kitRoot 'Payload'
$profileRoot = 'C:\ProgramData\BASTOS-ISO'

if ($MachineOnly) {
    if (-not (Test-BastosAdministrator)) { throw 'La phase machine doit etre autorisee par Windows.' }
    $backupRoot = Join-Path $profileRoot ('Backups\Applications-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    foreach ($name in @('Remove-Appx.txt','Remove-Appx-Selection.txt','BASTOS-Architecture.psm1','Apply-Machine.ps1','Apply-User.ps1','Configure-BASTOS-AfterInstall.ps1','Clear-BASTOS-StandbyList.ps1','Complete-BASTOS-UserSetup.ps1','Remove-BASTOS-OneDrive.ps1','Remove-BASTOS-Edge.ps1','Bastos.Native\BASTOS-Native.exe','Initialize-BASTOS-Recovery.ps1','Install-BASTOS-AdkDeploymentTools.ps1','Download-BASTOS-RadeonTool.ps1','Invoke-BASTOS-Protected.ps1','Audit-PUBG-System.ps1','Build-BASTOS-ISO.ps1','Profile.json')) {
        $existing = Join-Path $profileRoot $name
        if (Test-Path -LiteralPath $existing -PathType Leaf) { Copy-Item -LiteralPath $existing -Destination $backupRoot -Force }
    }

    foreach ($name in @('BASTOS-Architecture.psm1','Apply-Machine.ps1','Apply-User.ps1','Configure-BASTOS-AfterInstall.ps1','Clear-BASTOS-StandbyList.ps1','Complete-BASTOS-UserSetup.ps1','Remove-BASTOS-OneDrive.ps1','Remove-BASTOS-Edge.ps1','Bastos.Native\BASTOS-Native.exe','Initialize-BASTOS-Recovery.ps1','Install-BASTOS-AdkDeploymentTools.ps1','Download-BASTOS-RadeonTool.ps1','Invoke-BASTOS-Protected.ps1','Audit-PUBG-System.ps1')) {
        $source = Join-Path $payloadRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Module BASTOS absent : $source" }
        $destination = Join-Path $profileRoot $name
        $destinationParent = Split-Path -Parent $destination
        if ($destinationParent) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    foreach ($name in @('Build-BASTOS-ISO.ps1','Profile.json')) {
        $source = Join-Path $kitRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Fichier BASTOS absent : $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $profileRoot $name) -Force
    }
    $removeList = Join-Path $kitRoot 'Remove-Appx.txt'
    if (-not (Test-Path -LiteralPath $removeList -PathType Leaf)) { throw "Liste BASTOS absente : $removeList" }
    Copy-Item -LiteralPath $removeList -Destination (Join-Path $profileRoot 'Remove-Appx.txt') -Force
    $selectionPath = Join-Path $profileRoot 'Remove-Appx-Selection.txt'
    if (-not (Test-Path -LiteralPath $selectionPath -PathType Leaf)) {
        $defaultNames = @(Get-Content -LiteralPath $removeList -Encoding UTF8)
        $removalOptionsPath = Join-Path $profileRoot 'BASTOS-Removal-Options.json'
        if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
            $removalOptions = Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $removalOptions.RemoveOneDrive) {
                $defaultNames = @($defaultNames | Where-Object { $_.Trim() -ne 'Microsoft.OneDriveSync' })
            }
        }
        [IO.File]::WriteAllLines($selectionPath,$defaultNames,[Text.UTF8Encoding]::new($false))
    }

    & (Join-Path $profileRoot 'Apply-Machine.ps1') -SkipUserRunOnce -Force
    if (-not (Test-Path -LiteralPath (Join-Path $profileRoot 'MachineProfileApplied.ok') -PathType Leaf)) {
        throw 'La verification machine BASTOS a echoue.'
    }
    Repair-BastosGamingServices
    exit 0
}

if (Test-BastosAdministrator) {
    throw 'Lance ce script par un double-clic normal afin que la phase utilisateur reste dans le bon compte.'
}

Write-Host 'Windows va demander une autorisation pour retirer aussi le provisionnement machine des applications.'
$arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-MachineOnly')
$elevated = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
if ($elevated.ExitCode -ne 0) { throw "La phase machine a echoue avec le code $($elevated.ExitCode)." }

$completion = & (Join-Path $profileRoot 'Complete-BASTOS-UserSetup.ps1') -MaxAttempts 2 -WingetWaitSeconds 90
if (-not [bool]$completion.Success) {
    throw "Le nettoyage utilisateur reste incomplet : $(@($completion.Failures) -join ', ')."
}

Write-Host 'Rectification BASTOS appliquee selon les choix de suppression de cette ISO.' -ForegroundColor Green
