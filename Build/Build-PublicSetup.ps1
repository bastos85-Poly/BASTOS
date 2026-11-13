param(
    [Parameter(Mandatory)][string]$CandidateRoot,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$version='7.120.136'
$source=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$candidate=(Resolve-Path -LiteralPath $CandidateRoot).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath (Join-Path $output 'BASTOS-Setup-7.120.136.exe')){throw 'Use a new output directory.'}
if($output.StartsWith($candidate.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside candidate.'}
New-Item -ItemType Directory -Path $output -Force|Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-Utf8([string]$path,[string]$text){[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($true))}
function Sha([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
function Zip-Files([string]$root,[string]$path,[switch]$Sources){
 $zip=[IO.Compression.ZipFile]::Open($path,'Create')
 try{foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force){
  $rel=$file.FullName.Substring($root.Length+1)
  if($Sources -and ($rel -match '(^|[\\/])(bin|obj|artifacts|\.git|\.vs)([\\/]|$)' -or $file.Extension -in '.exe','.dll','.pdb','.res','.log','.dmp','.lnk')){continue}
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$rel.Replace('\','/'),'Optimal')|Out-Null
 }}finally{$zip.Dispose()}
}
$native=Join-Path $candidate 'Bastos.Native/BASTOS-Native.exe'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler '/nologo' '/target:winexe' '/platform:x64' '/optimize+' '/debug-' ('/out:'+(Join-Path $candidate 'Bastos-Uninstall.exe')) ('/win32manifest:'+(Join-Path $PSScriptRoot 'Installer/app.manifest')) '/reference:System.Windows.Forms.dll' ('/resource:'+(Join-Path $PSScriptRoot 'Installer/Uninstall.ps1')+',Uninstall.ps1') (Join-Path $PSScriptRoot 'Installer/Uninstall.cs')
if($LASTEXITCODE){throw 'Uninstaller compilation failed.'}
if((Get-Item -LiteralPath $native).VersionInfo.FileVersion -ne ($version+'.0')){throw 'Unexpected native version.'}
foreach($file in Get-ChildItem -LiteralPath $candidate -Recurse -File){
 if($file.Extension -eq '.pdb'){throw 'Debug symbols must not be packaged.'}
 if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse points must not be packaged.'}
}
$sourceZip=Join-Path $output 'BASTOS-7.120.136-Sources.zip'
Zip-Files $source $sourceZip -Sources
Copy-Item -LiteralPath $sourceZip -Destination (Join-Path $candidate 'Bastos.Native/Source-Current.zip') -Force
Copy-Item -LiteralPath (Join-Path $source 'LICENSE.txt') -Destination (Join-Path $candidate 'LICENSE.txt') -Force
Write-Utf8 (Join-Path $candidate 'VERSION.txt') ($version+"`r`n")
$files=@(Get-ChildItem -LiteralPath $candidate -Recurse -File -Force|Where-Object {$_.Name -notin @('BASTOS-App-Manifest.json','BASTOS-Build.json','INSTALLER-MANIFEST.sha256')}|Sort-Object FullName)
$legacy=@($files|ForEach-Object {(Sha $_.FullName)+'  '+$_.FullName.Substring($candidate.Length+1).Replace('\','/')})
Write-Utf8 (Join-Path $candidate 'INSTALLER-MANIFEST.sha256') (($legacy -join "`r`n")+"`r`n")
$files=@(Get-ChildItem -LiteralPath $candidate -Recurse -File -Force|Where-Object {$_.Name -notin @('BASTOS-App-Manifest.json','BASTOS-Build.json')}|Sort-Object FullName)
$manifest=[ordered]@{BastosVersion=$version;CreatedUtc=[DateTime]::UtcNow.ToString('o');FileCount=$files.Count;Files=@($files|ForEach-Object {[ordered]@{Path=$_.FullName.Substring($candidate.Length+1).Replace('\','/');Sha256=Sha $_.FullName}})}
Write-Utf8 (Join-Path $candidate 'BASTOS-App-Manifest.json') ($manifest|ConvertTo-Json -Depth 8)
$build=Get-Content (Join-Path $candidate 'BASTOS-Build.json') -Raw|ConvertFrom-Json
$build.BastosVersion=$version;$build.BuildId=$version+'-public-candidate';$build.BuiltUtc=[DateTime]::UtcNow.ToString('o')
$build.AppManifestSha256=Sha (Join-Path $candidate 'BASTOS-App-Manifest.json');$build.AppFileCount=$files.Count;$build.NativeAppSha256=Sha $native
$build.PackagingRevision=$version+'-public-candidate';$build.ValidationScope='Candidate construction only. The complete release gate is recorded separately in ReleaseStatus.json.'
Write-Utf8 (Join-Path $candidate 'BASTOS-Build.json') ($build|ConvertTo-Json -Depth 8)
$payload=Join-Path $output ('BASTOS-'+$version+'-Payload.zip')
Zip-Files $candidate $payload
$hashes=@{PAYLOAD=Sha $payload;MANIFEST=Sha (Join-Path $candidate 'BASTOS-App-Manifest.json');NATIVE=Sha $native;BUILD=Sha (Join-Path $candidate 'BASTOS-Build.json')}
$script=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PublicInstaller.ps1')).Replace('__FILE_COUNT__',[string]$files.Count)
foreach($key in $hashes.Keys){$script=$script.Replace(('__'+$key+'_HASH__'),$hashes[$key])}
$installer=Join-Path $output 'Installer.ps1';Write-Utf8 $installer $script
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Installer/Bootstrapper.cs')).Replace('__PAYLOAD_HASH__',$hashes.PAYLOAD).Replace('__SCRIPT_HASH__',(Sha $installer))
$temp=Join-Path $output 'compiler';New-Item -ItemType Directory -Path $temp|Out-Null
$cs=Join-Path $temp 'Bootstrapper.cs';Write-Utf8 $cs $code
$setup=Join-Path $output ('BASTOS-Setup-'+$version+'.exe')
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler '/nologo' '/target:winexe' '/platform:x64' '/optimize+' '/debug-' ('/out:'+$setup) ('/win32manifest:'+(Join-Path $PSScriptRoot 'Installer/app.manifest')) ('/win32icon:'+(Join-Path $source 'app.ico')) '/reference:System.Windows.Forms.dll' '/reference:System.Drawing.dll' ('/resource:'+$payload+',Payload.zip') ('/resource:'+$installer+',Installer.ps1') ('/resource:'+(Join-Path $source 'LICENSE.txt')+',LICENSE.txt') $cs
if($LASTEXITCODE){throw 'Setup compilation failed.'}
Copy-Item (Join-Path $source 'LICENSE.txt') (Join-Path $output 'LICENSE.txt')
$status=[ordered]@{Version=$version;Status='LOCAL-CANDIDATE-DO-NOT-PUBLISH';FullReleaseGatePassed=$false;NativeSha256=$hashes.NATIVE;ManifestSha256=$hashes.MANIFEST;BuildSha256=$hashes.BUILD;PayloadSha256=$hashes.PAYLOAD;SourceSha256=Sha $sourceZip;SetupSha256=Sha $setup;ManifestFiles=$files.Count;PayloadFiles=$files.Count+2;SetupSigned=$false}
Write-Utf8 (Join-Path $output 'ReleaseStatus.json') ($status|ConvertTo-Json -Depth 5)
Write-Utf8 (Join-Path $output 'SHA256SUMS.txt') (((Get-ChildItem -LiteralPath $output -File|Where-Object Name -ne 'SHA256SUMS.txt'|ForEach-Object {(Sha $_.FullName)+'  '+$_.Name}) -join "`r`n")+"`r`n")
$status|ConvertTo-Json
