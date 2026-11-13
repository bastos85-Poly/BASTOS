[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$WindowsLocale,
    [Parameter(Mandatory)][string]$KeyboardLayout,
    [ValidateSet('Administrator','BastOS')][string]$LocalUserName = 'BastOS',
    [Parameter(Mandatory)][string]$ResultPath,
    [ValidateRange(35,45)][int]$RecoverySizeGB = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LocalUserName = 'BastOS'
$workRoot=Join-Path $env:TEMP ('BASTOS-Autonomous-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force|Out-Null

function Save-PreparationResult {
    param([bool]$Success,[string]$Message,[string]$Stage)
    $parent=Split-Path -Parent $ResultPath
    if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $payload=[ordered]@{Success=$Success;Message=$Message;Stage=$Stage;PostInstallMode='BastosAutonomous';Date=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Depth 3),[Text.UTF8Encoding]::new($false))
}

function Invoke-Worker {
    param([string]$Script,[string[]]$Arguments)
    $tokens=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$Script)+$Arguments
    $commandLine=($tokens|ForEach-Object{'"'+([string]$_).Replace('"','\"')+'"'}) -join ' '
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $commandLine -PassThru -Wait -WindowStyle Hidden
    if($process.ExitCode -ne 0){throw "$([IO.Path]::GetFileName($Script)) a retourne le code $($process.ExitCode)."}
}

try{
    $bootstrap=Join-Path $PSScriptRoot 'Bastos-Uninstall.exe'
    if(-not(Test-Path -LiteralPath $bootstrap -PathType Leaf)){
        throw 'L installateur autonome BASTOS est absent. Reinstalle la derniere version de BASTOS puis recommence.'
    }
    $auditResult=Join-Path $workRoot 'audit.json'
    Invoke-Worker -Script (Join-Path $PSScriptRoot 'Test-BASTOS-AutonomousIso.ps1') -Arguments @('-IsoPath',$IsoPath,'-ResultPath',$auditResult)
    $audit=Get-Content -LiteralPath $auditResult -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not [bool]$audit.Success){throw [string]$audit.Message}

    $answerPath=Join-Path $workRoot 'autounattend-autonomous.xml'
    Invoke-Worker -Script (Join-Path $PSScriptRoot 'New-BASTOS-Official-Unattend.ps1') -Arguments @(
        '-OfficialIsoPath',$IsoPath,'-OutputPath',$answerPath,'-WindowsLocale',$WindowsLocale,
        '-KeyboardLayout',$KeyboardLayout,'-LocalUserName',$LocalUserName,'-PostInstallMode','BastosAutonomous'
    )
    if(-not(Test-Path -LiteralPath $answerPath -PathType Leaf)){throw 'Le profil autonome n a pas ete cree.'}

    $provisionResult=Join-Path $workRoot 'provision.json'
    Invoke-Worker -Script (Join-Path $PSScriptRoot 'Initialize-BASTOS-Recovery.ps1') -Arguments @(
        '-Action','Provision','-IsoPath',$IsoPath,'-AnswerFilePath',$answerPath,'-ResultPath',$provisionResult,
        '-RecoverySizeGB',[string]$RecoverySizeGB,'-RecoveryMode','Novice','-PostInstallMode','BastosAutonomous'
    )
    $provision=Get-Content -LiteralPath $provisionResult -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not [bool]$provision.Success){throw [string]$provision.Message}
    Save-PreparationResult -Success $true -Message ('Installation autonome preparee. '+[string]$provision.Message) -Stage 'Ready'
    exit 0
}catch{
    Save-PreparationResult -Success $false -Message $_.Exception.Message -Stage 'Error'
    Write-Error $_.Exception.Message
    exit 1
}finally{
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
