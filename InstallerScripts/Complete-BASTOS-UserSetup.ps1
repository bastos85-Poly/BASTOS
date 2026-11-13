[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$MaxAttempts = 8,

    [ValidateRange(0, 180)]
    [int]$WingetWaitSeconds = 90,

    [switch]$MarkProfileComplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Le chemin des modules peut contenir PowerShell 7 avant Windows PowerShell.
# Charger explicitement la version native pour verifier les signatures Microsoft.
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop

$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$removalOptions = [pscustomobject]@{RemoveOneDrive=$true;DisableConsumerContent=$true}
$removalOptionsPath = Join-Path $profileRoot 'BASTOS-Removal-Options.json'
if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
    $removalOptions = Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$userDataRoot = Join-Path $env:LOCALAPPDATA 'BASTOS'
$logRoot = Join-Path $userDataRoot 'Logs'
$statePath = Join-Path $userDataRoot 'UserSetup-State.json'
$completeMarker = Join-Path $userDataRoot 'UserSetup-Complete.ok'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'BASTOS-Complete-UserSetup'
$scriptPath = $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Write-BastosUserSetupLog {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','OK','WARN','ERROR')][string]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Add-Content -LiteralPath (Join-Path $logRoot 'User-Setup.log') -Value $line -Encoding UTF8
}

function Get-BastosSelectionNames {
    $selectionPath = Join-Path $profileRoot 'Remove-Appx-Selection.txt'
    $defaultPath = Join-Path $profileRoot 'Remove-Appx.txt'
    $path = if (Test-Path -LiteralPath $selectionPath -PathType Leaf) { $selectionPath } else { $defaultPath }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique)
}

