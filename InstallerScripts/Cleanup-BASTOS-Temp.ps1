[CmdletBinding()]
param([switch]$AnalyzeOnly, [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath, [string]$OperationId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force
function Progress([int]$Percent, [string]$Phase, [string]$Message) {
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}
# Check every ancestor, including the TEMP root, before traversal and again before removal.
function Test-SafePath([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -ne $Root -and -not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $cursor = $full
    while ($cursor) {
        if (([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $true
}
try {
    $targets = @()
    $expected = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))
    foreach ($candidate in ($expected | Select-Object -Unique)) {
        if (-not $candidate) { continue }
        $root = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        if ($root.Length -lt 8 -or [IO.Path]::GetFileName($root) -ne 'Temp' -or -not [IO.Directory]::Exists($root)) { continue }
        if (-not (Test-SafePath $root $root)) { throw "Dossier temporaire redirige refuse : $root" }
        $targets += $root
    }
    # Avoid counting overlapping roots twice.
    $targets = @($targets | Where-Object { $r = $_; -not @($targets | Where-Object { $_ -ne $r -and $r.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count })
    if (-not $targets.Count) { throw 'Aucun dossier TEMP valide trouve.' }
    $cutoff = [DateTime]::UtcNow.AddHours(-24)
    $eligible = New-Object 'Collections.Generic.List[object]'
    $count = 0L; $bytes = 0L; $eligibleBytes = 0L; $scanErrors = 0L; $skippedLinks = 0L
    Progress 0 'Analyse' 'Recherche des fichiers temporaires de plus de 24 heures...'
    foreach ($root in $targets) {
        $stack = New-Object 'Collections.Generic.Stack[string]'
        $stack.Push($root)
        while ($stack.Count) {
            $current = $stack.Pop()
            try {
                if (-not (Test-SafePath $current $root)) { $skippedLinks++; continue }
                $items = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
            } catch { $scanErrors++; continue }
            foreach ($item in $items) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skippedLinks++; continue }
                if ($item.PSIsContainer) { $stack.Push($item.FullName); continue }
                if ($item.FullName -eq $ProgressPath -or $item.FullName -eq $ResultPath) { continue }
                $count++; $bytes += $item.Length
                if ($item.LastWriteTimeUtc -lt $cutoff) {
                    $eligible.Add([pscustomobject]@{ Path=$item.FullName; Root=$root; Length=[long]$item.Length; LastWriteTicks=$item.LastWriteTimeUtc.Ticks })
                    $eligibleBytes += $item.Length
                }
            }
        }
    }
    $removed = 0L; $removedBytes = 0L; $failed = 0L
    if (-not $AnalyzeOnly) {
        foreach ($entry in $eligible) {
            Progress (20 + [int](75 * (($removed + $failed) / [double][Math]::Max(1,$eligible.Count)))) 'Suppression' "$removed supprimes, $failed conserves"
            try {
                if (-not (Test-SafePath $entry.Path $entry.Root)) { throw 'Chemin redirige ou hors cible.' }
                $file = Get-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
                if ($file.PSIsContainer -or $file.LastWriteTimeUtc -ge $cutoff -or $file.Length -ne $entry.Length -or $file.LastWriteTimeUtc.Ticks -ne $entry.LastWriteTicks) { throw 'Fichier modifie depuis analyse : conserve.' }
                Remove-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
                if ([IO.File]::Exists($entry.Path) -or [IO.Directory]::Exists($entry.Path)) { throw 'Suppression non confirmee.' }
                $removed++; $removedBytes += $entry.Length
            } catch { $failed++ }
        }
    }
    Progress 98 'Verification' 'Enregistrement des compteurs verifies...'
    Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $true -Message 'Traitement termine.' -Data @{
        AnalyzeOnly=[bool]$AnalyzeOnly; Targets=@($targets); Count=$count; Bytes=$bytes; EligibleCount=$eligible.Count; EligibleBytes=$eligibleBytes
        Removed=$removed; RemovedBytes=$removedBytes; Failed=$failed; ScanErrors=$scanErrors; SkippedLinks=$skippedLinks
        DeletionVerified=$true; CutoffUtc=$cutoff.ToString('o')
    }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.ToString())
    try { Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $false -Message $_.Exception.Message } catch {}
    exit 1
}
