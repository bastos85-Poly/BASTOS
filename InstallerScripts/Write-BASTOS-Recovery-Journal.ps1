[CmdletBinding()]
param(
    [ValidateSet('RecordCurrent','CollectDiagnostics')]
    [string]$Mode = 'CollectDiagnostics'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RecoveryRoot {
    $localCandidate = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $localCandidate 'BASTOS-BOOT-ID.txt')) {
        return $localCandidate.TrimEnd('\')
    }
    $volume = Get-Volume -FileSystemLabel 'BASTOS_RECOVERY' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $volume -or -not $volume.DriveLetter) { throw 'Partition BASTOS_RECOVERY introuvable.' }
    return ('{0}:' -f $volume.DriveLetter)
}

$recoveryRoot = Get-RecoveryRoot
$applicationRoot = Join-Path $recoveryRoot 'Application'
$diagnosticRoot = Join-Path $recoveryRoot 'BASTOS-Diagnostics'
$journalPath = Join-Path $diagnosticRoot 'Recovery-Journal.log'
$statePath = Join-Path $recoveryRoot 'BASTOS-LAST-KNOWN-GOOD.json'
New-Item -ItemType Directory -Path $diagnosticRoot -Force | Out-Null

function Write-Journal {
    param([string]$Message,[ValidateSet('INFO','OK','WARN','ERROR')][string]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Add-Content -LiteralPath $journalPath -Value $line -Encoding UTF8
}

function Get-FileRecord {
    param([string]$RelativePath,[switch]$Hash)
    $path = Join-Path $recoveryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ Path=$RelativePath; Present=$false }
    }
    $item = Get-Item -LiteralPath $path -Force
    $record = [ordered]@{
        Path = $RelativePath
        Present = $true
        Length = $item.Length
        LastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
    }
    if ($Hash) { $record.Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    return $record
}

try {
    $versionPath = Join-Path $applicationRoot 'VERSION.txt'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { throw 'Application\VERSION.txt absent.' }
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()

    if ($Mode -eq 'RecordCurrent') {
        $state = [ordered]@{
            Schema = 1
            BastosVersion = $version
            Status = 'LAST_KNOWN_GOOD'
            RecordedUtc = [DateTime]::UtcNow.ToString('o')
            RecoveryVolume = $recoveryRoot
            ComputerName = $env:COMPUTERNAME
            Files = @(
                (Get-FileRecord 'Application\VERSION.txt' -Hash),
                (Get-FileRecord 'Application\Bastos.Native\BASTOS-Native.exe' -Hash),
                (Get-FileRecord 'Application\Assets\Bastos-App.ico' -Hash),
                (Get-FileRecord 'Application\Cleanup-BASTOS-Temp.ps1' -Hash),
                (Get-FileRecord 'Application\General-Optimization-Tools\25-DevicePower.ps1' -Hash),
                (Get-FileRecord 'Application\General-Optimization-Tools\26 Network Adapter Power Savings & Wake.ps1' -Hash),
                (Get-FileRecord 'Application\General-Optimization-Tools\27 Network IPv4 Only.ps1' -Hash),
                (Get-FileRecord 'Application\General-Optimization-Tools\28 Write Cache Buffer Flushing.ps1' -Hash),
                (Get-FileRecord 'Application\General-Optimization-Tools\30 Timer Resolution.ps1' -Hash),
                (Get-FileRecord 'Application\Initialize-BASTOS-Recovery.ps1' -Hash),
                (Get-FileRecord 'Application\autounattend.xml' -Hash),
                (Get-FileRecord 'BASTOS-Recovery-Unattend.xml' -Hash),
                (Get-FileRecord 'BASTOS-RECOVERY-SELECTION.json' -Hash),
                (Get-FileRecord 'BASTOS-WINDOWS-DISK-ID.txt' -Hash),
                (Get-FileRecord 'BASTOS-WINDOWS-DISK-CHECK.txt' -Hash),
                (Get-FileRecord 'BASTOS-LAYOUT-DISK0.ok' -Hash),
                (Get-FileRecord 'sources\boot.wim' -Hash),
                (Get-FileRecord 'sources\install.wim')
            )
        }
        [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        Write-Journal "Version BASTOS $version enregistrée comme dernière version connue." 'OK'
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $sessionRoot = Join-Path $diagnosticRoot $stamp
    New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
    foreach ($source in @(
        'C:\Windows\Panther\setuperr.log',
        'C:\Windows\Panther\setupact.log',
        'C:\Windows\Panther\UnattendGC\setuperr.log',
        'C:\Windows\Panther\UnattendGC\setupact.log',
        'C:\Windows\Logs\CBS\CBS.log'
    )) {
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $sessionRoot -Force -ErrorAction SilentlyContinue
        }
    }
    $setupState = [ordered]@{
        CollectedUtc = [DateTime]::UtcNow.ToString('o')
        BastosVersion = $version
        LastKnownGood = if(Test-Path -LiteralPath $statePath){Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json}else{$null}
        ChildCompletion = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup\Status\ChildCompletion' -ErrorAction SilentlyContinue
        Setup = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue | Select-Object SystemSetupInProgress,OOBEInProgress,SetupPhase,SetupType,CmdLine,RestartSetup
    }
    [IO.File]::WriteAllText((Join-Path $sessionRoot 'Setup-State.json'), ($setupState | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Journal "Diagnostic enregistré dans $sessionRoot pour BASTOS $version." 'OK'
}
catch {
    try { Write-Journal $_.Exception.Message 'ERROR' } catch {}
    throw
}
