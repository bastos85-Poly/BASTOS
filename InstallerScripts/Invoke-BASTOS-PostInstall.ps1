[CmdletBinding()]
param([string]$ResultPath = 'C:\ProgramData\BASTOS-ISO\PostInstall-Result.json')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$steps=[Collections.Generic.List[object]]::new()
function Add-Step([string]$Name,[bool]$Success,[string]$Message){$steps.Add([pscustomobject]@{Name=$Name;Success=$Success;Message=$Message})}

try {
    $removalOptionsPath = 'C:\ProgramData\BASTOS-ISO\BASTOS-Removal-Options.json'
    $removeOneDrive = $true
    if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
        $removeOneDrive = [bool](Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json).RemoveOneDrive
    }
    # OneDrive est deja traite en deux temps : composants machine pendant
    # Apply-Machine.ps1, puis elements du profil dans
    # Complete-BASTOS-UserSetup.ps1. Ne pas relancer ici une suppression
    # Scope Both, qui constituerait un troisieme passage inutile.
    Add-Step 'OneDrive' $true $(if($removeOneDrive){'Suppression geree pendant les phases machine et utilisateur.'}else{'OneDrive conserve selon le choix de l ISO.'})

    # Microsoft Edge est conserve jusqu'a ce qu'un autre navigateur soit
    # installe et verifie dans BASTOS.
    $criticalOk=$true
    Add-Step 'Edge' $true 'Microsoft Edge conserve jusqu au remplacement verifie depuis BASTOS; WebView2 reste intact.'
    $payload=[ordered]@{Success=$criticalOk;OneDriveHandledByMachineAndUserPhases=$removeOneDrive;EdgeDeferredUntilBrowserReplacement=$true;Steps=@($steps);Date=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    if(-not $criticalOk){exit 1}
    exit 0
} catch {
    Add-Step 'PostInstall' $false $_.Exception.Message
    $payload=[ordered]@{Success=$false;Steps=@($steps);Date=[DateTime]::UtcNow.ToString('o')}
    $parent=Split-Path -Parent $ResultPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    exit 1
}
