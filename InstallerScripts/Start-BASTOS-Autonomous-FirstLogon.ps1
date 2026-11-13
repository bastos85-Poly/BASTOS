$ErrorActionPreference='Stop'
$orchestrator=Join-Path $PSScriptRoot 'Initialize-BASTOS-Autonomous-FirstLogon.ps1'
if(-not(Test-Path -LiteralPath $orchestrator -PathType Leaf)){throw "Orchestrateur BASTOS absent : $orchestrator"}

# FirstLogonCommands attend normalement la fin du programme. Démarrer un
# processus séparé permet à Windows d afficher le Bureau pendant que la chaîne
# BASTOS continue dans une console visible; le processus enfant hérite du
# contexte élevé et montre clairement chaque opération au propriétaire du PC.
$process=Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoLogo','-NoProfile',
    '-ExecutionPolicy','Bypass','-File',$orchestrator
) -PassThru -WindowStyle Normal
if(-not $process -or $process.HasExited){
    if(-not $process -or $process.ExitCode -ne 0){throw 'Le lancement de la post-installation BASTOS a echoue.'}
}
exit 0
