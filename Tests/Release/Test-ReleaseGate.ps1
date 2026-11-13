param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$source=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$guard=Join-Path $source 'Build/Assert-ReleaseValidation.ps1'
$root=Join-Path $OutputDirectory ('Gate-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory (Join-Path $root 'Bastos.Native') -Force|Out-Null
foreach($file in @('Bastos.Native/BASTOS-Native.exe','BASTOS-App-Manifest.json','Bastos.Native/Source-Current.zip')){[IO.File]::WriteAllText((Join-Path $root $file),'fixture')}
$required=@('ReleaseGate','VmGuards','engine','cancellation','resume','journal','integrity','guidance','postinstall','diagnostic-export','log-maintenance','WpfScenarios','VmReinstallation')
$base=@{Schema=1;Passed=$true;CompletedUtc=[DateTime]::UtcNow.ToString('o');Error=$null;CandidateSha256=(Get-FileHash (Join-Path $root 'Bastos.Native/BASTOS-Native.exe')).Hash;ManifestSha256=(Get-FileHash (Join-Path $root 'BASTOS-App-Manifest.json')).Hash;SourceZipSha256=(Get-FileHash (Join-Path $root 'Bastos.Native/Source-Current.zip')).Hash;Stages=@($required|ForEach-Object {@{Name=$_;Passed=$true}})}
$report=Join-Path $root 'report.json';$count=0
function Check-Report($value,[bool]$expected){$value|ConvertTo-Json -Depth 8|Set-Content $report -Encoding UTF8;$ok=$true;try{& $guard -CandidateRoot $root -ReportPath $report}catch{$ok=$false};if($ok -ne $expected){throw 'Garde de livraison incorrect.'};$script:count++}
Check-Report $base $true
foreach($name in $required){$clone=$base|ConvertTo-Json -Depth 8|ConvertFrom-Json;$clone.Stages=@($clone.Stages|Where-Object Name -ne $name);Check-Report $clone $false}
foreach($change in @('failed','old','binary','source','manifest','boolean')){
 $clone=$base|ConvertTo-Json -Depth 8|ConvertFrom-Json
 switch($change){failed{$clone.Passed=$false}old{$clone.CompletedUtc=[DateTime]::UtcNow.AddDays(-2).ToString('o')}binary{$clone.CandidateSha256='00'}source{$clone.SourceZipSha256='00'}manifest{$clone.ManifestSha256='00'}boolean{$clone.Passed='true'}}
 Check-Report $clone $false
}
"PASS : $count controles du garde de livraison (dont absence individuelle des 13 suites)."
