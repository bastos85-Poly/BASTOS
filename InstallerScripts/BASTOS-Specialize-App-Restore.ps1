$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'BASTOS-Architecture.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Module d architecture BASTOS absent : $modulePath"
}
Import-Module $modulePath -Force

# BASTOS_RECOVERY\Application est la source persistante; C:\ProgramData\BASTOS-ISO
# est un cache d execution jetable. Robocopy ne transfere que les fichiers
# modifies et conserve les selections propres a l installation en cours.
$recoveryRoot = Get-BastosRecoveryRoot -WaitSeconds 30
$source = Join-Path $recoveryRoot 'Application'
Invoke-BastosRuntimeSync -SourceRoot $source | Out-Null
exit 0
