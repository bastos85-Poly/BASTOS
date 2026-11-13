param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$path=Join-Path $SourceRoot 'InstallerScripts\New-BASTOS-DesktopShortcut.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
$helper=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-BastosDesktopShortcut'},$true)
Invoke-Expression $helper.Extent.Text
$fixture=Join-Path $env:TEMP ('Bastos-StartShortcut-'+[guid]::NewGuid().ToString('N'))
try{
    $app=Join-Path $fixture 'Application'
    New-Item -ItemType Directory (Join-Path $app 'Bastos.Native') -Force|Out-Null
    $exe=Join-Path $app 'Bastos.Native\BASTOS-Native.exe'
    [IO.File]::WriteAllText($exe,'shortcut fixture')
    @{NativeAppSha256=(Get-FileHash $exe).Hash}|ConvertTo-Json|Set-Content (Join-Path $app 'BASTOS-Build.json')
    $link=New-BastosDesktopShortcut -ApplicationRoot $app -DesktopPath (Join-Path $fixture 'CommonPrograms')
    $shell=New-Object -ComObject WScript.Shell
    $actual=$shell.CreateShortcut($link)
    if($actual.TargetPath -ne $exe -or $actual.IconLocation -ne ($exe+',0')){throw 'Shortcut target or icon mismatch'}
    [IO.File]::AppendAllText($exe,'tampered')
    $refused=$false
    try{New-BastosDesktopShortcut -ApplicationRoot $app -DesktopPath (Join-Path $fixture 'Rejected')|Out-Null}catch{$refused=$true}
    if(-not $refused -or (Test-Path (Join-Path $fixture 'Rejected\BASTOS.lnk'))){throw 'Altered executable must not get a shortcut'}
    Remove-Item -LiteralPath $exe
    $refused=$false
    try{New-BastosDesktopShortcut -ApplicationRoot $app -DesktopPath (Join-Path $fixture 'Missing')|Out-Null}catch{$refused=$true}
    if(-not $refused){throw 'Missing executable must fail'}
    'PASS: real shortcut target and embedded icon; altered and missing executable refused. TEMP only.'
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture outside TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
