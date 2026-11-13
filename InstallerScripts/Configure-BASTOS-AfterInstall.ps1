[CmdletBinding()]
param(
    [switch]$CursorOnly,
    [string]$ResultPath,
    [string]$TargetUserSid,
    [string]$TargetLocalAppData
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installedRoot = 'C:\ProgramData\BASTOS-ISO'
# D:\Application est la source de recuperation et peut etre protegee en ecriture.
# Les selections et resultats de l assistant sont donc toujours enregistres
# dans la copie de travail locale installee par BASTOS.
$root = if (Test-Path -LiteralPath (Join-Path $installedRoot 'Remove-BASTOS-Edge.ps1')) {
    $installedRoot
} else {
    $sourceRoot
}
$cursorPackRoot = Join-Path $sourceRoot 'Assets\Cursor-Dark'
if (-not $TargetUserSid) { $TargetUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
if (-not $TargetLocalAppData) { $TargetLocalAppData = $env:LOCALAPPDATA }
$stateRoot = Join-Path $TargetLocalAppData 'BASTOS\State'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$logRoot = Join-Path $TargetLocalAppData 'BASTOS\Logs'
$logPath = Join-Path $logRoot 'After-Install.log'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Write-BastosAfterInstallLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Show-BastosStage {
    param([string]$Message)
    Write-Host "`r`n=== $Message ===" -ForegroundColor Cyan
    Write-BastosAfterInstallLog $Message
}

function Test-BastosAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-BastosBrowserChoice {
    $catalog = @(
        [pscustomobject]@{ Id='Chrome'; DisplayName='Google Chrome'; WingetId='Google.Chrome'; OfficialUri='https://www.google.com/chrome/' },
        [pscustomobject]@{ Id='Brave'; DisplayName='Brave'; WingetId='Brave.Brave'; OfficialUri='https://brave.com/download/' },
        [pscustomobject]@{ Id='Firefox'; DisplayName='Mozilla Firefox'; WingetId='Mozilla.Firefox'; OfficialUri='https://www.mozilla.org/firefox/new/' },
        [pscustomobject]@{ Id='FirefoxNightly'; DisplayName='Mozilla Firefox Nightly'; WingetId='Mozilla.Firefox.Nightly.MSIX'; OfficialUri='https://nightly.mozfr.org/' },
        [pscustomobject]@{ Id='Opera'; DisplayName='Opera'; WingetId='Opera.Opera'; OfficialUri='https://www.opera.com/download' },
        [pscustomobject]@{ Id='Vivaldi'; DisplayName='Vivaldi'; WingetId='Vivaldi.Vivaldi'; OfficialUri='https://vivaldi.com/download/' }
    )
    $form = New-Object Windows.Forms.Form
    $form.Text = 'BASTOS - navigateur Internet'
    $form.Size = New-Object Drawing.Size(520,235)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $label = New-Object Windows.Forms.Label
    $label.Text = "Choisis le navigateur à installer. Après sa vérification, BASTOS supprimera automatiquement Microsoft Edge tout en conservant WebView2."
    $label.Location = New-Object Drawing.Point(22,20)
    $label.Size = New-Object Drawing.Size(465,52)
    $form.Controls.Add($label)
    $combo = New-Object Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.Location = New-Object Drawing.Point(24,83)
    $combo.Size = New-Object Drawing.Size(455,30)
    foreach ($browser in $catalog) { [void]$combo.Items.Add($browser.DisplayName) }
    $combo.SelectedIndex = 0
    $form.Controls.Add($combo)
    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'Installer et continuer'
    $ok.Location = New-Object Drawing.Point(276,137)
    $ok.Size = New-Object Drawing.Size(203,34)
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $ok
    $form.Controls.Add($ok)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Annuler'
    $cancel.Location = New-Object Drawing.Point(164,137)
    $cancel.Size = New-Object Drawing.Size(100,34)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancel
    $form.Controls.Add($cancel)
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { $form.Dispose(); return $null }
    $selected=$catalog[$combo.SelectedIndex]|Select-Object *,@{Name='RemoveEdge';Expression={$true}}
    $form.Dispose()
    return $selected
}

function Get-BastosBrowserExecutable {
    param([string]$BrowserId)
    $candidates = switch ($BrowserId) {
        'Chrome' { @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$TargetLocalAppData\Google\Chrome\Application\chrome.exe") }
        'Brave' { @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$TargetLocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe") }
        'Firefox' { @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$TargetLocalAppData\Mozilla Firefox\firefox.exe") }
        'FirefoxNightly' { @("$env:ProgramFiles\Firefox Nightly\firefox.exe", "${env:ProgramFiles(x86)}\Firefox Nightly\firefox.exe", "$TargetLocalAppData\Firefox Nightly\firefox.exe") }
        'Opera' { @("$TargetLocalAppData\Programs\Opera\opera.exe", "$env:ProgramFiles\Opera\opera.exe") }
        'Vivaldi' { @("$env:ProgramFiles\Vivaldi\Application\vivaldi.exe", "${env:ProgramFiles(x86)}\Vivaldi\Application\vivaldi.exe", "$TargetLocalAppData\Vivaldi\Application\vivaldi.exe") }
    }
    if($BrowserId -eq 'FirefoxNightly'){
        foreach($package in @(Get-AppxPackage -Name '*Firefox*Nightly*' -ErrorAction SilentlyContinue)){
            if($package.InstallLocation){$candidates+=@(Get-ChildItem -LiteralPath $package.InstallLocation -Filter 'firefox.exe' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName -First 1)}
        }
    }
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Install-BastosWingetPackage {
    param([string]$Id, [string]$DisplayName)
    Write-BastosAfterInstallLog "Installation demandée : $DisplayName ($Id)."
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'WinGet est indisponible. Installe ou répare Microsoft App Installer puis recommence.' }
    $process = Start-Process -FilePath $winget.Source -ArgumentList @('install','--id',$Id,'--exact','--source','winget','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity') -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(600000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "L'installation de $DisplayName a dépassé dix minutes."
    }
    if ($process.ExitCode -notin @(0,-1978335189)) { throw "L'installation de $DisplayName a échoué (code $($process.ExitCode))." }
    Write-BastosAfterInstallLog "Installation terminée : $DisplayName." 'OK'
}

function Install-BastosDarkCursorPack {
    $infPath = Join-Path $cursorPackRoot 'Install.inf'
    $creditsPath = Join-Path $cursorPackRoot 'CREDITS-AND-LICENSE.txt'
    if (-not (Test-Path -LiteralPath $infPath -PathType Leaf)) { throw "Pack de curseurs dark introuvable : $infPath" }
    if (-not (Test-Path -LiteralPath $creditsPath -PathType Leaf)) { throw 'Le credit et la licence du pack de curseurs sont absents.' }

    $expectedFiles = @(
        'arrow.cur','help.cur','appstarting.ani','wait.ani','crosshair.cur','ibeam.cur',
        'nwpen.cur','no.cur','sizens.cur','sizewe.cur','sizenwse.cur','sizenesw.cur',
        'sizeall.cur','uparrow.cur','hand.cur','person.cur','pin.cur'
    )
    $missingSources = @($expectedFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $cursorPackRoot $_) -PathType Leaf) })
    if ($missingSources.Count -gt 0) { throw "Pack de curseurs incomplet : $($missingSources -join ', ')" }

    Write-BastosAfterInstallLog 'Installation du pack W11 Cursor Dark Free demandee.'
    # Reproduire exactement le verbe "clic droit > Installer" de Windows 11.
    # L ancienne invocation InstallHinfSection affiche a tort "installation
    # echouee" avec certains INF de schemas de curseurs.
    $infDefaultInstall = Join-Path $env:SystemRoot 'System32\InfDefaultInstall.exe'
    if (-not (Test-Path -LiteralPath $infDefaultInstall -PathType Leaf)) {
        throw "Le programme d installation INF de Windows est introuvable : $infDefaultInstall"
    }
    # L INF ouvre ensuite la feuille "Proprietes de : Souris". Un petit
    # superviseur eleve reproduit Appliquer puis OK pour que l utilisateur
    # n ait aucun bouton supplementaire a valider apres l UAC.
    $cursorDialogCloser = @'
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BastosMousePropertyCloser {
    public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr window, int identifier);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    public static IntPtr FindMouseProperties() {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr parameter) {
            var title = new StringBuilder(260);
            var className = new StringBuilder(64);
            GetWindowText(window, title, title.Capacity);
            GetClassName(window, className, className.Capacity);
            string value = title.ToString();
            if (className.ToString() == "#32770" &&
                (value.IndexOf("Souris", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 value.IndexOf("Mouse", StringComparison.OrdinalIgnoreCase) >= 0)) {
                found = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
$deadline=(Get-Date).AddSeconds(20)
do {
    $window=[BastosMousePropertyCloser]::FindMouseProperties()
    if($window -ne [IntPtr]::Zero){
        $apply=[BastosMousePropertyCloser]::GetDlgItem($window,0x3021)
        if($apply -ne [IntPtr]::Zero -and [BastosMousePropertyCloser]::IsWindowEnabled($apply)){
            [void][BastosMousePropertyCloser]::SendMessage($apply,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
            Start-Sleep -Milliseconds 350
        }
        $ok=[BastosMousePropertyCloser]::GetDlgItem($window,1)
        if($ok -ne [IntPtr]::Zero){
            [void][BastosMousePropertyCloser]::SendMessage($ok,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
            exit 0
        }
    }
    Start-Sleep -Milliseconds 150
} while((Get-Date)-lt $deadline)
exit 2
'@
    $encodedCloser = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cursorDialogCloser))
    $closerProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand $encodedCloser" -PassThru -WindowStyle Hidden
    $process = Start-Process -FilePath $infDefaultInstall -ArgumentList ('"{0}"' -f $infPath) -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Installation du pack de curseurs impossible (code $($process.ExitCode))." }
    if($closerProcess -and $closerProcess.HasExited -and $closerProcess.ExitCode -eq 0){
        Write-BastosAfterInstallLog 'Fenetre des pointeurs validee automatiquement avec Appliquer puis OK.' 'OK'
    }

    $installedCursorRoot = Join-Path $env:SystemRoot 'Cursors\W11 Cursor Dark Free'
    $missingInstalled = @($expectedFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $installedCursorRoot $_) -PathType Leaf) })
    if ($missingInstalled.Count -gt 0) {
        # Certains Windows acceptent l'INF mais ne copient pas ses fichiers.
        # L'assistant est déjà élevé : terminer alors l'installation directement,
        # fichier par fichier, puis vérifier de nouveau avant d'activer le schéma.
        Write-BastosAfterInstallLog "L INF n a pas copie $($missingInstalled.Count) curseur(s). Copie directe securisee en cours." 'WARN'
        New-Item -ItemType Directory -Path $installedCursorRoot -Force | Out-Null
        foreach($fileName in $expectedFiles){
            Copy-Item -LiteralPath (Join-Path $cursorPackRoot $fileName) -Destination (Join-Path $installedCursorRoot $fileName) -Force
        }
        $missingInstalled = @($expectedFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $installedCursorRoot $_) -PathType Leaf) })
    }
    if ($missingInstalled.Count -gt 0) { throw "Le pack de curseurs reste incomplet apres la copie directe : $($missingInstalled -join ', ')" }

    $schemeName = 'W11 Cursor Dark Free by Jepri Creations'
    $cursorKey = "Registry::HKEY_USERS\$TargetUserSid\Control Panel\Cursors"
    $schemesKey = Join-Path $cursorKey 'Schemes'
    if (-not (Test-Path -LiteralPath $cursorKey)) { throw "La ruche de l utilisateur cible n est pas chargee : $TargetUserSid" }
    if (-not (Test-Path -LiteralPath $schemesKey)) { New-Item -Path $schemesKey -Force | Out-Null }

    $cursorAssignments = [ordered]@{
        AppStarting='appstarting.ani'; Arrow='arrow.cur'; Crosshair='crosshair.cur'; Hand='hand.cur'; Help='help.cur';
        IBeam='ibeam.cur'; No='no.cur'; NWPen='nwpen.cur'; SizeAll='sizeall.cur'; SizeNESW='sizenesw.cur';
        SizeNS='sizens.cur'; SizeNWSE='sizenwse.cur'; SizeWE='sizewe.cur'; UpArrow='uparrow.cur';
        Wait='wait.ani'; Person='person.cur'; Pin='pin.cur'
    }
    foreach ($entry in $cursorAssignments.GetEnumerator()) {
        New-ItemProperty -LiteralPath $cursorKey -Name $entry.Key -PropertyType ExpandString -Value (Join-Path $installedCursorRoot $entry.Value) -Force | Out-Null
    }
    $schemeOrder = @('Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No','SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Person','Pin')
    $schemeValue = ($schemeOrder | ForEach-Object { Join-Path $installedCursorRoot $cursorAssignments[$_] }) -join ','
    New-ItemProperty -LiteralPath $schemesKey -Name $schemeName -PropertyType ExpandString -Value $schemeValue -Force | Out-Null
    $nativeCursorKey = [Microsoft.Win32.Registry]::Users.OpenSubKey("$TargetUserSid\Control Panel\Cursors",$true)
    if (-not $nativeCursorKey) { throw 'La cle native des curseurs ne peut pas etre ouverte en ecriture.' }
    try { $nativeCursorKey.SetValue('',$schemeName,[Microsoft.Win32.RegistryValueKind]::String) } finally { $nativeCursorKey.Dispose() }

    $cursorState = Get-ItemProperty -LiteralPath $cursorKey -ErrorAction Stop
    $activeScheme = [string](Get-Item -LiteralPath $cursorKey).GetValue('')
    $arrowPath = Join-Path $installedCursorRoot 'arrow.cur'
    if ($activeScheme -ne $schemeName -or [string]$cursorState.Arrow -ne $arrowPath) {
        throw 'Le pack est copie, mais son schema n a pas ete active pour l utilisateur courant.'
    }

    if (-not ('BastosCursorRefresh' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BastosCursorRefresh {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(uint action, uint parameter, IntPtr value, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SendNotifyMessage(IntPtr window, uint message, UIntPtr wParam, string lParam);
}
'@
    }
    # SPI_SETCURSORS recharge le schema. SPIF_SENDCHANGE (2) diffuse la
    # modification; SPIF_UPDATEINIFILE n est pas accepte pour cette action.
    $cursorReloaded = [BastosCursorRefresh]::SystemParametersInfo(0x0057,0,[IntPtr]::Zero,2)
    $cursorBroadcast = [BastosCursorRefresh]::SendNotifyMessage(
        [IntPtr]0xFFFF,0x001A,[UIntPtr]::Zero,'Control Panel\Cursors')
    if (-not $cursorBroadcast) {
        Write-BastosAfterInstallLog 'Le schema est actif, mais la diffusion WM_SETTINGCHANGE a ete refusee.' 'WARN'
    }
    if (-not $cursorReloaded) {
        $rundll32 = Join-Path $env:SystemRoot 'System32\rundll32.exe'
        $refreshProcess = Start-Process -FilePath $rundll32 -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' -PassThru -Wait -WindowStyle Hidden
        if ($refreshProcess.ExitCode -ne 0) { throw 'Le schema est installe, mais le pointeur n a pas pu etre recharge.' }
    }

    $runOnceSetup = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce\Setup'
    if (Test-Path -LiteralPath $runOnceSetup) {
        $defaultCommand = [string](Get-Item -LiteralPath $runOnceSetup).GetValue('')
        if ($defaultCommand -eq 'rundll32.exe shell32.dll,Control_RunDLL main.cpl @0,1') {
            & reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce\Setup' /ve /f | Out-Null
        }
    }

    $state = [ordered]@{
        Scheme = $schemeName
        InstalledRoot = $installedCursorRoot
        Author = 'Jepri Creations'
        Credits = $creditsPath
        InstalledUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $stateRoot 'Cursor-Dark.json'),($state | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Write-BastosAfterInstallLog "Pack de curseurs dark installe, active et verifie : $schemeName." 'OK'
}

if (-not (Test-BastosAdministrator)) {
    $arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path
    if ($CursorOnly) { $arguments += ' -CursorOnly' }
    if ($ResultPath) { $arguments += ' -ResultPath "{0}"' -f $ResultPath }
    $arguments += ' -TargetUserSid "{0}" -TargetLocalAppData "{1}"' -f $TargetUserSid,$TargetLocalAppData
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments | Out-Null
    return
}

try {
    if ($CursorOnly) {
        Show-BastosStage 'Installation du pack de curseurs dark'
        Install-BastosDarkCursorPack
        $result = [ordered]@{ Success=$true; Scheme='W11 Cursor Dark Free by Jepri Creations'; StatePath=(Join-Path $stateRoot 'Cursor-Dark.json') }
        if ($ResultPath) { [IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json),[Text.UTF8Encoding]::new($false)) }
        [pscustomobject]$result
        return
    }
    Clear-Host
    Write-Host 'BASTOS - Configuration après installation' -ForegroundColor Cyan
    Write-BastosAfterInstallLog 'Assistant manuel démarré.'
    Show-BastosStage 'Installation et activation du pack de curseurs dark'
    Install-BastosDarkCursorPack
    $browser = Show-BastosBrowserChoice
    if (-not $browser) { Write-BastosAfterInstallLog 'Assistant annulé avant le choix du navigateur.' 'WARN'; return }
    $browserExe = Get-BastosBrowserExecutable -BrowserId $browser.Id
    if ($browserExe) {
        Show-BastosStage "$($browser.DisplayName) est déjà installé"
        Write-BastosAfterInstallLog "Navigateur déjà présent : $browserExe" 'OK'
    } else {
        Show-BastosStage "Installation de $($browser.DisplayName)"
        Install-BastosWingetPackage -Id $browser.WingetId -DisplayName $browser.DisplayName
        $browserExe = Get-BastosBrowserExecutable -BrowserId $browser.Id
    }
    if (-not $browserExe) { throw "Le navigateur $($browser.DisplayName) n'a pas pu être vérifié après installation. Edge est conservé." }
    $selectionPath = Join-Path $stateRoot 'Browser-Selection.json'
    [IO.File]::WriteAllText($selectionPath,($browser | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Write-BastosAfterInstallLog "Navigateur vérifié : $browserExe" 'OK'

    $edgeScript = Join-Path $root 'Remove-BASTOS-Edge.ps1'
    if ($browser.RemoveEdge -and (Test-Path -LiteralPath $edgeScript)) {
        Show-BastosStage 'Retrait de Microsoft Edge (cette étape peut durer plusieurs minutes)'
        $edgeResultPath = Join-Path $stateRoot 'Edge-Machine-Removal.json'
        $edgeResult = & $edgeScript -WaitForBrowserSeconds 0 -SelectionPath $selectionPath -ResultPath $edgeResultPath
        if ($edgeResult.Success) { Write-BastosAfterInstallLog 'Microsoft Edge retiré; WebView2 conservé.' 'OK' }
        else { Write-BastosAfterInstallLog ("Retrait Edge incomplet : {0}" -f ($edgeResult.Errors -join '; ')) 'WARN' }
    } else {
        Write-BastosAfterInstallLog 'Microsoft Edge conservé selon le choix de utilisateur.' 'OK'
    }

    $installEssentials = [Windows.Forms.MessageBox]::Show('Installer automatiquement 7-Zip, Notepad++ et tous les runtimes Visual C++ ?','Logiciels essentiels','YesNo','Question')
    if ($installEssentials -eq [Windows.Forms.DialogResult]::Yes) {
        Show-BastosStage 'Installation des logiciels essentiels'
        foreach ($package in @(
            @{ Id='7zip.7zip'; Name='7-Zip' },
            @{ Id='Notepad++.Notepad++'; Name='Notepad++' },
            @{ Id='abbodi1406.vcredist'; Name='Visual C++ Runtimes All-in-One' }
        )) { Install-BastosWingetPackage -Id $package.Id -DisplayName $package.Name }
    }

    Write-BastosAfterInstallLog 'Assistant terminé.' 'OK'
    [Windows.Forms.MessageBox]::Show("Configuration après installation terminée.`r`n`r`nJournal : $logPath",'BASTOS','OK','Information') | Out-Null
}
catch {
    Write-BastosAfterInstallLog $_.Exception.Message 'ERROR'
    [Windows.Forms.MessageBox]::Show("La configuration s'est arrêtée :`r`n$($_.Exception.Message)`r`n`r`nMicrosoft Edge est conservé si le nouveau navigateur ne peut pas être vérifié.",'BASTOS','OK','Error') | Out-Null
    exit 1
}
