param([Parameter(Mandatory)][string]$TestRoot)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($TestRoot)
if(Test-Path -LiteralPath (Join-Path $root 'Config.json')){throw 'Choisir un nouveau dossier de test pour ne pas écraser une configuration.'}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$probe=Join-Path $root 'GameProbe.exe'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BASTOS-Game.exe') -Destination $probe
$argsList=@('--self-test','--config',('"'+$root+'\Config.json"'),'--status',('"'+$root+'\Status.json"'),'--recovery',('"'+$root+'\Recovery.json"'),'--log',('"'+$root+'\test.log"'))
$process=Start-Process -FilePath $probe -ArgumentList $argsList -Wait -PassThru -WindowStyle Hidden
$result=Get-Content -LiteralPath (Join-Path $root 'tests.json') -Raw | ConvertFrom-Json
if($process.ExitCode -ne 0 -or -not $result.Success){throw ($result | ConvertTo-Json -Depth 8)}
$result
