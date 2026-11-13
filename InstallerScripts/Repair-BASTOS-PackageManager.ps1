[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResultPath,
    [switch]$AllowChocolatey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-BastosAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-BastosExecutable {
    param([Parameter(Mandatory)][string]$Name,[string[]]$Candidates=@())
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [string]$command.Source
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Find-BastosWinget {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\AppInstallerCLI.exe')
    )
    $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path -LiteralPath $windowsApps -PathType Container) {
        $desktopInstaller = Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($desktopInstaller) {
            $candidates += Join-Path $desktopInstaller.FullName 'winget.exe'
            $candidates += Join-Path $desktopInstaller.FullName 'AppInstallerCLI.exe'
        }
    }
    return Find-BastosExecutable -Name 'winget.exe' -Candidates $candidates
}

function Find-BastosChocolatey {
    $candidates=@((Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'))
    if($env:ChocolateyInstall){$candidates+=Join-Path $env:ChocolateyInstall 'bin\choco.exe'}
    return Find-BastosExecutable -Name 'choco.exe' -Candidates $candidates
}

function Install-BastosWinget {
    # First re-register App Installer when its package already exists but its alias is missing.
    try {
        $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($appInstaller -and $appInstaller.InstallLocation) {
            $manifest = Join-Path $appInstaller.InstallLocation 'AppxManifest.xml'
            if (Test-Path -LiteralPath $manifest -PathType Leaf) {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
            }
        }
    } catch {}
    $winget = Find-BastosWinget
    if ($winget) { return $winget }

    # Microsoft documents this module and cmdlet as the supported bootstrap/repair path.
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -AllowClobber | Out-Null
    Import-Module Microsoft.WinGet.Client -Force
    if (Test-BastosAdministrator) {
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    } else {
        Repair-WinGetPackageManager -Force -Latest | Out-Null
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    $winget = Find-BastosWinget
    if (-not $winget) { throw 'La réparation Microsoft s est terminée, mais winget.exe reste introuvable.' }
    & $winget source reset --force --disable-interactivity | Out-Null
    & $winget source update --disable-interactivity | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "WinGet est installé, mais ses sources ne répondent pas (code $LASTEXITCODE)." }
    return $winget
}

function Install-BastosChocolatey {
    if (-not (Test-BastosAdministrator)) { throw 'Chocolatey doit être installé avec les droits administrateur.' }
    $uri = [Uri]'https://community.chocolatey.org/install.ps1'
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'community.chocolatey.org') { throw 'Adresse Chocolatey non autorisée.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tempScript = Join-Path ([IO.Path]::GetTempPath()) ('BASTOS-Chocolatey-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -OutFile $tempScript
        $download = Get-Item -LiteralPath $tempScript -ErrorAction Stop
        if ($download.Length -lt 1000 -or $download.Length -gt 2MB) { throw 'Le script officiel Chocolatey téléchargé a une taille anormale.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript
        if ($LASTEXITCODE -ne 0) { throw "L installateur Chocolatey a retourné le code $LASTEXITCODE." }
    } finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    $choco = Find-BastosChocolatey
    if (-not $choco) { throw 'Chocolatey semble installé, mais choco.exe reste introuvable.' }
    return $choco
}

$result = [ordered]@{Success=$false;Manager='';Path='';WingetError='';ChocolateyError='';UpdatedUtc=[datetime]::UtcNow.ToString('o')}
try {
    $winget = Find-BastosWinget
    if (-not $winget) {
        try { $winget = Install-BastosWinget }
        catch { $result.WingetError = $_.Exception.Message }
    }
    if ($winget) {
        $result.Success = $true
        $result.Manager = 'winget'
        $result.Path = $winget
    } elseif ($AllowChocolatey) {
        $choco = Find-BastosChocolatey
        if (-not $choco) {
            try { $choco = Install-BastosChocolatey }
            catch { $result.ChocolateyError = $_.Exception.Message }
        }
        if ($choco) {
            $result.Success = $true
            $result.Manager = 'chocolatey'
            $result.Path = $choco
        }
    }
    if (-not $result.Success -and -not $result.WingetError) { $result.WingetError = 'WinGet est indisponible.' }
} catch {
    if (-not $result.WingetError) { $result.WingetError = $_.Exception.Message }
} finally {
    $result.UpdatedUtc = [datetime]::UtcNow.ToString('o')
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($ResultPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
}
if ($result.Success) { exit 0 } else { exit 1 }