function Remove-BastosSelectedUserAppx {
    $names = @(Get-BastosSelectionNames)
    if ($names.Count -eq 0) {
        Write-BastosUserSetupLog 'Aucune application Appx selectionnee pour retrait.' 'OK'
        return $true
    }

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) -or -not (Get-Command Remove-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-BastosUserSetupLog 'Les commandes Appx utilisateur sont indisponibles.' 'ERROR'
        return $false
    }

    try {
        for ($pass = 1; $pass -le 3; $pass++) {
            $installed = @(Get-AppxPackage -ErrorAction Stop | Where-Object { [string]$_.Name -in $names })
            foreach ($package in $installed) {
                try {
                    Write-BastosUserSetupLog ("Retrait Appx utilisateur, passe {0} : {1}" -f $pass,$package.Name)
                    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop | Out-Null
                } catch {
                    Write-BastosUserSetupLog ("Echec du retrait Appx {0} : {1}" -f $package.Name,$_.Exception.Message) 'WARN'
                }
            }
            if ($pass -lt 3) { Start-Sleep -Seconds 4 }
        }

        $remaining = @(Get-AppxPackage -ErrorAction Stop | Where-Object { [string]$_.Name -in $names } | Select-Object -ExpandProperty Name -Unique)
        if ($remaining.Count -gt 0) {
            Write-BastosUserSetupLog ("Appx encore enregistrees pour utilisateur : {0}" -f ($remaining -join ', ')) 'ERROR'
            return $false
        }
        Write-BastosUserSetupLog ("Applications Appx selectionnees absentes du profil utilisateur : {0}" -f $names.Count) 'OK'
        return $true
    } catch {
        Write-BastosUserSetupLog ("Verification Appx utilisateur impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Remove-BastosUserOneDrive {
    if (-not $removalOptions.RemoveOneDrive) {
        Write-BastosUserSetupLog 'OneDrive conserve selon le choix fait pendant la creation ISO.' 'OK'
        return $true
    }
    $worker = Join-Path $profileRoot 'Remove-BASTOS-OneDrive.ps1'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
        Write-BastosUserSetupLog 'Module de desinstallation OneDrive absent.' 'ERROR'
        return $false
    }

    try {
        $resultPath = Join-Path $userDataRoot 'OneDrive-Removal.json'
        # Retire le client et ses enregistrements sans supprimer les fichiers personnels synchronises.
        $result = & $worker -Scope User -TimeoutSeconds 90 -ResultPath $resultPath
        if ([bool]$result.Success) {
            Write-BastosUserSetupLog 'Le client OneDrive et ses enregistrements propres sont absents; les fichiers personnels synchronises ont ete conserves.' 'OK'
            return $true
        }
        Write-BastosUserSetupLog ("OneDrive reste present : {0}" -f ((@($result.Remaining) + @($result.Errors)) -join ' | ')) 'ERROR'
        return $false
    } catch {
        Write-BastosUserSetupLog ("Desinstallation OneDrive utilisateur impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Set-BastosMinimalStartLayout {
    try {
        $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
        $registeredLayoutPath = [Environment]::ExpandEnvironmentVariables([string](Get-ItemPropertyValue -LiteralPath $policyPath -Name ConfigureStartPinsJSON -ErrorAction Stop))
        $initialLayoutPath = Join-Path $profileRoot 'LayoutModification.json'
        $persistentLayoutPath = Join-Path $profileRoot 'State\StartPins-Active.json'
        if ($registeredLayoutPath -notin @($initialLayoutPath, $persistentLayoutPath) -or
            -not (Test-Path -LiteralPath $registeredLayoutPath -PathType Leaf)) {
            throw "Disposition du menu Demarrer inattendue ou absente : $registeredLayoutPath"
        }
        $layout = Get-Content -LiteralPath $registeredLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedApplyOnce = $registeredLayoutPath -eq $initialLayoutPath
        if ([bool]$layout.applyOnce -ne $expectedApplyOnce -or @($layout.pinnedList).Count -ne 3 -or
            [string]$layout.pinnedList[0].desktopAppLink -notlike '*\BASTOS.lnk' -or
            [string]$layout.pinnedList[1].desktopAppId -ne 'Microsoft.Windows.Explorer' -or
            [string]$layout.pinnedList[2].packagedAppId -ne 'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel') {
            throw 'La disposition BASTOS doit contenir BASTOS, Explorateur et Parametres avec le mode de persistance attendu.'
        }
        if ([int](Get-ItemPropertyValue -LiteralPath $policyPath -Name ConfigureStartPins -ErrorAction Stop) -ne 1 -or
            $registeredLayoutPath -notin @($initialLayoutPath, $persistentLayoutPath)) {
            throw 'La strategie Windows ConfigureStartPins ne correspond pas au profil BASTOS.'
        }
        if ([int](Get-ItemPropertyValue -LiteralPath $policyPath -Name HideRecommendedSection -ErrorAction Stop) -ne 1) {
            throw 'Le masquage des recommandations du menu Demarrer n est pas actif.'
        }
        Write-BastosUserSetupLog 'Profil initial du menu Demarrer enregistre et verifie : BASTOS, Explorateur et Parametres.' 'OK'
        return $true
    } catch {
        Write-BastosUserSetupLog ("Profil du menu Demarrer non verifie : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Set-BastosKeyboardRegistryConvergence {
    param([Parameter(Mandatory)][string]$WindowsLocale,[Parameter(Mandatory)][string]$InputLocale)
    $layoutId = ($InputLocale -split ':')[1].ToUpperInvariant()
    $preloadKey = 'HKCU:\Keyboard Layout\Preload'
    $substitutesKey = 'HKCU:\Keyboard Layout\Substitutes'
    $userProfileKey = 'HKCU:\Control Panel\International\User Profile'
    $languageProfileKey = Join-Path $userProfileKey $WindowsLocale
    foreach ($path in @($preloadKey,$substitutesKey,$userProfileKey,$languageProfileKey)) { New-Item -Path $path -Force | Out-Null }

    New-ItemProperty -LiteralPath $userProfileKey -Name 'Languages' -PropertyType MultiString -Value @($WindowsLocale) -Force | Out-Null
    New-ItemProperty -LiteralPath $userProfileKey -Name 'InputMethodOverride' -PropertyType String -Value $InputLocale.ToUpperInvariant() -Force | Out-Null
    @((Get-ItemProperty -LiteralPath $languageProfileKey).PSObject.Properties | Where-Object Name -match '^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$') |
        ForEach-Object { Remove-ItemProperty -LiteralPath $languageProfileKey -Name $_.Name -Force -ErrorAction SilentlyContinue }
    New-ItemProperty -LiteralPath $languageProfileKey -Name $InputLocale.ToUpperInvariant() -PropertyType DWord -Value 1 -Force | Out-Null

    @((Get-ItemProperty -LiteralPath $preloadKey).PSObject.Properties | Where-Object Name -match '^\d+$') |
        ForEach-Object { Remove-ItemProperty -LiteralPath $preloadKey -Name $_.Name -Force -ErrorAction SilentlyContinue }
    @((Get-ItemProperty -LiteralPath $substitutesKey).PSObject.Properties | Where-Object Name -notmatch '^PS') |
        ForEach-Object { Remove-ItemProperty -LiteralPath $substitutesKey -Name $_.Name -Force -ErrorAction SilentlyContinue }
    New-ItemProperty -LiteralPath $preloadKey -Name '1' -PropertyType String -Value $layoutId -Force | Out-Null
}

function Invoke-BastosRegionalCmdletsBounded {
    param([Parameter(Mandatory)][string]$WindowsLocale,[Parameter(Mandatory)][string]$InputLocale,[ValidateRange(5,60)][int]$TimeoutSeconds=20)
    $escapedLocale=$WindowsLocale.Replace("'","''");$escapedInput=$InputLocale.Replace("'","''")
    $command=@"
`$ErrorActionPreference='Stop'
`$list=New-WinUserLanguageList -Language '$escapedLocale'
foreach(`$language in `$list){`$language.InputMethodTips.Clear()}
[void]`$list[0].InputMethodTips.Add('$escapedInput'.ToUpperInvariant())
Set-WinUserLanguageList -LanguageList `$list -Force
Set-WinDefaultInputMethodOverride -InputTip '$escapedInput'.ToUpperInvariant()
Set-Culture -CultureInfo '$escapedLocale'
if(Get-Command Set-WinUILanguageOverride -ErrorAction SilentlyContinue){Set-WinUILanguageOverride -Language '$escapedLocale'}
"@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -PassThru -WindowStyle Hidden
    if(-not $process.WaitForExit($TimeoutSeconds*1000)){
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Write-BastosUserSetupLog "Service linguistique Windows lent : délai de $TimeoutSeconds secondes atteint; le verrouillage direct reste appliqué." 'WARN'
        return $false
    }
    if($process.ExitCode -ne 0){Write-BastosUserSetupLog "Commandes linguistiques Windows terminées avec le code $($process.ExitCode); le verrouillage direct reste appliqué." 'WARN';return $false}
    return $true
}

function Set-BastosActiveKeyboardLayout {
    param([Parameter(Mandatory)][string]$InputLocale)
    $layoutId=($InputLocale -split ':')[1].ToUpperInvariant()
    if(-not('Bastos.KeyboardSession' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Bastos {
  public static class KeyboardSession {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr LoadKeyboardLayout(string id, uint flags);
    [DllImport("user32.dll")] public static extern bool UnloadKeyboardLayout(IntPtr layout);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int count, IntPtr[] layouts);
  }
}
'@
    }
    $loaded=[Bastos.KeyboardSession]::LoadKeyboardLayout($layoutId,0x0000000B)
    if($loaded -eq [IntPtr]::Zero){throw "Windows refuse de charger la disposition $layoutId."}
    $foreground=[Bastos.KeyboardSession]::GetForegroundWindow()
    if($foreground -ne [IntPtr]::Zero){[void][Bastos.KeyboardSession]::PostMessage($foreground,0x0050,[IntPtr]::Zero,$loaded)}
    $count=[Bastos.KeyboardSession]::GetKeyboardLayoutList(0,$null);$layouts=New-Object IntPtr[] $count
    [void][Bastos.KeyboardSession]::GetKeyboardLayoutList($count,$layouts)
    $wantedPhysical=[Convert]::ToInt32($layoutId.Substring(4,4),16)
    foreach($candidate in $layouts){$raw=$candidate.ToInt64()-band 0xFFFFFFFF;$physical=($raw -shr 16)-band 0xFFFF;if($physical -ne $wantedPhysical){[void][Bastos.KeyboardSession]::UnloadKeyboardLayout($candidate)}}
    if($foreground -ne [IntPtr]::Zero){[void][Bastos.KeyboardSession]::PostMessage($foreground,0x0050,[IntPtr]::Zero,$loaded)}
}

function Set-BastosRegionalSelection {
    $selectionPath = Join-Path $profileRoot 'Regional-Selection.json'
    if (-not (Test-Path -LiteralPath $selectionPath -PathType Leaf)) {
        Write-BastosUserSetupLog 'Selection regionale absente : aucune modification regionale supplementaire.' 'WARN'
        return $true
    }

    try {
        $selection = Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $windowsLocale = [string]$selection.WindowsLocale
        $inputLocale = [string]$selection.InputLocale
        if ($windowsLocale -notmatch '^[a-z]{2,3}(?:-[A-Za-z]{2,4}){1,2}$' -or $inputLocale -notmatch '^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$') {
            throw 'La selection regionale integree est invalide.'
        }

        # Le verrouillage direct est écrit avant et après les cmdlets. Celles-ci
        # sont isolées avec un délai maximal pour ne plus bloquer la première connexion.
        Set-BastosKeyboardRegistryConvergence -WindowsLocale $windowsLocale -InputLocale $inputLocale
        [void](Invoke-BastosRegionalCmdletsBounded -WindowsLocale $windowsLocale -InputLocale $inputLocale -TimeoutSeconds 20)
        Set-BastosKeyboardRegistryConvergence -WindowsLocale $windowsLocale -InputLocale $inputLocale
        Set-BastosActiveKeyboardLayout -InputLocale $inputLocale

        $actualLanguageCollection = Get-WinUserLanguageList
        $actualList = @()
        for ($index = 0; $index -lt $actualLanguageCollection.Count; $index++) { $actualList += $actualLanguageCollection[$index] }
        $actualTips = @(
            foreach ($language in $actualList) {
                foreach ($tip in @($language.InputMethodTips)) { [string]$tip }
            }
        )
        $actualTips = @($actualTips | Select-Object -Unique)
        $overrideTip = [string](Get-ItemPropertyValue -LiteralPath 'HKCU:\Control Panel\International\User Profile' -Name 'InputMethodOverride' -ErrorAction SilentlyContinue)
        $uiOverride = if (Get-Command Get-WinUILanguageOverride -ErrorAction SilentlyContinue) { [string](Get-WinUILanguageOverride) } else { $windowsLocale }
        if ([string]::IsNullOrWhiteSpace($uiOverride)) { $uiOverride = $windowsLocale }
        $expectedTip = $inputLocale.ToUpperInvariant()
        if ($actualList.Count -ne 1 -or [string]$actualList[0].LanguageTag -ine $windowsLocale -or $uiOverride -ine $windowsLocale -or
            $actualTips.Count -ne 1 -or [string]$actualTips[0] -ine $expectedTip -or $overrideTip -ine $expectedTip) {
            throw "Windows n a pas conserve uniquement le clavier demande ($expectedTip)."
        }

        Write-BastosUserSetupLog ("Langue utilisateur {0}, clavier unique {1}." -f $windowsLocale,$expectedTip) 'OK'
        return $true
    } catch {
        Write-BastosUserSetupLog ("Application langue/clavier impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Set-BastosUserPolicyConvergence {
    try {
        if ($removalOptions.DisableConsumerContent) {
            $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            if (-not (Test-Path -LiteralPath $contentPath)) { New-Item -Path $contentPath -Force | Out-Null }
            $disabledValues = @(
            'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
            'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','RotatingLockScreenEnabled',
            'RotatingLockScreenOverlayEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
            'SubscribedContent-310091Enabled','SubscribedContent-310092Enabled',
            'SubscribedContent-338380Enabled','SubscribedContent-338381Enabled',
            'SubscribedContent-338387Enabled','SubscribedContent-338388Enabled',
            'SubscribedContent-338389Enabled','SubscribedContent-353694Enabled',
            'SubscribedContent-353696Enabled','SystemPaneSuggestionsEnabled'
            )
            foreach ($name in $disabledValues) {
                New-ItemProperty -Path $contentPath -Name $name -PropertyType DWord -Value 0 -Force | Out-Null
            }
        }
        if ($removalOptions.RemoveOneDrive) {
            foreach ($name in @('OneDrive','OneDriveSetup')) {
                Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $name -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
        if ($removalOptions.DisableConsumerContent) {
            $incorrect = @($disabledValues | Where-Object {
                [int](Get-ItemPropertyValue -LiteralPath $contentPath -Name $_ -ErrorAction Stop) -ne 0
            })
            if ($incorrect.Count -gt 0) { throw "Valeurs utilisateur non appliquees : $($incorrect -join ', ')." }
        }
        Write-BastosUserSetupLog 'Choix de suppression ISO appliques aux strategies utilisateur.' 'OK'
        return $true
    } catch {
        Write-BastosUserSetupLog ("Convergence des strategies utilisateur impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Get-BastosBrowserExecutable {
    param([Parameter(Mandatory)][ValidateSet('Edge','Chrome','Brave','Firefox','FirefoxNightly','Opera','Vivaldi')][string]$BrowserId)
    $candidates = switch ($BrowserId) {
        'Edge' { @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
        'Chrome' { @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") }
        'Brave' { @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe") }
        'Firefox' { @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe") }
        'FirefoxNightly' { @("$env:ProgramFiles\Firefox Nightly\firefox.exe", "${env:ProgramFiles(x86)}\Firefox Nightly\firefox.exe", "$env:LOCALAPPDATA\Firefox Nightly\firefox.exe") }
        'Opera' { @("$env:LOCALAPPDATA\Programs\Opera\opera.exe", "$env:ProgramFiles\Opera\launcher.exe", "${env:ProgramFiles(x86)}\Opera\launcher.exe") }
        'Vivaldi' { @("$env:ProgramFiles\Vivaldi\Application\vivaldi.exe", "${env:ProgramFiles(x86)}\Vivaldi\Application\vivaldi.exe", "$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe") }
    }
    if($BrowserId -eq 'FirefoxNightly'){
        foreach($package in @(Get-AppxPackage -Name '*Firefox*Nightly*' -ErrorAction SilentlyContinue)){
            if($package.InstallLocation){$candidates+=@(Get-ChildItem -LiteralPath $package.InstallLocation -Filter 'firefox.exe' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName -First 1)}
        }
    }
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Get-BastosWingetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { return [string]$command.Source }
    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $aliasPath -PathType Leaf) { return $aliasPath }
    return $null
}

function Request-BastosWingetRegistration {
    if (Get-BastosWingetPath) { return }
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop | Out-Null
        Write-BastosUserSetupLog 'Enregistrement de Microsoft App Installer demande pour rendre WinGet disponible.'
    } catch {
        Write-BastosUserSetupLog ("Enregistrement immediat de WinGet non disponible : {0}" -f $_.Exception.Message) 'WARN'
    }
}

function New-BastosOfficialBrowserShortcut {
    param([Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][string]$OfficialUri)
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { return }
    $shortcutPath = Join-Path $desktop ("Installer {0}.url" -f $DisplayName)
    $shortcutContent = "[InternetShortcut]`r`nURL=$OfficialUri`r`n"
    [IO.File]::WriteAllText($shortcutPath, $shortcutContent, [Text.UTF8Encoding]::new($true))
}

function New-BastosBrowserDesktopShortcut {
    param([Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][string]$ExecutablePath)
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { return }
    try {
        $shortcutPath = Join-Path $desktop ("{0}.lnk" -f $DisplayName)
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ExecutablePath
        $shortcut.WorkingDirectory = Split-Path -Parent $ExecutablePath
        $shortcut.Description = "$DisplayName - navigateur choisi dans ISO BASTOS"
        $shortcut.IconLocation = "$ExecutablePath,0"
        $shortcut.Save()
    } catch {
        Write-BastosUserSetupLog ("Navigateur installe, raccourci Bureau non cree : {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Install-BastosSelectedBrowser {
    param([ValidateRange(0,180)][int]$WaitSeconds)

    $selectionPath = Join-Path $profileRoot 'Browser-Selection.json'
    if (-not (Test-Path -LiteralPath $selectionPath -PathType Leaf)) {
        Write-BastosUserSetupLog 'Selection du navigateur absente : Microsoft Edge reste disponible.' 'WARN'
        return $true
    }
    $browser = $null
    $browserCatalog = @{
        Edge=[pscustomobject]@{ DisplayName='Microsoft Edge'; WingetId='Microsoft.Edge'; OfficialUri='https://www.microsoft.com/edge' }
        Chrome=[pscustomobject]@{ DisplayName='Google Chrome'; WingetId='Google.Chrome'; OfficialUri='https://www.google.com/chrome/' }
        Brave=[pscustomobject]@{ DisplayName='Brave'; WingetId='Brave.Brave'; OfficialUri='https://brave.com/download/' }
        Firefox=[pscustomobject]@{ DisplayName='Mozilla Firefox'; WingetId='Mozilla.Firefox'; OfficialUri='https://www.mozilla.org/firefox/new/' }
        FirefoxNightly=[pscustomobject]@{ DisplayName='Mozilla Firefox Nightly'; WingetId='Mozilla.Firefox.Nightly.MSIX'; OfficialUri='https://nightly.mozfr.org/' }
        Opera=[pscustomobject]@{ DisplayName='Opera'; WingetId='Opera.Opera'; OfficialUri='https://www.opera.com/download' }
        Vivaldi=[pscustomobject]@{ DisplayName='Vivaldi'; WingetId='Vivaldi.Vivaldi'; OfficialUri='https://vivaldi.com/download/' }
    }

    try {
        $selection = Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $browserId = [string]$selection.Id
        if ($browserId -eq 'None') {
            Write-BastosUserSetupLog 'Aucun navigateur choisi pendant la creation de ISO : Microsoft Edge reste disponible jusqu au choix effectue dans BASTOS.' 'OK'
            return $true
        }
        if (-not $browserCatalog.ContainsKey($browserId)) { throw "Navigateur integre inconnu : $browserId" }
        $browser = $browserCatalog[$browserId]
        $browserExe = Get-BastosBrowserExecutable -BrowserId $browserId
        if ($browserExe) {
            $desktop = [Environment]::GetFolderPath('Desktop')
            if ($desktop) { Remove-Item -LiteralPath (Join-Path $desktop ("Installer {0}.url" -f $browser.DisplayName)) -Force -ErrorAction SilentlyContinue }
            if ($browserId -ne 'Edge') { New-BastosBrowserDesktopShortcut -DisplayName $browser.DisplayName -ExecutablePath $browserExe }
            Write-BastosUserSetupLog ("Navigateur choisi detecte : {0} ({1})." -f $browser.DisplayName,$browserExe) 'OK'
            return $true
        }

        Request-BastosWingetRegistration
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        $winget = Get-BastosWingetPath
        while (-not $winget -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $winget = Get-BastosWingetPath
        }
        if (-not $winget) {
            New-BastosOfficialBrowserShortcut -DisplayName $browser.DisplayName -OfficialUri $browser.OfficialUri
            Write-BastosUserSetupLog ("WinGet indisponible; installation de {0} reportee." -f $browser.DisplayName) 'WARN'
            return $false
        }

        Write-BastosUserSetupLog ("Installation WinGet du navigateur choisi : {0}." -f $browser.DisplayName)
        $arguments = 'install --id "{0}" --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --no-upgrade' -f $browser.WingetId
        $process = Start-Process -FilePath $winget -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
        if (-not $process.WaitForExit(300000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Installation WinGet interrompue apres cinq minutes pour $($browser.DisplayName)."
        }
        if ($process.ExitCode -ne 0) { throw "WinGet a retourne le code $($process.ExitCode) pour $($browser.DisplayName)." }

        $detectDeadline = (Get-Date).AddSeconds(45)
        do {
            $browserExe = Get-BastosBrowserExecutable -BrowserId $browserId
            if ($browserExe) { break }
            Start-Sleep -Seconds 3
        } while ((Get-Date) -lt $detectDeadline)
        if (-not $browserExe) { throw "WinGet a termine sans rendre $($browser.DisplayName) detectable." }

        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) { Remove-Item -LiteralPath (Join-Path $desktop ("Installer {0}.url" -f $browser.DisplayName)) -Force -ErrorAction SilentlyContinue }
        if ($browserId -ne 'Edge') { New-BastosBrowserDesktopShortcut -DisplayName $browser.DisplayName -ExecutablePath $browserExe }
        Write-BastosUserSetupLog ("Navigateur choisi installe et verifie : {0} ({1})." -f $browser.DisplayName,$browserExe) 'OK'
        return $true
    } catch {
        try {
            if ($browser -and $browser.DisplayName -and $browser.OfficialUri) {
                New-BastosOfficialBrowserShortcut -DisplayName $browser.DisplayName -OfficialUri $browser.OfficialUri
            }
        } catch {}
        Write-BastosUserSetupLog ("Installation du navigateur non convergee : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Test-BastosConditionalEdgeRemoval {
    param([bool]$BrowserReady)
    $selectionPath = Join-Path $profileRoot 'Browser-Selection.json'
    if (-not (Test-Path -LiteralPath $selectionPath -PathType Leaf)) { return $true }
    try {
        $selection = Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $browserId = [string]$selection.Id
        $removeEdge=$selection.PSObject.Properties['RemoveEdge'] -and [bool]$selection.RemoveEdge
        if ($browserId -in @('None','Edge') -or -not $removeEdge) {
            Write-BastosUserSetupLog 'Microsoft Edge conserve selon le choix de reinstallation.' 'OK'
            return $true
        }
        if (-not $BrowserReady) { return $false }
        $worker = Join-Path $profileRoot 'Remove-BASTOS-Edge.ps1'
        if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
            Write-BastosUserSetupLog 'Module de verification Edge absent.' 'ERROR'
            return $false
        }
        try { Start-ScheduledTask -TaskName 'BASTOS-Remove-Edge' -ErrorAction SilentlyContinue } catch {}
        $deadline = (Get-Date).AddSeconds(120)
        do {
            $audit = & $worker -AuditOnly -ResultPath (Join-Path $userDataRoot 'Edge-Removal-Audit.json')
            if ([bool]$audit.Success) {
                Write-BastosUserSetupLog ("Navigateur choisi verifie et Microsoft Edge absent; WebView2 conserve : {0}." -f $browserId) 'OK'
                return $true
            }
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 5
        } while ($true)
        Write-BastosUserSetupLog 'Microsoft Edge attend encore la passe SYSTEM apres verification du navigateur choisi.' 'ERROR'
        return $false
    } catch {
        Write-BastosUserSetupLog ("Verification du retrait conditionnel Edge impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Start-BastosSelectedNiniteOnce {
    $ninitePath=Join-Path $profileRoot 'Tools\Ninite\Ninite.exe'
    if(-not(Test-Path -LiteralPath $ninitePath -PathType Leaf)){
        Write-BastosUserSetupLog 'Aucune sélection Ninite prévue pour ce profil.' 'OK'
        return $true
    }
    try{
        $signature=Get-AuthenticodeSignature -LiteralPath $ninitePath
        $subject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}
        if($signature.Status -ne 'Valid' -or $subject -notmatch '(?i)CN=Secure By Design Inc\.') { throw 'La signature officielle Ninite est absente ou invalide.' }
        $hash=(Get-FileHash -LiteralPath $ninitePath -Algorithm SHA256).Hash
        $marker=Join-Path $userDataRoot ("Ninite-Launched-$hash.ok")
        if(Test-Path -LiteralPath $marker -PathType Leaf){
            Write-BastosUserSetupLog 'La sélection Ninite de ce profil a déjà été lancée.' 'OK'
            return $true
        }
        Start-Process -FilePath $ninitePath -WorkingDirectory (Split-Path -Parent $ninitePath)|Out-Null
        [IO.File]::WriteAllText($marker,([datetime]::UtcNow.ToString('o')),[Text.UTF8Encoding]::new($false))
        Write-BastosUserSetupLog 'Sélection Ninite officielle lancée au premier Bureau.' 'OK'
        return $true
    }catch{
        Write-BastosUserSetupLog ("Lancement Ninite impossible : {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Register-BastosUserSetupRetry {
    if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    $command = 'powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -MaxAttempts {1} -WingetWaitSeconds 15 -MarkProfileComplete' -f $scriptPath,$MaxAttempts
    New-ItemProperty -Path $runKey -Name $runName -PropertyType String -Value $command -Force | Out-Null
}

function Remove-BastosUserSetupRetry {
    Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
}

$attempt = 1
$previousSessionId = $null
$currentSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $previousState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $attempt = [Math]::Max(1, [int]$previousState.Attempts + 1)
        if ($previousState.PSObject.Properties['SessionId']) { $previousSessionId = [int]$previousState.SessionId }
    } catch {
        $attempt = 1
    }
}
Remove-Item -LiteralPath $completeMarker -Force -ErrorAction SilentlyContinue
Write-BastosUserSetupLog ("Tentative de convergence utilisateur {0}/{1}." -f $attempt,$MaxAttempts)

$regionalReady = Set-BastosRegionalSelection
$userPolicyReady = Set-BastosUserPolicyConvergence
$appxReady = Remove-BastosSelectedUserAppx
$oneDriveReady = Remove-BastosUserOneDrive
# Configuration logicielle uniquement a la demande depuis l'interface BASTOS.
$browserReady = $true
$edgeReady = $true
$startLayoutReady = Set-BastosMinimalStartLayout
$profileCoreReady = (-not $MarkProfileComplete) -or (Test-Path -LiteralPath (Join-Path $profileRoot 'UserProfileCoreApplied.ok') -PathType Leaf)
$success = $regionalReady -and $userPolicyReady -and $appxReady -and $oneDriveReady -and $browserReady -and $edgeReady -and $startLayoutReady -and $profileCoreReady
$failures = @()
if (-not $regionalReady) { $failures += 'langue/clavier' }
if (-not $userPolicyReady) { $failures += 'strategies utilisateur' }
if (-not $appxReady) { $failures += 'applications Appx' }
if (-not $oneDriveReady) { $failures += 'OneDrive' }
if (-not $browserReady) { $failures += 'navigateur' }
if (-not $edgeReady) { $failures += 'retrait conditionnel Edge' }
if (-not $startLayoutReady) { $failures += 'menu Démarrer' }
if (-not $profileCoreReady) { $failures += 'profil utilisateur principal' }

if ($success) {
    if ($null -eq $previousSessionId -or $previousSessionId -eq $currentSessionId) {
        Register-BastosUserSetupRetry
        Write-BastosUserSetupLog 'Premiere convergence reussie; verification durable programmee a la prochaine ouverture de session.' 'OK'
    } else {
        Remove-BastosUserSetupRetry
        New-Item -ItemType File -Path $completeMarker -Force | Out-Null
        if ($MarkProfileComplete) {
            $coreMarker = Join-Path $profileRoot 'UserProfileCoreApplied.ok'
            if (Test-Path -LiteralPath $coreMarker -PathType Leaf) {
                try { New-Item -ItemType File -Path (Join-Path $profileRoot 'UserProfileApplied.ok') -Force | Out-Null } catch {
                    Write-BastosUserSetupLog ("Convergence terminee, mais marqueur ProgramData non actualise : {0}" -f $_.Exception.Message) 'WARN'
                }
            } else {
                Write-BastosUserSetupLog 'Convergence terminee, mais le profil utilisateur principal ne possede pas son marqueur de verification.' 'ERROR'
            }
        }
        Write-BastosUserSetupLog 'Convergence utilisateur confirmee dans une nouvelle session.' 'OK'
    }
} elseif ($attempt -lt $MaxAttempts) {
    Register-BastosUserSetupRetry
    Write-BastosUserSetupLog ("Nouvelle tentative automatique enregistree; elements restants : {0}." -f ($failures -join ', ')) 'WARN'
} else {
    Remove-BastosUserSetupRetry
    Write-BastosUserSetupLog ("Limite de tentatives atteinte; elements non converges : {0}." -f ($failures -join ', ')) 'ERROR'
}

$state = [pscustomobject]@{
    Attempts = $attempt
    SessionId = $currentSessionId
    VerificationPending = [bool]($success -and ($null -eq $previousSessionId -or $previousSessionId -eq $currentSessionId))
    MaxAttempts = $MaxAttempts
    Success = $success
    RegionalReady = $regionalReady
    UserPolicyReady = $userPolicyReady
    AppxReady = $appxReady
    OneDriveReady = $oneDriveReady
    BrowserReady = $browserReady
    EdgeReady = $edgeReady
    StartLayoutReady = $startLayoutReady
    ProfileCoreReady = $profileCoreReady
    Failures = $failures
    UpdatedUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
if (-not $success) {
    throw ("Convergence utilisateur BASTOS incomplete : {0}." -f ($failures -join ', '))
}
return $state
