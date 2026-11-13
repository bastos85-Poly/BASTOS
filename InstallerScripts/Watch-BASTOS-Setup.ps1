[CmdletBinding()]
param([switch]$Start)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$taskName='BASTOS-SetupDiagnostics'
$localLog=Join-Path $PSScriptRoot 'Logs\SetupDiagnostics.log'

function Write-CollectorLog([string]$Message){
    try{New-Item -ItemType Directory -Path (Split-Path -Parent $localLog) -Force|Out-Null; Add-Content -LiteralPath $localLog -Value (([DateTime]::UtcNow.ToString('o'))+' '+$Message) -Encoding UTF8}catch{}
}
function Get-CollectorContext {
    $config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SetupDiagnostics-Identity.json') -Raw|ConvertFrom-Json
    $candidates=@(Get-Partition -ErrorAction Stop|Where-Object { $_.DriveLetter -and ([string]$_.Guid).Trim('{}') -ieq ([string]$config.RecoveryPartitionGuid).Trim('{}') })
    if($candidates.Count -ne 1){throw 'Partition diagnostic absente ou ambigue.'}
    $partition=$candidates[0]
    $disk=Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
    if(([string]$disk.UniqueId).Trim('{}') -ine ([string]$config.WindowsDiskIdentity).Trim('{}')){throw 'Identite disque diagnostic divergente.'}
    $volume=$partition|Get-Volume -ErrorAction Stop
    if($volume.FileSystemLabel -ne 'BASTOS_RECOVERY' -or $volume.FileSystem -ne 'NTFS'){throw 'Volume diagnostic divergent.'}
    $root=([string]$partition.DriveLetter)+':\'
    if(-not(Test-Path -LiteralPath (Join-Path $root 'BASTOS-RECOVERY-PARTITION.txt'))){throw 'Marqueur diagnostic absent.'}
    $attempt=(Get-Content -LiteralPath (Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt') -Raw).Trim()
    if($attempt -notmatch '^Attempt-[0-9a-fA-F]{32}$'){throw 'Identifiant tentative invalide.'}
    [pscustomobject]@{Root=$root;Attempt=$attempt;Destination=Join-Path $root ('BASTOS-Diagnostics\Attempts\'+$attempt+'\Windows-Setup\Automatic-FirstBoot')}
}
function Copy-CollectorFile([string]$Source,[string]$Destination){
    if(-not(Test-Path -LiteralPath $Source -PathType Leaf)){return}
    $inputStream=$null;$outputStream=$null
    try{
        $inputStream=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $outputStream=[IO.File]::Open($Destination+'.tmp',[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $inputStream.CopyTo($outputStream);$outputStream.Dispose();$outputStream=$null
        Move-Item -LiteralPath ($Destination+'.tmp') -Destination $Destination -Force
    }catch{Write-CollectorLog ('Copie impossible '+$Source+': '+$_.Exception.Message)}
    finally{if($inputStream){$inputStream.Dispose()};if($outputStream){$outputStream.Dispose()}}
}
function Save-CollectorSnapshot($Context,[string]$WindowsRoot,[bool]$FirstLogonObserved){
    New-Item -ItemType Directory -Path $Context.Destination -Force|Out-Null
    $files=@('Panther\setupact.log','Panther\setuperr.log','Panther\diagerr.xml','Panther\diagwrn.xml','Panther\UnattendGC\setupact.log','Panther\UnattendGC\setuperr.log','System32\Sysprep\Panther\setupact.log','System32\Sysprep\Panther\setuperr.log','INF\setupapi.dev.log','INF\setupapi.offline.log')
    foreach($relative in $files){Copy-CollectorFile (Join-Path $WindowsRoot $relative) (Join-Path $Context.Destination $relative.Replace('\','--'))}
    foreach($name in @('setupact.log','setuperr.log')){Copy-CollectorFile (Join-Path (Split-Path -Parent $WindowsRoot) ('$WINDOWS.~BT\Sources\Panther\'+$name)) (Join-Path $Context.Destination ('Setup-'+$name))}
    $stage=if($FirstLogonObserved){'FirstLogonObserved'}else{'FirstBootCaptureActive'}
    $state=[ordered]@{Schema=1;AttemptId=$Context.Attempt;Stage=$stage;FirstLogonObserved=$FirstLogonObserved;CapturedUtc=[DateTime]::UtcNow.ToString('o');WindowsRoot=$WindowsRoot;Diagnostic=$Context.Destination}
    [IO.File]::WriteAllText((Join-Path $Context.Destination 'Capture-State.json'),($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $summary=@('AttemptId='+$Context.Attempt,'Stage='+$stage,'CapturedUtc='+$state.CapturedUtc,'Diagnostic='+$Context.Destination,'Les erreurs ci-dessous sont des indices, pas une preuve de cause fatale.')
    foreach($relative in @('Panther\setuperr.log','Panther\UnattendGC\setuperr.log','System32\Sysprep\Panther\setuperr.log')){
        $path=Join-Path $Context.Destination $relative.Replace('\','--')
        if(Test-Path -LiteralPath $path){$summary+=('--- '+$relative);$summary+=@(Get-Content -LiteralPath $path -Tail 40 -ErrorAction SilentlyContinue)}
    }
    [IO.File]::WriteAllLines((Join-Path $Context.Root 'BASTOS-DIAGNOSTIC-AUTOMATIQUE.txt'),[string[]]$summary,[Text.UTF8Encoding]::new($true))
    Copy-CollectorFile $localLog (Join-Path $Context.Destination 'Collector.log')
}

$mutex=$null;$ownsMutex=$false
try{
    if($Start){
        Write-CollectorLog 'Demarrage en specialize ; enregistrement collecte au prochain boot.'
        $context=Get-CollectorContext
        Save-CollectorSnapshot $context $env:SystemRoot $false
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$PSCommandPath+'"'
        & schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR ('"'+$powershell+'" '+$arguments) /F 2>&1|ForEach-Object {Write-CollectorLog ([string]$_)}
        Write-CollectorLog ('Enregistrement tache retour '+$LASTEXITCODE)
        Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden|Out-Null
    }else{
        $mutex=[Threading.Mutex]::new($false,'Global\BASTOS-SetupDiagnostics')
        try{$ownsMutex=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsMutex=$true}
        if(-not $ownsMutex){exit 0}
        Write-CollectorLog 'Collecte active sans ouverture de session.'
        $deadline=[DateTime]::UtcNow.AddHours(1)
        do{
            try{
                $context=Get-CollectorContext
                $done=Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Logs\Rufus-FirstLogon.ok')
                Save-CollectorSnapshot $context $env:SystemRoot $done
                if($done){
                    foreach($channel in @('Setup','System','Application')){try{& wevtutil.exe epl $channel (Join-Path $context.Destination ($channel+'.evtx')) /ow:true 2>$null|Out-Null}catch{}}
                    & schtasks.exe /Delete /TN $taskName /F 2>&1|Out-Null
                    Write-CollectorLog 'Premiere connexion observee ; collecte arretee.'
                    break
                }
            }catch{Write-CollectorLog $_.Exception.Message}
            Start-Sleep -Seconds 5
        }while([DateTime]::UtcNow -lt $deadline)
    }
}catch{Write-CollectorLog $_.Exception.Message}
finally{if($ownsMutex){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
# Une panne de diagnostic ne doit jamais faire echouer Windows Setup.
exit 0
