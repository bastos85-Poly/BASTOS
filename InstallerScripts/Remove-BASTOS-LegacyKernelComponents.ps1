[CmdletBinding()]
param([string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$removed = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

function Add-Removed([string]$Message) { $removed.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }
function Repair-SystemFile([string]$Path,[switch]$WhenDifferentFromCmd) {
    $needsRepair = -not (Test-Path -LiteralPath $Path -PathType Leaf)
    if (-not $needsRepair -and $WhenDifferentFromCmd) {
        $cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
        if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
            $needsRepair = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $cmdPath -Algorithm SHA256).Hash
        }
    }
    if (-not $needsRepair) { return }
    & sfc.exe "/scanfile=$Path" | Out-Null
    if ($LASTEXITCODE -in @(0, 1, 2) -and (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Removed "Fichier système Windows restauré : $Path" }
    else { Add-Warning "Windows n'a pas pu restaurer automatiquement : $Path" }
}

try {
    foreach ($process in @(Get-Process -Name 'KRNLGame' -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $process.Id -Force -ErrorAction Stop; Add-Removed 'Processus KRNLGame arrêté.' }
        catch { Add-Warning "KRNLGame n'a pas pu être arrêté : $($_.Exception.Message)" }
    }

    foreach ($runKey in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )) {
        if (-not (Test-Path -LiteralPath $runKey)) { continue }
        $properties = Get-ItemProperty -LiteralPath $runKey
        foreach ($name in @('KRNLGame', 'Kernel Game', 'KernelOS Toolbox', 'KOS Post Install')) {
            if ($null -ne $properties.PSObject.Properties[$name]) {
                Remove-ItemProperty -LiteralPath $runKey -Name $name -Force
                Add-Removed "Démarrage automatique retiré : $name."
            }
        }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $app = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            $displayName = if ($null -ne $app.PSObject.Properties['DisplayName']) { [string]$app.DisplayName } else { '' }
            if ($displayName -notmatch '^(KernelOS Toolbox|KOS PostInstall|KOS Post Install)(\s|$)') { continue }
            $raw = if ($null -ne $app.PSObject.Properties['QuietUninstallString']) { [string]$app.QuietUninstallString } else { '' }
            if (-not $raw -and $null -ne $app.PSObject.Properties['UninstallString']) { $raw = [string]$app.UninstallString }
            $match = [regex]::Match($raw, '^(?:"(?<exe>[^"]+)"|(?<exe>\S+))(?:\s+(?<args>.*))?$')
            if (-not $match.Success) { Add-Warning "Commande de désinstallation illisible pour $displayName."; continue }
            $exe = [IO.Path]::GetFullPath($match.Groups['exe'].Value)
            $allowedRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') + '\' }
            if (-not ($allowedRoots | Where-Object { $exe.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) -or [IO.Path]::GetFileName($exe) -notmatch '^unins\d*\.exe$') {
                Add-Warning "Désinstalleur non fiable refusé : $exe"; continue
            }
            if (Test-Path -LiteralPath $exe -PathType Leaf) {
                $arguments = [string]$match.Groups['args'].Value
                if ($arguments -notmatch '(?i)/silent|/verysilent') { $arguments = ($arguments + ' /SILENT /NORESTART').Trim() }
                $process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -Wait
                if ($process.ExitCode -in @(0, 3010)) { Add-Removed "$displayName désinstallé." }
                else { Add-Warning "$displayName a retourné le code $($process.ExitCode)." }
            }
        }
    }

    $legacyGame = Join-Path $env:SystemRoot 'KRNLGame.exe'
    if (Test-Path -LiteralPath $legacyGame -PathType Leaf) {
        Remove-Item -LiteralPath $legacyGame -Force
        Add-Removed 'Ancien moteur C:\Windows\KRNLGame.exe supprimé.'
    }

    foreach ($startup in @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup\KernelOS11.bat'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\KernelOS11.bat')
    )) {
        if (Test-Path -LiteralPath $startup -PathType Leaf) { Remove-Item -LiteralPath $startup -Force; Add-Removed 'Ancien script KernelOS11.bat retiré du démarrage.' }
    }

    $legacyModules = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'KernelOS-Modules'))
    if ((Test-Path -LiteralPath $legacyModules -PathType Container) -and $legacyModules -eq ([IO.Path]::GetFullPath("$env:SystemDrive\KernelOS-Modules"))) {
        Remove-Item -LiteralPath $legacyModules -Recurse -Force
        Add-Removed 'Dossier résiduel KernelOS-Modules supprimé.'
    }

    Repair-SystemFile -Path (Join-Path $env:SystemRoot 'System32\utilman.exe') -WhenDifferentFromCmd
    Repair-SystemFile -Path (Join-Path $env:SystemRoot 'System32\smartscreen.exe')
    Repair-SystemFile -Path (Join-Path $env:SystemRoot 'HelpPane.exe')
    Repair-SystemFile -Path (Join-Path $env:SystemRoot 'System32\mobsync.exe')

    $payload = [ordered]@{ Success = $true; Removed = @($removed); Warnings = @($warnings); UpdatedUtc = [DateTime]::UtcNow.ToString('o') }
} catch {
    $payload = [ordered]@{ Success = $false; Removed = @($removed); Warnings = @($warnings); Error = $_.Exception.Message; UpdatedUtc = [DateTime]::UtcNow.ToString('o') }
}

if ($ResultPath) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($ResultPath))
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
[pscustomobject]$payload
if ($payload.Success) { exit 0 } else { exit 1 }
