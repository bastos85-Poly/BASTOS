param(
    [Parameter(Mandatory)][string]$ApplicationRoot,
    [string]$UpdatedScriptsRoot,
    [string[]]$AdditionalPaths=@(),
    [string[]]$ExcludedPaths=@(),
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\EngineIntegrity.json')
)
# Developer build tool only. Runtime never regenerates or accepts a new catalogue.
$ErrorActionPreference='Stop'
$app=[IO.Path]::GetFullPath($ApplicationRoot).TrimEnd('\')
$build=Get-Content -LiteralPath (Join-Path $app 'BASTOS-Build.json') -Raw -Encoding UTF8|ConvertFrom-Json
$manifestPath=Join-Path $app 'BASTOS-App-Manifest.json'
if((Get-FileHash -LiteralPath $manifestPath).Hash -ne $build.AppManifestSha256){throw 'Manifeste de base divergent.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$paths=@(@($manifest.Files.Path)+$AdditionalPaths|ForEach-Object {([string]$_).Replace('/', '\')}|Where-Object {$_ -match '\.(ps1|psm1|psd1|cmd|bat)$' -and $_ -ne 'Installer-BASTOS.ps1' -and $_ -notin $ExcludedPaths}|Sort-Object -Unique)
$files=@(foreach($relative in $paths){
    if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative.Split('\') -contains '..'){throw 'Chemin de catalogue refuse.'}
    $file=Join-Path $app $relative
    if($UpdatedScriptsRoot -and (Test-Path -LiteralPath (Join-Path $UpdatedScriptsRoot $relative) -PathType Leaf)){$file=Join-Path $UpdatedScriptsRoot $relative}
    for($cursor=[IO.Path]::GetFullPath($file);$cursor;$cursor=Split-Path -Parent $cursor){if((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Lien de fichier ou de dossier refuse.'}}
    [ordered]@{Path=$relative;Sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
})
if($files.Count -lt 1){throw 'Catalogue vide refuse.'}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),([ordered]@{Schema=1;Files=$files}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output ('Catalogue genere : '+$files.Count+' fichiers. Recompilez Bastos avant livraison.')
