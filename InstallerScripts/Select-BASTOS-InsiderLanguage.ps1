[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LanguageValue,
    [Parameter(Mandatory)][string]$LanguageDisplay,
    [Parameter(Mandatory)][string]$DownloadDirectory,
    [Parameter(Mandatory)][string]$ResultPath,
    [ValidateRange(30,7200)][int]$TimeoutSeconds = 3600
)

$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$comboType=[Windows.Automation.ControlType]::ComboBox
$listItemType=[Windows.Automation.ControlType]::ListItem
$buttonType=[Windows.Automation.ControlType]::Button
$hyperlinkType=[Windows.Automation.ControlType]::Hyperlink
$comboCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,$comboType)
$listItemCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,$listItemType)
$buttonCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,$buttonType)
$hyperlinkCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,$hyperlinkType)
$targets=@($LanguageValue,$LanguageDisplay) | Where-Object {$_} | Select-Object -Unique
$stage='Edition'
$startedAt=Get-Date
$signInInvoked=$false

function Write-BastosInsiderState {
    param([string]$Status,[string]$Message,[string]$FilePath,[long]$Bytes=0,[long]$TotalBytes=0)
    $parent=Split-Path -Parent $ResultPath
    if($parent -and -not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $payload=[ordered]@{
        Status=$Status;Message=$Message;Uri='';FilePath=$FilePath;Bytes=$Bytes;TotalBytes=$TotalBytes
        Date=(Get-Date).ToString('o');Release='Insider26H2';Language=$LanguageValue
    }
    [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}

function Get-BastosInsiderDownload {
    if(-not(Test-Path -LiteralPath $DownloadDirectory -PathType Container)){return $null}
    Get-ChildItem -LiteralPath $DownloadDirectory -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.CreationTime -ge $startedAt.AddMinutes(-1) -or $_.LastWriteTime -ge $startedAt.AddMinutes(-1)) -and
            $_.Name -match '(?i)(Win(?:dows)?[\s._-]*11|WindowsInsiderPreview|Insider)' -and
            $_.Name -match '(?i)\.iso(?:\.(?:crdownload|part|tmp))?$'
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Select-BastosWebComboItem {
    param($Combo,[string[]]$Names,[string]$Pattern)
    try{
        $expand=$Combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        $expand.Expand()
        Start-Sleep -Milliseconds 400
    }catch{}
    $items=[Windows.Automation.AutomationElement]::RootElement.FindAll(
        [Windows.Automation.TreeScope]::Descendants,$listItemCondition)
    foreach($item in $items){
        $name=([string]$item.Current.Name).Trim()
        $exact=$Names | Where-Object {$name.Equals($_,[StringComparison]::OrdinalIgnoreCase)}
        if(-not $exact -and ($Pattern -eq '' -or $name -notmatch $Pattern)){continue}
        try{
            $selection=$item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
            $selection.Select()
            return $true
        }catch{}
    }
    return $false
}

function Invoke-BastosNearestConfirm {
    param($Window,$Combo)
    $comboRectangle=$Combo.Current.BoundingRectangle
    $buttons=$Window.FindAll([Windows.Automation.TreeScope]::Descendants,$buttonCondition)
    $candidates=@()
    foreach($button in $buttons){
        $name=([string]$button.Current.Name).Trim()
        if($name -notmatch '^(?i:Confirm|Confirmer|Bestätigen|Confirmar|Conferma|確認|확인)$' -or -not $button.Current.IsEnabled){continue}
        $rectangle=$button.Current.BoundingRectangle
        $distance=[Math]::Abs($rectangle.Top-$comboRectangle.Bottom)+[Math]::Abs($rectangle.Left-$comboRectangle.Left)
        $candidates+=[pscustomobject]@{Element=$button;Distance=$distance}
    }
    $candidate=$candidates|Sort-Object Distance|Select-Object -First 1
    if(-not $candidate){return $false}
    try{
        $invoke=$candidate.Element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
        $invoke.Invoke()
        return $true
    }catch{return $false}
}

while([DateTime]::UtcNow -lt $deadline){
    if($stage -eq 'Monitor'){
        $download=Get-BastosInsiderDownload
        if($download){
            $partial=$download.Name -match '(?i)\.(crdownload|part|tmp)$'
            $closed=$false
            if(-not $partial){
                try{
                    $stream=[IO.File]::Open($download.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
                    $stream.Dispose()
                    $closed=$true
                }catch{}
            }
            Write-BastosInsiderState -Status $(if($closed){'Completed'}else{'Downloading'}) `
                -Message $(if($closed){'Téléchargement Windows 11 26H2 Insider terminé.'}else{'Téléchargement Windows 11 26H2 Insider en cours.'}) `
                -FilePath $download.FullName -Bytes ([long]$download.Length)
            if($closed){exit 0}
        }else{
            Write-BastosInsiderState -Status 'DownloadStarted' -Message 'Le navigateur prépare le téléchargement Windows 11 26H2 Insider.'
        }
        Start-Sleep -Milliseconds 500
        continue
    }
    $windows=[Windows.Automation.AutomationElement]::RootElement.FindAll(
        [Windows.Automation.TreeScope]::Children,
        [Windows.Automation.Condition]::TrueCondition)
    foreach($window in $windows){
        $title=[string]$window.Current.Name
        if($title -notmatch '(?i)(Windows Insider|Microsoft|Software Download)'){continue}
        try{
            if($stage -eq 'Download'){
                $links=$window.FindAll([Windows.Automation.TreeScope]::Descendants,$hyperlinkCondition)
                $downloadControls=@($links)+@($window.FindAll([Windows.Automation.TreeScope]::Descendants,$buttonCondition))
                foreach($link in $downloadControls){
                    $name=([string]$link.Current.Name).Trim()
                    if($name -notmatch '(?i)(64-bit.*Download|Download.*64-bit|Téléchargement.*64|64 bits)'){continue}
                    try{
                        $invoke=$link.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
                        $invoke.Invoke()
                        $stage='Monitor'
                        Write-BastosInsiderState -Status 'DownloadStarted' -Message 'Téléchargement Windows 11 26H2 Insider lancé dans le navigateur.'
                        break
                    }catch{}
                }
            }
            if($stage -eq 'Edition' -and -not $signInInvoked){
                $links=@($window.FindAll([Windows.Automation.TreeScope]::Descendants,$hyperlinkCondition))+
                    @($window.FindAll([Windows.Automation.TreeScope]::Descendants,$buttonCondition))
                foreach($link in $links){
                    $name=([string]$link.Current.Name).Trim()
                    if($name -notmatch '^(?i:Sign in|Se connecter|Connexion|Anmelden|Iniciar sesión)$'){continue}
                    try{
                        $invoke=$link.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
                        $invoke.Invoke()
                        $signInInvoked=$true
                        Write-BastosInsiderState -Status 'SignIn' -Message 'Connexion Microsoft Insider demandée dans le navigateur.'
                        break
                    }catch{}
                }
            }
            $combos=$window.FindAll([Windows.Automation.TreeScope]::Descendants,$comboCondition)
            foreach($combo in $combos){
                $comboName=[string]$combo.Current.Name
                if($stage -eq 'Edition'){
                    if($comboName -and $comboName -notmatch '(?i)(edition|product|select)'){continue}
                    if(Select-BastosWebComboItem -Combo $combo -Names @() -Pattern '(?i)(26H2|26300)'){
                        if(Invoke-BastosNearestConfirm -Window $window -Combo $combo){$stage='Language';Start-Sleep -Seconds 2;break}
                    }
                }elseif($stage -eq 'Language'){
                    if($comboName -and $comboName -notmatch '(?i)(language|langue|idioma|sprache|lingua|select)'){continue}
                    if(Select-BastosWebComboItem -Combo $combo -Names $targets -Pattern ''){
                        if(Invoke-BastosNearestConfirm -Window $window -Combo $combo){$stage='Download';Start-Sleep -Seconds 2;break}
                    }
                }
            }
        }catch{}
    }
    Start-Sleep -Seconds 2
}
Write-BastosInsiderState -Status 'Timeout' -Message 'Microsoft n a pas affiché toutes les étapes Insider dans le délai prévu.'
exit 2
