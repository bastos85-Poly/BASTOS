Set-StrictMode -Version Latest

$script:BastosRecoveryLabel = 'BASTOS_RECOVERY'
$script:BastosRuntimeRoot = 'C:\ProgramData\BASTOS-ISO'

function Get-BastosRuntimeRoot {
    [CmdletBinding()]
    param()
    return $script:BastosRuntimeRoot
}

function Get-BastosRecoveryRoot {
    [CmdletBinding()]
    param([ValidateRange(0, 120)][int]$WaitSeconds = 0)

    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    do {
        $volumes = @(Get-Volume -FileSystemLabel $script:BastosRecoveryLabel -ErrorAction SilentlyContinue)
        if ($volumes.Count -gt 1) {
            throw "Plusieurs volumes $script:BastosRecoveryLabel ont ete detectes. Operation refusee pour eviter une cible ambigue."
        }
        if ($volumes.Count -eq 1 -and $volumes[0].DriveLetter) {
            return ('{0}:\' -f $volumes[0].DriveLetter)
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 500
    } while ($true)

    throw "Volume $script:BastosRecoveryLabel introuvable ou non monte."
}

function Invoke-BastosRuntimeSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [string]$DestinationRoot = $script:BastosRuntimeRoot
    )

    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $destination = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Source BASTOS absente : $source"
    }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $mutex = [Threading.Mutex]::new($false, 'Global\BASTOS-Runtime-Sync')
    $lockTaken = $false
    try {
        try {
            $lockTaken = $mutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [Threading.AbandonedMutexException] {
            $lockTaken = $true
        }
        if (-not $lockTaken) { throw 'Une synchronisation BASTOS est deja en cours.' }

        $arguments = @(
            $source, $destination,
            '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:1', '/XJ',
            '/FFT', '/NP', '/NFL', '/NDL',
            '/XD', 'Logs', 'Backups', '.codex-backup-*',
            '/XF', '*.ok',
            'BASTOS-App-Manifest.json', 'BASTOS-Build.json',
            'Browser-Selection.json', 'Regional-Selection.json', 'Remove-Appx-Selection.txt',
            'Appx-Machine-Removal.json', 'Edge-Machine-Removal.json',
            'OneDrive-Machine-Removal.json', 'OneDrive-User-Removal.json',
            'Last-Built-Iso.txt'
        )
        & "$env:SystemRoot\System32\robocopy.exe" @arguments | Out-Null
        $exitCode = $LASTEXITCODE
        if ($exitCode -ge 8) { throw "Synchronisation BASTOS echouee (Robocopy $exitCode)." }

        Get-ChildItem -LiteralPath $destination -Force -File -Filter '*.ok' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue

        [pscustomobject]@{
            Source = $source
            Destination = $destination
            RobocopyExitCode = $exitCode
            Changed = [bool]($exitCode -band 1)
        }
    }
    finally {
        if ($lockTaken) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

Export-ModuleMember -Function Get-BastosRuntimeRoot,Get-BastosRecoveryRoot,Invoke-BastosRuntimeSync
