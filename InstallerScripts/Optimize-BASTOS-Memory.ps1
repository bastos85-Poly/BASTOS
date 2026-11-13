[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-WorkerProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    $safePhase = $Phase -replace "[`r`n`t]",' '
    $safeMessage = $Message -replace "[`r`n`t]",' '
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes("$Percent`t$safePhase`t$safeMessage")
    for ($attempt=0; $attempt -lt 50; $attempt++) {
        $stream = $null
        try {
            $stream = [IO.FileStream]::new($ProgressPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
            $stream.SetLength(0)
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Flush($true)
            return
        } catch [IO.IOException] {
            if ($attempt -eq 49) { throw }
            Start-Sleep -Milliseconds 10
        } finally { if ($stream) { $stream.Dispose() } }
    }
}

function Write-WorkerResult {
    param([hashtable]$Data)
    [IO.File]::WriteAllText($ResultPath,($Data | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($true))
}

function Get-AvailableMemoryMB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return 0 }
    return [math]::Round([double]$os.FreePhysicalMemory / 1024,0)
}

try {
    $progressFolder = Split-Path -Parent $ProgressPath
    $resultFolder = Split-Path -Parent $ResultPath
    if ($progressFolder) { New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null }
    if ($resultFolder) { New-Item -ItemType Directory -Path $resultFolder -Force | Out-Null }
    Write-WorkerProgress -Percent 5 -Phase 'Etape 1/3 - Verification' -Message 'Recherche des applications utilisateur...'

    if (@(Get-Process -Name 'TslGame','PUBG' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Un jeu PUBG est en cours. Ferme-le avant d alleger la RAM.'
    }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BastosWorkingSet {
    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool EmptyWorkingSet(IntPtr process);
}
'@
    $sessionId = (Get-Process -Id $PID).SessionId
    $excluded = @('idle','system','registry','secure system','smss','csrss','wininit','services','lsass','svchost','fontdrvhost','dwm','explorer','sihost','ctfmon','conhost','powershell','pwsh','taskhostw','runtimebroker','searchhost','startmenuexperiencehost','shellexperiencehost','textinputhost','applicationframehost')
    $targets = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -ne $PID -and $_.SessionId -eq $sessionId -and $_.WorkingSet64 -ge 50MB -and $_.MainWindowHandle -ne 0 -and $excluded -notcontains $_.ProcessName.ToLowerInvariant()
    } | Sort-Object WorkingSet64 -Descending)
    $beforeAvailable = Get-AvailableMemoryMB
    $beforeWorkingSet = [int64](($targets | Measure-Object WorkingSet64 -Sum).Sum)
    $processed = 0
    $failed = 0
    Write-WorkerProgress -Percent 15 -Phase 'Etape 2/3 - Allegement' -Message "$($targets.Count) applications non critiques a traiter"
    for ($index=0; $index -lt $targets.Count; $index++) {
        $process = $targets[$index]
        $percent = if($targets.Count -eq 0){90}else{15 + [int][math]::Floor(75 * (($index + 1) / [double]$targets.Count))}
        Write-WorkerProgress -Percent $percent -Phase 'Etape 2/3 - Allegement' -Message ("{0}/{1} - {2}" -f ($index+1),$targets.Count,$process.ProcessName)
        try {
            if ($DryRun -or [BastosWorkingSet]::EmptyWorkingSet($process.Handle)) { $processed++ } else { $failed++ }
        } catch { $failed++ }
    }
    Write-WorkerProgress -Percent 94 -Phase 'Etape 3/3 - Mesure' -Message 'Mesure de la RAM apres operation...'
    Start-Sleep -Milliseconds 700
    $afterAvailable = Get-AvailableMemoryMB
    $afterWorkingSet = 0L
    foreach ($target in $targets) {
        try { $afterWorkingSet += [int64](Get-Process -Id $target.Id -ErrorAction Stop).WorkingSet64 } catch {}
    }
    $released = [math]::Max(0,$beforeWorkingSet - $afterWorkingSet)
    $releasedMB = [math]::Round($released / 1MB,1)
    Write-WorkerResult -Data @{ Success=$true; Processed=$processed; Failed=$failed; BeforeAvailableMB=$beforeAvailable; AfterAvailableMB=$afterAvailable; ReleasedWorkingSetMB=$releasedMB }
    Write-WorkerProgress -Percent 100 -Phase 'Termine' -Message "$processed applications traitees - $releasedMB Mo retires des ensembles de travail"
    exit 0
} catch {
    try { Write-WorkerResult -Data @{ Success=$false; Error=$_.Exception.Message } } catch {}
    try { Write-WorkerProgress -Percent 100 -Phase 'Erreur' -Message $_.Exception.Message } catch {}
    exit 1
}
