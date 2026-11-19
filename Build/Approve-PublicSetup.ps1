param(
 [Parameter(Mandatory)][string]$CandidateRoot,
 [Parameter(Mandatory)][string]$KitRoot,
 [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Assert-ReleaseValidation.ps1') -CandidateRoot $CandidateRoot -ReportPath $ReportPath
$kit=(Resolve-Path -LiteralPath $KitRoot).Path
$path=Join-Path $kit 'ReleaseStatus.json';$status=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
$candidateFiles=@{'Bastos.Native/BASTOS-Native.exe'=$status.NativeSha256;'BASTOS-App-Manifest.json'=$status.ManifestSha256;'BASTOS-Build.json'=$status.BuildSha256;'Bastos.Native/Source-Current.zip'=$status.SourceSha256}
foreach($name in $candidateFiles.Keys){if((Get-FileHash -LiteralPath (Join-Path $CandidateRoot $name)).Hash -ne $candidateFiles[$name]){throw 'Candidate differs from the packaged setup.'}}
$kitFiles=@{'BASTOS-Setup-7.120.139.exe'=$status.SetupSha256;'BASTOS-7.120.139-Payload.zip'=$status.PayloadSha256;'BASTOS-7.120.139-Sources.zip'=$status.SourceSha256}
foreach($name in $kitFiles.Keys){if((Get-FileHash -LiteralPath (Join-Path $kit $name)).Hash -ne $kitFiles[$name]){throw 'Packaged file changed after construction.'}}
$status.FullReleaseGatePassed=$true;$status.Status='Validated'
[IO.File]::WriteAllText($path,($status|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($true))
$sums=@(Get-ChildItem -LiteralPath $kit -File|Where-Object Name -ne 'SHA256SUMS.txt'|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash+'  '+$_.Name})
[IO.File]::WriteAllText((Join-Path $kit 'SHA256SUMS.txt'),(($sums -join "`r`n")+"`r`n"),[Text.UTF8Encoding]::new($true))
Write-Output 'Full release validation matched the unchanged candidate and setup.'
