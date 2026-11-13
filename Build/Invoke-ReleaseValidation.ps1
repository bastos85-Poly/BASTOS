param([Parameter(Mandatory)][string]$CandidateRoot,[Parameter(Mandatory)][string]$RuntimeRoot,[Parameter(Mandatory)][string]$DotNetPath,[Parameter(Mandatory)][string]$VmPlanPath,[Parameter(Mandatory)][string]$OutputDirectory,[switch]$HostOnly)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path (Join-Path $OutputDirectory 'ReleaseValidation.json')){throw 'Utiliser un nouveau dossier de resultats pour chaque validation.'}
New-Item -ItemType Directory $OutputDirectory -Force|Out-Null
function Source-Fingerprint {
 $text=@(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {$_.FullName.Substring($source.Length+1) -notmatch '(^|\\)(bin|obj)\\'} | Sort-Object FullName | ForEach-Object {$_.FullName.Substring($source.Length+1)+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n"
 [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
}
$sourceFingerprint=Source-Fingerprint
$report=[ordered]@{Schema=1;Passed=$false;StartedUtc=[DateTime]::UtcNow.ToString('o');CompletedUtc=$null;CandidateSha256=(Get-FileHash (Join-Path $CandidateRoot 'Bastos.Native/BASTOS-Native.exe')).Hash;ManifestSha256=(Get-FileHash (Join-Path $CandidateRoot 'BASTOS-App-Manifest.json')).Hash;SourceZipSha256=(Get-FileHash (Join-Path $CandidateRoot 'Bastos.Native/Source-Current.zip')).Hash;Stages=@();Error=$null}
function Save-Report { $p=Join-Path $OutputDirectory 'ReleaseValidation.json';$t=$p+'.tmp';[IO.File]::WriteAllText($t,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $t -Destination $p -Force }
function Run-Stage([string]$name,[scriptblock]$action){
 Write-Output ('Validation : '+$name)
 $clock=[Diagnostics.Stopwatch]::StartNew()
 try{& $action;$report.Stages+=@{Name=$name;Passed=$true;DurationMs=$clock.ElapsedMilliseconds}}catch{$report.Stages+=@{Name=$name;Passed=$false;DurationMs=$clock.ElapsedMilliseconds};throw}finally{Save-Report}
}
function Run-Process([string]$file,[string[]]$arguments,[string]$log,[int]$seconds=180){
 $start=[Diagnostics.ProcessStartInfo]::new($file);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 foreach($arg in $arguments){$start.ArgumentList.Add($arg)}
 $p=[Diagnostics.Process]::Start($start);$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 try{if(-not $p.WaitForExit($seconds*1000)){$p.Kill($true);throw ('Delai depasse : '+$log)}
 [IO.File]::WriteAllText($log,$out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult())
 if($p.ExitCode -ne 0){throw ('Echec code '+$p.ExitCode+' : '+$log)}}finally{$p.Dispose()}
}
$oldData=$env:BASTOS_TEST_DATA;$oldDotNetRoot=$env:DOTNET_ROOT;$env:DOTNET_ROOT=Split-Path -Parent $DotNetPath
$oldTemp=$env:TEMP;$oldTmp=$env:TMP;$oldSource=$env:BASTOS_TEST_SOURCE;$oldRuntime=$env:BASTOS_TEST_RUNTIME
try {
 $env:BASTOS_TEST_SOURCE=$source;$env:BASTOS_TEST_RUNTIME=$RuntimeRoot
 $env:TEMP=Join-Path $OutputDirectory 'Temp';$env:TMP=$env:TEMP;New-Item -ItemType Directory $env:TEMP -Force|Out-Null
 Save-Report
 Run-Stage 'ReleaseGate' { & (Join-Path $source 'Tests/Release/Test-ReleaseGate.ps1') -OutputDirectory $OutputDirectory | Set-Content (Join-Path $OutputDirectory 'release-gate-tests.log') }
 Run-Stage 'VmGuards' { & (Join-Path $source 'Tests/VmLab/Test-VmLabGuards.ps1') | Set-Content (Join-Path $OutputDirectory 'vm-guards-tests.log') }
 foreach($suite in @('engine','cancellation','resume','journal','integrity','guidance','postinstall','diagnostic-export','log-maintenance')){
  $name=$suite
  Run-Stage $name {
   $project=@(Get-ChildItem (Join-Path $source ('Tests/Release/'+$name)) -Filter '*.csproj');if($project.Count -ne 1){throw 'Projet de test ambigu.'}
   $publish=Join-Path $OutputDirectory ('suites/'+$name)
   Run-Process $DotNetPath @('publish',$project[0].FullName,'-c','Release','--self-contained','false',"-p:BastosSourceRoot=$source",'-o',$publish) (Join-Path $OutputDirectory ($name+'-build.log'))
   $exe=Join-Path $publish ($project[0].BaseName+'.exe')
   $args=@();if($name -eq 'engine'){$args=@((Join-Path $OutputDirectory 'engine-fixtures'))}
   Run-Process $exe $args (Join-Path $OutputDirectory ($name+'-tests.log'))
  }
 }
 Run-Stage 'WpfScenarios' {
  $app=Join-Path $OutputDirectory 'Application';New-Item -ItemType Directory (Join-Path $app 'Bastos.Native') -Force|Out-Null
  $catalog=Get-Content (Join-Path $source 'Assets/EngineIntegrity.json') -Raw|ConvertFrom-Json
  foreach($entry in $catalog.Files){$from=Join-Path $CandidateRoot $entry.Path;if(-not(Test-Path $from)){$from=Join-Path $RuntimeRoot $entry.Path};$to=Join-Path $app $entry.Path;New-Item -ItemType Directory (Split-Path -Parent $to) -Force|Out-Null;Copy-Item -LiteralPath $from -Destination $to -Force}
  Get-ChildItem -LiteralPath $RuntimeRoot -File | Where-Object Extension -in '.json','.txt' | Copy-Item -Destination $app -Force
  $env:BASTOS_TEST_DATA=Join-Path $env:TEMP 'Bastos-TestData'
  Copy-Item -LiteralPath (Join-Path $RuntimeRoot 'Assets') -Destination (Join-Path $app 'Assets') -Recurse -Force
  $exe=Join-Path $app 'Bastos.Native/BASTOS-Native.exe';Copy-Item (Join-Path $CandidateRoot 'Bastos.Native/BASTOS-Native.exe') $exe -Force
  Run-Process $exe @('--smoke-test','--cancellation-smoke-test','--resume-smoke-test','--guidance-smoke-test','--preflight-smoke-test','--postinstall-smoke-test','--diagnostic-export-smoke-test','--integrity-smoke-test','--log-maintenance-smoke-test','--responsiveness-smoke-test') (Join-Path $OutputDirectory 'wpf-tests.log') 240
  foreach($result in @('BASTOS-Native-SmokeTest.txt','BASTOS-Availability-SmokeTest.txt','BASTOS-Cancellation-SmokeTest.txt','BASTOS-Resume-SmokeTest.txt','BASTOS-Integrity-SmokeTest.txt','BASTOS-Maintenance-SmokeTest.txt','BASTOS-Responsiveness-SmokeTest.txt')){if(-not(Test-Path (Join-Path $env:TEMP $result))){throw ('Preuve WPF absente : '+$result)}}
 }
 if($HostOnly){return}
 Run-Stage 'VmReinstallation' {
  $powershell5=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  Run-Process $powershell5 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Invoke-ReleaseVm.ps1'),'-SourceRoot',$source,'-CandidateRoot',$CandidateRoot,'-RuntimeRoot',$RuntimeRoot,'-DotNetPath',$DotNetPath,'-PlanPath',$VmPlanPath,'-OutputDirectory',$OutputDirectory) (Join-Path $OutputDirectory 'vm-console.log') 3300
 }
 if((Source-Fingerprint) -ne $sourceFingerprint){throw 'Sources modifiees pendant les tests : nouvelle validation requise.'}
 foreach($file in @(@{Path='Bastos.Native/BASTOS-Native.exe';Hash=$report.CandidateSha256},@{Path='BASTOS-App-Manifest.json';Hash=$report.ManifestSha256},@{Path='Bastos.Native/Source-Current.zip';Hash=$report.SourceZipSha256})){if((Get-FileHash (Join-Path $CandidateRoot $file.Path)).Hash -ne $file.Hash){throw 'Candidat modifie pendant les tests.'}}
 $report.Passed=$true
} catch { $report.Error=$_.Exception.Message;throw } finally {
 $report.CompletedUtc=[DateTime]::UtcNow.ToString('o');Save-Report
 $env:BASTOS_TEST_DATA=$oldData;$env:DOTNET_ROOT=$oldDotNetRoot;$env:TEMP=$oldTemp;$env:TMP=$oldTmp;$env:BASTOS_TEST_SOURCE=$oldSource;$env:BASTOS_TEST_RUNTIME=$oldRuntime
}
Write-Output ('Validation terminee : '+(Join-Path $OutputDirectory 'ReleaseValidation.json'))
