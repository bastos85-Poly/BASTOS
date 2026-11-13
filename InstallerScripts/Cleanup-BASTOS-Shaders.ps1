[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop

function Write-WorkerProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}

function Write-WorkerResult {
    param([hashtable]$Data)
    Write-BastosJsonFile -Path $ResultPath -Data $Data
}

function Add-Target {
    param([Collections.Generic.List[object]]$List,[string]$Name,[string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return }
    if (-not [IO.Directory]::Exists($full)) { return }
    $root = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (-not $root -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
    if (@($List | Where-Object { $_.Path -eq $full }).Count -eq 0) {
        $List.Add([pscustomobject]@{ Name=$Name; Path=$full })
    }
}

try {
    $progressFolder = Split-Path -Parent $ProgressPath
    $resultFolder = Split-Path -Parent $ResultPath
    if ($progressFolder) { New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null }
    if ($resultFolder) { New-Item -ItemType Directory -Path $resultFolder -Force | Out-Null }

    $gpuNames = @((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Name }))
    $hasAmd = @($gpuNames | Where-Object { $_ -match 'AMD|Radeon' }).Count -gt 0
    $hasNvidia = @($gpuNames | Where-Object { $_ -match 'NVIDIA|GeForce' }).Count -gt 0
    $hasIntel = @($gpuNames | Where-Object { $_ -match 'Intel' }).Count -gt 0
    $targets = New-Object 'Collections.Generic.List[object]'
    Add-Target $targets 'DirectX Windows' $(if($env:LOCALAPPDATA){Join-Path $env:LOCALAPPDATA 'D3DSCache'}else{$null})
    if ($hasAmd -and $env:LOCALAPPDATA) {
        Add-Target $targets 'AMD DxCache' (Join-Path $env:LOCALAPPDATA 'AMD\DxCache')
        Add-Target $targets 'AMD DxcCache' (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache')
        Add-Target $targets 'AMD GLCache' (Join-Path $env:LOCALAPPDATA 'AMD\GLCache')
        Add-Target $targets 'AMD VkCache' (Join-Path $env:LOCALAPPDATA 'AMD\VkCache')
    }
    if ($hasNvidia -and $env:LOCALAPPDATA) {
        Add-Target $targets 'NVIDIA DXCache' (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache')
        Add-Target $targets 'NVIDIA GLCache' (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache')
        if ($env:ProgramData) { Add-Target $targets 'NVIDIA NV_Cache' (Join-Path $env:ProgramData 'NVIDIA Corporation\NV_Cache') }
    }
    if ($hasIntel -and $env:LOCALAPPDATA) {
        Add-Target $targets 'Intel ShaderCache' (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache')
    }

    Write-WorkerProgress -Percent 5 -Phase 'Etape 1/3 - Detection' -Message ("GPU : " + $(if($gpuNames.Count){$gpuNames -join ', '}else{'information indisponible'}))
    $files = New-Object 'Collections.Generic.List[IO.FileInfo]'
    $totalBytes = 0L
    foreach ($target in $targets) {
        $stack = New-Object 'Collections.Generic.Stack[string]'
        $stack.Push([string]$target.Path)
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($item.PSIsContainer) { $stack.Push($item.FullName); continue }
                $files.Add([IO.FileInfo]$item)
                try { $totalBytes += [int64]$item.Length } catch {}
                if (($files.Count % 100) -eq 0) { Write-WorkerProgress -Percent 10 -Phase 'Etape 1/3 - Analyse' -Message "$($files.Count) fichiers shaders reperes..." }
            }
        }
    }

    $removed = 0
    $failed = 0
    $removedBytes = 0L
    $count = $files.Count
    Write-WorkerProgress -Percent 15 -Phase 'Etape 2/3 - Suppression' -Message "$count fichiers shaders a traiter"
    for ($index=0; $index -lt $count; $index++) {
        $file = $files[$index]
        $percent = if($count -eq 0){95}else{15 + [int][math]::Floor(80 * (($index + 1) / [double]$count))}
        Write-WorkerProgress -Percent $percent -Phase 'Etape 2/3 - Suppression' -Message ("{0}/{1} - {2}" -f ($index+1),$count,$file.Name)
        try {
            $length = [int64]$file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
            $removedBytes += $length
        } catch { $failed++ }
    }

    Write-WorkerProgress -Percent 98 -Phase 'Etape 3/3 - Rapport' -Message 'Calcul du resultat final...'
    $names = @($targets | ForEach-Object { $_.Name })
    $reclaimedMB = [math]::Round($removedBytes / 1MB,1)
    Write-WorkerResult -Data @{ Success=$true; Count=$count; Removed=$removed; Failed=$failed; ReclaimedMB=$reclaimedMB; Targets=$names }
    Write-WorkerProgress -Percent 100 -Phase 'Termine' -Message "$removed fichiers supprimes - $reclaimedMB Mo liberes"
    exit 0
} catch {
    try { Write-WorkerResult -Data @{ Success=$false; Error=$_.Exception.Message } } catch {}
    try { Write-WorkerProgress -Percent 100 -Phase 'Erreur' -Message $_.Exception.Message } catch {}
    exit 1
}
