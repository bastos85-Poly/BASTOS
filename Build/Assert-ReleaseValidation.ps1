param([Parameter(Mandatory)][string]$CandidateRoot,[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop'
$r=Get-Content -LiteralPath $ReportPath -Raw|ConvertFrom-Json
if($r.Schema -ne 1 -or ($r.Passed -isnot [bool] -or $r.Passed -ne $true) -or $r.Error){throw 'Livraison bloquee : validation incomplete ou en echec.'}
$required=@('ReleaseGate','VmGuards','engine','cancellation','resume','journal','integrity','guidance','postinstall','diagnostic-export','log-maintenance','WpfScenarios','VmReinstallation')
foreach($name in $required){$stage=@($r.Stages|Where-Object Name -ceq $name);if($stage.Count -ne 1 -or ($stage[0].Passed -isnot [bool] -or $stage[0].Passed -ne $true)){throw ('Livraison bloquee : scenario non valide '+$name)}}
$time=([DateTime]$r.CompletedUtc).ToUniversalTime()
if($time -gt [DateTime]::UtcNow.AddMinutes(1) -or $time -lt [DateTime]::UtcNow.AddHours(-24)){throw 'Livraison bloquee : validation trop ancienne ou date incoherente.'}
foreach($file in @(@{Path='Bastos.Native/BASTOS-Native.exe';Hash=$r.CandidateSha256},@{Path='BASTOS-App-Manifest.json';Hash=$r.ManifestSha256},@{Path='Bastos.Native/Source-Current.zip';Hash=$r.SourceZipSha256})){
 if(-not $file.Hash -or (Get-FileHash -LiteralPath (Join-Path $CandidateRoot $file.Path)).Hash -cne $file.Hash){throw ('Livraison bloquee : candidat modifie apres les tests : '+$file.Path)}
}
