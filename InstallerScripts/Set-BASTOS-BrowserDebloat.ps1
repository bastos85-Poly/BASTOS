[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Brave','Edge')][string]$Target,
    [string]$ResultPath=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try {
    $worker=Join-Path $PSScriptRoot 'General-Optimization-Tools\35 Manage BASTOS Options.ps1'
    if(-not(Test-Path -LiteralPath $worker -PathType Leaf)){throw 'Module de debloat navigateur absent.'}
    $option=if($Target -eq 'Brave'){'BraveDebloat'}else{'EdgeDebloat'}
    & $worker -Option $option -Choix 1|Out-Null
    $payload=[ordered]@{Success=$true;Target=$Target;Message="Debloat $Target applique avec sauvegarde reversible.";Date=[DateTime]::UtcNow.ToString('o')}
    if($ResultPath){$parent=Split-Path -Parent $ResultPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    exit 0
}catch{
    if($ResultPath){$parent=Split-Path -Parent $ResultPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllText($ResultPath,([ordered]@{Success=$false;Target=$Target;Message=$_.Exception.Message;Date=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    exit 1
}
