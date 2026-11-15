param([Parameter(Mandatory)][string]$Toolchain)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$catalog = Get-Content (Join-Path $root '../Assets/Interface.en.json') -Raw | ConvertFrom-Json -AsHashtable
$gameCatalog = Get-Content (Join-Path $root 'Interface.en.json') -Raw | ConvertFrom-Json -AsHashtable
foreach($key in $gameCatalog.Keys){$catalog[$key]=$gameCatalog[$key]}
$literal = $catalog | ConvertTo-Json -Depth 4 -Compress
if($literal.Contains(')BASTOS"')){throw 'Invalid catalog literal delimiter'}
[IO.File]::WriteAllText((Join-Path $root 'language-catalog.hpp'),('inline constexpr const char* gameLanguageCatalog=R"BASTOS('+$literal+')BASTOS";'),[Text.UTF8Encoding]::new($false))
& (Join-Path $Toolchain 'bin\llvm-windres.exe') (Join-Path $root 'app.rc') '-O' 'coff' '-o' (Join-Path $root 'app.res')
if($LASTEXITCODE){throw 'Resource compilation failed'}
& (Join-Path $Toolchain 'bin\x86_64-w64-mingw32-clang++.exe') ('-ffile-prefix-map='+$root+'=/_/BASTOS-Game') '-std=c++20' '-O2' '-static' '-municode' '-mwindows' '-D_WIN32_WINNT=0x0A00' (Join-Path $root 'main.cpp') (Join-Path $root 'app.res') '-o' (Join-Path $root 'BASTOS-Game.exe') '-ladvapi32' '-luser32' '-lshell32' '-lcomdlg32' '-lcomctl32' '-lgdi32' '-luxtheme' '-ldwmapi' '-ld3d11'
if($LASTEXITCODE){throw 'Compilation failed'}
Get-FileHash -LiteralPath (Join-Path $root 'BASTOS-Game.exe')
