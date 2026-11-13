[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$RufusPath,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$IsoPath,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Save-LaunchResult {
    param([bool]$IsoPreselected,[string]$Message)
    $parent = Split-Path -Parent $ResultPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $payload = [pscustomobject]@{ Success=$true; IsoPreselected=$IsoPreselected; Message=$Message; IsoPath=$IsoPath }
    [IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
}

$signature = Get-AuthenticodeSignature -LiteralPath $RufusPath
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)Akeo Consulting') {
    throw 'Rufus ne possede pas une signature Akeo Consulting valide.'
}
if ([IO.Path]::GetExtension($IsoPath) -ne '.iso') { throw 'Le fichier choisi pour Rufus doit etre une image ISO.' }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$launched = Start-Process -FilePath $RufusPath -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(20)
$window = $null
while (-not $window -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    foreach ($candidate in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'rufus*' -and $_.MainWindowHandle -ne 0 })) {
        try {
            $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, $candidate.Id)
            $window = [Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $condition)
            if ($window) { break }
        } catch {}
    }
}
if (-not $window) {
    Save-LaunchResult -IsoPreselected $false -Message 'Rufus est ouvert, mais sa fenetre n a pas ete detectee. Le chemin ISO a ete copie par BASTOS.'
    exit 0
}

try {
    $buttonCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
    $buttons = $window.FindAll([Windows.Automation.TreeScope]::Descendants, $buttonCondition)
    $selectButton = $null
    foreach ($button in $buttons) {
        $name = ([string]$button.Current.Name).Trim().Replace('&','')
        if ($name -match '^(?i:SELECT|SELECTION|SELECTIONNER|SÉLECTION|SÉLECTIONNER)$') { $selectButton = $button; break }
    }
    if (-not $selectButton) { throw 'Bouton de selection ISO introuvable dans Rufus.' }
    $invoke = $selectButton.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()

    $dialogDeadline = [DateTime]::UtcNow.AddSeconds(12)
    $dialog = $null
    while (-not $dialog -and [DateTime]::UtcNow -lt $dialogDeadline) {
        Start-Sleep -Milliseconds 200
        $dialogCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, '#32770')
        $dialogs = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $dialogCondition)
        foreach ($candidateDialog in $dialogs) {
            if ($candidateDialog.Current.ProcessId -eq $window.Current.ProcessId) { $dialog = $candidateDialog; break }
        }
    }
    if (-not $dialog) { throw 'Fenetre de selection du fichier ISO introuvable.' }

    $editCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
    $edits = $dialog.FindAll([Windows.Automation.TreeScope]::Descendants, $editCondition)
    $fileNameEdit = $null
    foreach ($edit in $edits) {
        if ([string]$edit.Current.AutomationId -eq '1148') { $fileNameEdit = $edit; break }
    }
    if (-not $fileNameEdit -and $edits.Count -gt 0) { $fileNameEdit = $edits.Item($edits.Count - 1) }
    if (-not $fileNameEdit) { throw 'Champ du nom de fichier introuvable.' }
    $valuePattern = $fileNameEdit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    $valuePattern.SetValue($IsoPath)

    $dialogButtons = $dialog.FindAll([Windows.Automation.TreeScope]::Descendants, $buttonCondition)
    $openButton = $null
    foreach ($button in $dialogButtons) {
        $name = ([string]$button.Current.Name).Trim().Replace('&','')
        if ($name -match '^(?i:OPEN|OUVRIR)$') { $openButton = $button; break }
    }
    if (-not $openButton) { throw 'Bouton Ouvrir introuvable.' }
    $openInvoke = $openButton.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $openInvoke.Invoke()
    Save-LaunchResult -IsoPreselected $true -Message 'ISO BASTOS chargee dans Rufus. Choisis et verifie toi-meme la cle USB, puis clique sur Demarrer.'
} catch {
    Save-LaunchResult -IsoPreselected $false -Message ("Rufus est ouvert. Preselection automatique impossible : {0}. Le chemin ISO a ete copie par BASTOS." -f $_.Exception.Message)
}

