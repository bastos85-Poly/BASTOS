[CmdletBinding()]
param(
    [string]$PubgExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PubgExe) {
    $candidates = @()
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
        $candidates += Join-Path $drive.Root 'SteamLibrary\steamapps\common\PUBG\TslGame\Binaries\Win64\TslGame.exe'
        $candidates += Join-Path $drive.Root 'Program Files (x86)\Steam\steamapps\common\PUBG\TslGame\Binaries\Win64\TslGame.exe'
        $candidates += Join-Path $drive.Root 'Program Files\Steam\steamapps\common\PUBG\TslGame\Binaries\Win64\TslGame.exe'
    }
    $PubgExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $PubgExe -or -not (Test-Path -LiteralPath $PubgExe -PathType Leaf)) {
    throw 'TslGame.exe est introuvable. Relance avec -PubgExe "D:\...\TslGame.exe".'
}

$fullPath = (Resolve-Path -LiteralPath $PubgExe).Path
$gpuPrefs = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (-not (Test-Path -Path $gpuPrefs)) { New-Item -Path $gpuPrefs -Force | Out-Null }
New-ItemProperty -Path $gpuPrefs -Name $fullPath -PropertyType String -Value 'GpuPreference=2;' -Force | Out-Null
Write-Host "PUBG utilise maintenant la preference GPU haute performance : $fullPath" -ForegroundColor Green
Write-Host 'Aucun drapeau de compatibilite ni desactivation des optimisations plein ecran n''a ete applique.'
