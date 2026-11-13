[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RealExecutable,
    [int]$RestartDelayMilliseconds = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BastosRealWindow {
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@

$realPath = [IO.Path]::GetFullPath($RealExecutable)
$toolRoot = Split-Path -Parent $realPath
$stopRequestPath = Join-Path $toolRoot 'watchdog.stop'
$pidPath = Join-Path $toolRoot 'watchdog.pid'

if (-not (Test-Path -LiteralPath $realPath -PathType Leaf)) {
    throw "REAL est introuvable : $realPath"
}

if (Test-Path -LiteralPath $stopRequestPath -PathType Leaf) {
    Remove-Item -LiteralPath $stopRequestPath -Force
}
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII

try {
    while (-not (Test-Path -LiteralPath $stopRequestPath -PathType Leaf)) {
        $realProcess = Start-Process -FilePath $realPath -WorkingDirectory $toolRoot -WindowStyle Hidden -PassThru
        while (-not $realProcess.HasExited -and -not (Test-Path -LiteralPath $stopRequestPath -PathType Leaf)) {
            Start-Sleep -Milliseconds 250
            try { $realProcess.Refresh() } catch {}
            if ($realProcess.HasExited) { break }
            $windowHandle = $realProcess.MainWindowHandle
            if ($null -ne $windowHandle -and $windowHandle -ne [IntPtr]::Zero -and [BastosRealWindow]::IsWindowVisible($windowHandle)) {
                [void][BastosRealWindow]::ShowWindowAsync($windowHandle, 0)
            }
        }
        if ((Test-Path -LiteralPath $stopRequestPath -PathType Leaf) -and -not $realProcess.HasExited) {
            Stop-Process -Id $realProcess.Id -Force -ErrorAction SilentlyContinue
            break
        }
        if (-not (Test-Path -LiteralPath $stopRequestPath -PathType Leaf)) {
            Start-Sleep -Milliseconds $RestartDelayMilliseconds
        }
    }
} finally {
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
}
