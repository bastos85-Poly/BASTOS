[CmdletBinding()]
param([string]$ResultPath = 'C:\ProgramData\BASTOS-ISO\FirstDesktop-Essentials.json')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$wingetItems = @(
    [ordered]@{ Name = '7-Zip'; Id = '7zip.7zip'; Source = 'winget' },
    [ordered]@{ Name = 'DirectX Runtime Offline'; Id = 'Microsoft.DirectX'; Source = 'winget' },
    [ordered]@{ Name = 'Visual C++ Runtime All-in-One'; Id = 'abbodi1406.vcredist'; Source = 'winget' },
    [ordered]@{ Name = 'Microsoft .NET Windows Desktop Runtime 8 x64'; Id = 'Microsoft.DotNet.DesktopRuntime.8'; Source = 'winget' },
    [ordered]@{ Name = 'Microsoft .NET Windows Desktop Runtime 10 x64'; Id = 'Microsoft.DotNet.DesktopRuntime.10'; Source = 'winget' }
)
$workRoot = Join-Path $env:ProgramData 'BASTOS-ISO\FirstDesktop'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$selectionPath = Join-Path $workRoot 'Essentials.json'
$progressPath = Join-Path $workRoot 'Essentials.progress'
$wingetResultPath = Join-Path $workRoot 'Essentials-WinGet.json'
[IO.File]::WriteAllText($selectionPath, ($wingetItems | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))

$steps = [Collections.Generic.List[object]]::new()
$wingetSuccess = $false
try {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'WinGet indisponible : les composants restent installables depuis Logiciels dans BASTOS.' }
    $installer = Join-Path $PSScriptRoot 'Install-BASTOS-SoftwareSelection.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Module Logiciels BASTOS absent.' }
    & $installer -SelectionPath $selectionPath -ProgressPath $progressPath -ResultPath $wingetResultPath -Manager winget
    if (-not (Test-Path -LiteralPath $wingetResultPath -PathType Leaf)) { throw 'Résultat WinGet des composants essentiels absent.' }
    $wingetResult = Get-Content -LiteralPath $wingetResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $wingetSuccess = [bool]$wingetResult.Success
    foreach ($item in @($wingetResult.Items)) { $steps.Add($item) }
    if (-not $wingetSuccess) { throw 'Une ou plusieurs installations WinGet essentielles ont échoué.' }
} catch {
    $steps.Add([pscustomobject]@{ Name='Composants essentiels WinGet'; Id='winget'; Success=$false; Status='Failed'; Detail=$_.Exception.Message })
}

$netFx3Success = $false
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
    if ([string]$feature.State -ne 'Enabled') {
        [IO.File]::WriteAllText($progressPath, "95`tActivation Windows`t.NET Framework 3.5 (NetFx3)", [Text.UTF8Encoding]::new($false))
        $dism = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\dism.exe') -ArgumentList @(
            '/Online','/Enable-Feature','/FeatureName:NetFx3','/All','/NoRestart','/Quiet'
        ) -PassThru -Wait -WindowStyle Hidden
        if ($dism.ExitCode -notin @(0,3010)) { throw "DISM a retourné le code $($dism.ExitCode)." }
        $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
    }
    $netFx3Success = [string]$feature.State -eq 'Enabled'
    if (-not $netFx3Success) { throw "Windows indique l’état $($feature.State) pour NetFx3." }
    $steps.Add([pscustomobject]@{ Name='.NET Framework 3.5 (inclut .NET 2.0 et 3.0)'; Id='WindowsFeature.NetFx3'; Success=$true; Status='Enabled'; Detail='Fonctionnalité Windows activée silencieusement.' })
} catch {
    $steps.Add([pscustomobject]@{ Name='.NET Framework 3.5 (inclut .NET 2.0 et 3.0)'; Id='WindowsFeature.NetFx3'; Success=$false; Status='Failed'; Detail=$_.Exception.Message })
}

$success = $wingetSuccess -and $netFx3Success
[IO.File]::WriteAllText($progressPath, ("100`tComposants essentiels terminés`t{0}" -f $(if($success){'Toutes les installations sont vérifiées.'}else{'Une installation facultative devra être relancée depuis Bastos.'})), [Text.UTF8Encoding]::new($false))
$payload = [ordered]@{
    Success = $success
    Optional = $true
    WingetSuccess = $wingetSuccess
    NetFx3Success = $netFx3Success
    Items = @($steps)
    UpdatedUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))
if ($success) { exit 0 } else { exit 1 }
