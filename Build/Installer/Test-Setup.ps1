param([Parameter(Mandatory)][string]$KitRoot,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$kit=(Resolve-Path -LiteralPath $KitRoot).Path
$root=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $root){throw 'Choose a new fixture directory.'}
New-Item -ItemType Directory -Path $root|Out-Null
$script:checks=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:checks++;Write-Output ('OK: '+$message)}
$setup=Join-Path $kit 'BASTOS-Setup-7.120.136.exe'
function Run-Setup([string]$destination,[switch]$Verify){
 $setupArguments=@('--test-root',('"'+$destination+'"'));if($Verify){$setupArguments+='--verify-only'}
 $p=Start-Process -FilePath $setup -ArgumentList $setupArguments -WindowStyle Hidden -PassThru
 try{if(-not $p.WaitForExit(120000)){$p.Kill();throw 'Setup test timed out.'};return $p.ExitCode}finally{$p.Dispose()}
}
$verify=Join-Path $root 'verify-only'
Check ((Run-Setup $verify -Verify) -eq 0) 'Self-contained executable verifies its embedded payload'
Check (-not(Test-Path (Join-Path $verify 'BASTOS'))) 'Verify-only does not install BASTOS'
$fresh=Join-Path $root 'fresh install with spaces'
Check ((Run-Setup $fresh) -eq 0) 'Single EXE installs to isolated directory containing spaces'
$exe=Join-Path $fresh 'BASTOS/Bastos.Native/BASTOS-Native.exe'
$meta=Get-Content (Join-Path $kit 'ReleaseStatus.json') -Raw|ConvertFrom-Json
Check ((Get-FileHash $exe).Hash -eq $meta.NativeSha256) 'Installed executable matches compiled candidate'
Check ((Get-Item $exe).VersionInfo.FileVersion -eq '7.120.136.0') 'Installed version is 7.120.136'
$manifest=Get-Content (Join-Path $fresh 'BASTOS/BASTOS-App-Manifest.json') -Raw|ConvertFrom-Json
$wrong=@($manifest.Files|Where-Object {(Get-FileHash -LiteralPath (Join-Path "$fresh/BASTOS" $_.Path)).Hash -ne $_.Sha256})
Check ($wrong.Count -eq 0) 'Every installed manifest entry matches SHA-256'
$lines=@(Get-Content (Join-Path $fresh 'BASTOS/INSTALLER-MANIFEST.sha256'))
Check (@($lines|Where-Object {$_ -notmatch '^[A-Fa-f0-9]{64}\s+.+$'}).Count -eq 0) 'Legacy manifest uses actual whitespace separators'
Check ($lines.Count -eq ($manifest.Files.Count-1)) 'Legacy manifest includes all non-metadata runtime files'
$old=Join-Path $fresh 'BASTOS/local-sentinel.txt';[IO.File]::WriteAllText($old,'preserve fixture')
Check ((Run-Setup $fresh) -eq 0) 'Updating an existing isolated installation succeeds'
$backup=@(Get-ChildItem -LiteralPath $fresh -Directory -Filter 'BASTOS-before-*')
Check ($backup.Count -eq 1 -and (Get-Content (Join-Path $backup[0].FullName 'local-sentinel.txt') -Raw) -eq 'preserve fixture') 'Previous installation and local fixture remain in backup'
$bad=Join-Path $root 'damaged-kit';New-Item -ItemType Directory $bad|Out-Null
Copy-Item (Join-Path $kit 'Installer.ps1') "$bad/Installer.ps1"
[IO.File]::WriteAllText((Join-Path $bad 'BASTOS-7.120.136-Payload.zip'),'corrupted fixture')
$ps=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$badTarget=Join-Path $root 'damaged-target'
& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$bad/Installer.ps1" -TestRoot $badTarget *> (Join-Path $root 'damaged.log')
Check ($LASTEXITCODE -ne 0 -and -not(Test-Path "$badTarget/BASTOS")) 'Damaged download is rejected before installation'
$actual=Join-Path $root 'junction-real';$link=Join-Path $root 'junction-link'
New-Item -ItemType Directory $actual|Out-Null
New-Item -ItemType Junction -Path $link -Target $actual|Out-Null
Check ((Run-Setup $link) -ne 0) 'Redirected installation directory is rejected'
Check (-not(Test-Path "$actual/BASTOS")) 'Rejected redirect leaves destination untouched'
$sourceZip=Join-Path $kit 'BASTOS-7.120.136-Sources.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($sourceZip)
try{Check (@($archive.Entries|Where-Object {$_.FullName -match '(^|/)(bin|obj|artifacts|\.git)/|\.(exe|dll|pdb|log|lnk)$'}).Count -eq 0) 'Distributed sources exclude compiled products and private runtime evidence'}finally{$archive.Dispose()}
$uninstaller=Join-Path $fresh 'BASTOS/Bastos-Uninstall.exe'
$process=Start-Process -FilePath $uninstaller -ArgumentList @('/silent','--test-root',('"'+$fresh+'"')) -WindowStyle Hidden -PassThru
$process.WaitForExit()
Check ($process.ExitCode -eq 0) 'Uninstaller launches only from its isolated installation'
$deadline=[datetime]::UtcNow.AddSeconds(30)
while((Test-Path (Join-Path $fresh 'BASTOS')) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 250}
Check (-not(Test-Path (Join-Path $fresh 'BASTOS'))) 'Uninstaller removes only the installed runtime directory'
Check ((Get-Content (Join-Path $backup[0].FullName 'local-sentinel.txt') -Raw) -eq 'preserve fixture') 'Uninstaller preserves the previous-version backup'
Write-Output ('PASS: '+$script:checks+' installer checks; no desktop shortcut or system optimization executed.')
exit 0
