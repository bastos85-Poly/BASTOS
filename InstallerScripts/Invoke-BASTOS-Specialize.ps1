[CmdletBinding()]
param(
    [string]$RecoveryRoot = '',
    [string]$WindowsRoot = $env:SystemRoot,
    [string]$RuntimeRoot = 'C:\ProgramData\BASTOS-ISO'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'BASTOS-SetupDiagnostics.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { exit 0 }
Import-Module $modulePath -Force

if (-not $RecoveryRoot) {
    try {
        $volumes = @(Get-Volume -FileSystemLabel 'BASTOS_RECOVERY' -ErrorAction SilentlyContinue | Where-Object DriveLetter)
        if ($volumes.Count -eq 1) { $RecoveryRoot = ('{0}:\' -f $volumes[0].DriveLetter) }
    } catch {}
}
$storageRoot = if ($RecoveryRoot) { $RecoveryRoot } else { 'C:\ProgramData' }
$context = Get-BastosDiagnosticContext -StorageRoot $storageRoot -Create
$errors = New-Object Collections.Generic.List[string]

function Invoke-SpecializeStep {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$ScriptPath,[string[]]$Arguments=@())
    $stdout = Join-Path $context.AttemptRoot ($Name + '-stdout.log')
    $stderr = Join-Path $context.AttemptRoot ($Name + '-stderr.log')
    try {
        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "Script absent : $ScriptPath" }
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Message "Debut $Name."
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList (@(
            '-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$ScriptPath
        ) + $Arguments) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if ($process.ExitCode -ne 0) { throw "$Name a retourne le code $($process.ExitCode)." }
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'OK' -Message "$Name termine."
    } catch {
        $errors.Add($Name + ': ' + $_.Exception.Message)
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'ERROR' -Message ($Name + ': ' + $_.Exception.Message)
    }
    Copy-BastosSetupDiagnostics -Context $context -WindowsRoot $WindowsRoot -SnapshotName $Name
}

try {
    Set-BastosDiagnosticState -Context $context -Stage 'FirstLogonMachineStarted' -Message 'Orchestrateur machine BASTOS demarre apres OOBE.'
    Write-BastosDiagnosticEvent -Context $context -Component 'MachinePhase' -Message 'Phase machine BASTOS demarree apres OOBE en mode fail-open.'
    if ($RecoveryRoot) {
        try {
            $architecture = Join-Path $PSScriptRoot 'BASTOS-Architecture.psm1'
            if (-not (Test-Path -LiteralPath $architecture -PathType Leaf)) { throw "Module absent : $architecture" }
            Import-Module $architecture -Force
            Invoke-BastosRuntimeSync -SourceRoot (Join-Path $RecoveryRoot 'Application') -DestinationRoot $RuntimeRoot | Out-Null
            Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'OK' -Message 'Runtime 7.77 restaure depuis BASTOS_RECOVERY.'
        } catch {
            $errors.Add('RuntimeSync: ' + $_.Exception.Message)
            Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'ERROR' -Message ('RuntimeSync: ' + $_.Exception.Message)
        }
    }

    Invoke-SpecializeStep -Name 'WindowsUpdateOff' -ScriptPath (Join-Path $RuntimeRoot 'BASTOS-Specialize-WU-Off.ps1')
    Invoke-SpecializeStep -Name 'ApplyMachine' -ScriptPath (Join-Path $RuntimeRoot 'Apply-Machine.ps1')
    Invoke-SpecializeStep -Name 'IntegrateWinRE' -ScriptPath (Join-Path $RuntimeRoot 'Integrate-WinRE-Into-BASTOS.ps1')
    Copy-BastosSetupDiagnostics -Context $context -WindowsRoot $WindowsRoot -SnapshotName 'SpecializeFinal'

    if ($errors.Count -eq 0) {
        Set-BastosDiagnosticState -Context $context -Stage 'FirstLogonMachineCompleted' -Success $true -Message 'Toutes les etapes machine BASTOS sont terminees.'
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'OK' -Message 'Phase specialize terminee.'
    } else {
        $message = $errors -join ' | '
        Set-BastosDiagnosticState -Context $context -Stage 'FirstLogonMachineCompletedWithErrors' -Success $false -Message $message
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'WARNING' -Message ('Windows continue malgre les erreurs BASTOS : ' + $message)
    }
} catch {
    try {
        Copy-BastosSetupDiagnostics -Context $context -WindowsRoot $WindowsRoot -SnapshotName 'SpecializeUnhandledFailure'
        Set-BastosDiagnosticState -Context $context -Stage 'FirstLogonMachineUnhandledFailure' -Success $false -Message $_.Exception.Message
        Write-BastosDiagnosticEvent -Context $context -Component 'Specialize' -Level 'ERROR' -Message $_.Exception.Message
    } catch {}
}

# Les personnalisations BASTOS ne doivent jamais transformer une installation
# Windows reussie en echec OOBE. Toutes les erreurs sont conservees sur Recovery.
exit 0
