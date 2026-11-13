[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$RamMapPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop

$expectedSha256 = 'E970913798481432CD590991577089E68510B861DC669DCAB24FEB06AAE0DF52'

function Write-WorkerProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}

function Write-WorkerResult {
    param([hashtable]$Data)
    Write-BastosJsonFile -Path $ResultPath -Data $Data
}

function Get-StandbyMemoryMB {
    $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    if (-not $memory) { return 0 }
    $bytes = [double]$memory.StandbyCacheCoreBytes +
             [double]$memory.StandbyCacheNormalPriorityBytes +
             [double]$memory.StandbyCacheReserveBytes
    return [math]::Round($bytes / 1MB,0)
}

try {
    foreach ($folder in @((Split-Path -Parent $ProgressPath),(Split-Path -Parent $ResultPath))) {
        if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    }
    Write-WorkerProgress -Percent 5 -Phase 'Etape 1/3 - Verification' -Message 'Controle de RAMMap64...'

    if (@(Get-Process -Name 'TslGame','PUBG' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Un jeu PUBG est en cours. Ferme-le avant de vider la standby list.'
    }
    if (-not (Test-Path -LiteralPath $RamMapPath -PathType Leaf)) {
        throw "RAMMap64 est introuvable : $RamMapPath"
    }
    $actualSha256 = (Get-FileHash -LiteralPath $RamMapPath -Algorithm SHA256).Hash
    if ($actualSha256 -ne $expectedSha256) {
        throw "La copie de RAMMap64 ne correspond pas a la version Microsoft approuvee."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $RamMapPath
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
        -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'La signature Microsoft de RAMMap64 est invalide ou absente.'
    }

    $beforeStandby = Get-StandbyMemoryMB
    Write-WorkerProgress -Percent 35 -Phase 'Etape 2/3 - Standby list' -Message "$beforeStandby Mo en attente avant operation"
    if (-not $DryRun) {
        $process = Start-Process -FilePath $RamMapPath -ArgumentList @('-Et','-accepteula') -Verb RunAs -PassThru -Wait
        if ($process.ExitCode -ne 0) {
            if ($process.ExitCode -eq 1223) { throw 'Autorisation Windows annulee.' }
            throw "RAMMap64 a retourne le code $($process.ExitCode)."
        }
    }

    Write-WorkerProgress -Percent 90 -Phase 'Etape 3/3 - Mesure' -Message 'Mesure de la standby list apres operation...'
    Start-Sleep -Milliseconds 800
    $afterStandby = if ($DryRun) { $beforeStandby } else { Get-StandbyMemoryMB }
    $released = [math]::Max(0,$beforeStandby - $afterStandby)
    Write-WorkerResult -Data @{
        Success = $true
        BeforeStandbyMB = $beforeStandby
        AfterStandbyMB = $afterStandby
        ReleasedStandbyMB = $released
        RamMapVersion = (Get-Item -LiteralPath $RamMapPath).VersionInfo.FileVersion
        DryRun = [bool]$DryRun
    }
    Write-WorkerProgress -Percent 100 -Phase 'Termine' -Message "$released Mo retires de la standby list"
    exit 0
} catch {
    try { Write-WorkerResult -Data @{ Success=$false; Error=$_.Exception.Message } } catch {}
    try { Write-WorkerProgress -Percent 100 -Phase 'Erreur' -Message $_.Exception.Message } catch {}
    exit 1
}
