param([string]$DotNetPath = 'dotnet')
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
& $DotNetPath build (Join-Path $sourceRoot 'BASTOS-Native.csproj') -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Compilation échouée.' }
& $DotNetPath run --project (Join-Path $sourceRoot 'Tests/Release/guidance/guidance-tests.csproj') -c Release "-p:BastosSourceRoot=$sourceRoot"
if ($LASTEXITCODE -ne 0) { throw 'Tests de présentation échoués.' }
& $DotNetPath run --project (Join-Path $sourceRoot 'Tests/CardSwitch/CardSwitch.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Tests des interrupteurs échoués.' }
& $DotNetPath run --project (Join-Path $sourceRoot 'Tests/SwitchUi/SwitchUi.csproj') -c Release -- (Join-Path $sourceRoot 'artifacts/SwitchUi') --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Tests WPF des interrupteurs échoués.' }
Write-Output 'Compilation et tests de présentation réussis. Validation de livraison complète non exécutée.'
