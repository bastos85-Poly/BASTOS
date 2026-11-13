param(
    [Parameter(Mandatory)][string]$Toolchain,
    [Parameter(Mandatory)][string]$TestRoot
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($TestRoot)
if (Test-Path -LiteralPath $root) { throw 'Choisir un nouveau dossier de test.' }
New-Item -ItemType Directory -Path $root | Out-Null
$compiler = Join-Path $Toolchain 'bin/x86_64-w64-mingw32-clang++.exe'
$executable = Join-Path $root 'DiscoveryTests.exe'
& $compiler '-std=c++20' '-O2' '-static' '-municode' ('-ffile-prefix-map='+$PSScriptRoot+'=/_/BASTOS-Game') '-D_WIN32_WINNT=0x0A00' (Join-Path $PSScriptRoot 'DiscoveryTests.cpp') '-o' $executable '-ladvapi32' '-luser32' '-lshell32' '-lcomdlg32' '-lcomctl32' '-lgdi32'
if ($LASTEXITCODE) { throw 'Compilation du test échouée.' }
& $executable (Join-Path $root 'fixtures')
if ($LASTEXITCODE) { throw 'Tests de détection échoués.' }
