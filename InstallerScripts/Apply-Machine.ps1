[CmdletBinding()]
param(
    [switch]$SkipUserRunOnce,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profileRoot = 'C:\ProgramData\BASTOS-ISO'
$removalOptions = [pscustomobject]@{RemoveOneDrive=$true;DisableConsumerContent=$true}
$removalOptionsPath = Join-Path $profileRoot 'BASTOS-Removal-Options.json'
if (Test-Path -LiteralPath $removalOptionsPath -PathType Leaf) {
    $removalOptions = Get-Content -LiteralPath $removalOptionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$logRoot = Join-Path $profileRoot 'Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Start-Transcript -Path (Join-Path $logRoot 'Apply-Machine.log') -Append | Out-Null
$machineMarker = Join-Path $profileRoot 'MachineProfileApplied.ok'

function Get-BastosRecoveryRootLocal {
    $modulePath = Join-Path $profileRoot 'BASTOS-Architecture.psm1'
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
        Import-Module $modulePath -Force
        return Get-BastosRecoveryRoot
    }
    $volumes = @(Get-Volume -FileSystemLabel 'BASTOS_RECOVERY' -ErrorAction SilentlyContinue | Where-Object DriveLetter)
    if ($volumes.Count -ne 1) { throw 'Une unique partition BASTOS_RECOVERY montee est requise.' }
    return ('{0}:\' -f $volumes[0].DriveLetter)
}
function Reset-BastosOneTimeBootMenu {
    try {
        $bcdedit = Join-Path $env:SystemRoot 'System32\bcdedit.exe'
        & $bcdedit /set '{bootmgr}' displaybootmenu no | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'displaybootmenu no a echoue.' }
        & $bcdedit /timeout 0 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'timeout 0 a echoue.' }
        $bootIdPath = Join-Path (Get-BastosRecoveryRootLocal) 'BASTOS-BOOT-ID.txt'
        if (Test-Path -LiteralPath $bootIdPath -PathType Leaf) {
            $bootId = (Get-Content -LiteralPath $bootIdPath -Raw).Trim()
            if ($bootId -match '^\{[0-9a-fA-F-]{36}\}$') {
                & $bcdedit /displayorder $bootId /remove 2>&1 | Out-Null
            }
        }
        Write-Host 'Menu BASTOS desactive apres le demarrage unique.'
    } catch {
        Write-Warning "Nettoyage du menu BASTOS reporte : $($_.Exception.Message)"
    }
}
function Set-DwordValue {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-StringValue {
    param([string]$Path, [string]$Name, [string]$Value, [ValidateSet('String','ExpandString')][string]$Type='String')
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Set-BastosStartLayoutPolicy {
    $commonPrograms = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    $launcher = Join-Path $profileRoot 'Bastos.Native\BASTOS-Native.exe'
    if (Test-Path -LiteralPath $launcher -PathType Leaf) {
        New-Item -ItemType Directory -Path $commonPrograms -Force | Out-Null
        $commonShortcutPath = Join-Path $commonPrograms 'BASTOS.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($commonShortcutPath)
        $shortcut.TargetPath = $launcher
        $shortcut.WorkingDirectory = $profileRoot
        $shortcut.Description = 'BASTOS - maintenance, optimisations et pilotes officiels'
        $iconPath = Join-Path $profileRoot 'Assets\Bastos-App.ico'
        if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $shortcut.IconLocation = "$iconPath,0" }
        $shortcut.Save()
    }

    # Windows 11 25H2 applique cette disposition via PolicyManager. La strategie
    # applyOnce initialise les trois epingles sans bloquer les modifications
    # ulterieures de l'utilisateur.
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (-not (Test-Path -LiteralPath $policyPath)) { New-Item -Path $policyPath | Out-Null }
    $layoutPath = Join-Path $profileRoot 'LayoutModification.json'
    $activePath = Join-Path $profileRoot 'State\StartPins-Active.json'
    $registeredPath = [string](Get-ItemPropertyValue -LiteralPath $policyPath -Name ConfigureStartPinsJSON -ErrorAction SilentlyContinue)
    if ($registeredPath -eq $activePath -and (Test-Path -LiteralPath $activePath -PathType Leaf)) {
        $active = Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [bool]$active.applyOnce -and @($active.pinnedList).Count -eq 3) {
            $layoutPath = $activePath
            Write-Host 'Disposition personnalisee existante conservee.'
        }
    }
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) { throw "Disposition du menu Demarrer absente : $layoutPath" }
    $layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($layout.pinnedList).Count -ne 3) { throw 'La disposition du menu Demarrer doit contenir trois epingles.' }
    $layoutJson = $layout | ConvertTo-Json -Compress -Depth 6
    $provider = 'B5292708-1619-419B-9923-E5D9F3925E71'
    $currentPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
    $providerPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\$provider\default\Device\Start"
    # Get-ItemProperty may return no object on a fresh installation. With
    # StrictMode enabled, accessing a missing property aborts the whole phase.
    $winner = Get-ItemPropertyValue -LiteralPath $currentPath -Name ConfigureStartPins_WinningProvider -ErrorAction SilentlyContinue
    if ($winner -and $winner -ne $provider) { throw "Une autre gestion du menu Demarrer est active : $winner" }
    # Retirer uniquement l ancien pseudo-fournisseur BASTOS. PolicyManager est
    # interne a Windows et ne doit pas etre simule par des valeurs de registre.
    if (-not $winner -or $winner -eq $provider) {
        foreach ($name in @('ConfigureStartPins','ConfigureStartPins_ProviderSet','ConfigureStartPins_WinningProvider')) {
            Remove-ItemProperty -LiteralPath $currentPath -Name $name -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $providerPath) { Remove-Item -LiteralPath $providerPath -Recurse -Force }
    }
    # La strategie GPO utilise deux valeurs distinctes : un DWORD d activation
    # et le chemin du fichier JSON. Le contenu JSON direct est reserve au CSP.
    New-ItemProperty -LiteralPath $policyPath -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -LiteralPath $policyPath -Name ConfigureStartPinsJSON -PropertyType ExpandString -Value $layoutPath -Force | Out-Null
    foreach ($name in @('HideRecentlyAddedApps','HideRecommendedPersonalizedSites')) {
        Remove-ItemProperty -LiteralPath $policyPath -Name $name -Force -ErrorAction SilentlyContinue
    }
    $registeredLayoutPath = [Environment]::ExpandEnvironmentVariables([string](Get-ItemPropertyValue -LiteralPath $policyPath -Name ConfigureStartPinsJSON -ErrorAction Stop))
    if ([int](Get-ItemPropertyValue -LiteralPath $policyPath -Name ConfigureStartPins -ErrorAction Stop) -ne 1 -or
        $registeredLayoutPath -ne $layoutPath) { throw 'La strategie du menu Demarrer n a pas ete enregistree correctement.' }
    New-ItemProperty -LiteralPath $policyPath -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force | Out-Null
    Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoStartMenuMorePrograms -Force -ErrorAction SilentlyContinue
    Write-Host 'Menu Demarrer : BASTOS, Explorateur et Parametres; recommandations masquees; Toutes les applications visible; personnalisation autorisee.'
}

function Invoke-OneDriveUninstall {
    param([ValidateRange(10, 300)][int]$TimeoutSeconds = 45)
    $worker = Join-Path $profileRoot 'Remove-BASTOS-OneDrive.ps1'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
        Write-Warning 'Module OneDrive absent. La passe utilisateur reessaiera.'
        return
    }
    try {
        # En reparation d'un PC existant, le jeton eleve garde le profil de l'utilisateur et peut aussi retirer les DLL locales protegees.
        # Pendant l'installation ISO (SYSTEM), ce volet utilisateur vise uniquement systemprofile; la passe de premier Bureau traite le vrai compte.
        # Specialize s'execute sous SYSTEM : ne jamais tenter ici le volet utilisateur,
        # car USERPROFILE/LOCALAPPDATA peuvent etre absents. Complete-BASTOS-UserSetup.ps1
        # traite le vrai profil au premier Bureau avec -Scope User.
        $result = & $worker -Scope Machine -TimeoutSeconds $TimeoutSeconds -ResultPath (Join-Path $profileRoot 'OneDrive-Machine-Removal.json')
        if ([bool]$result.Success) {
            Write-Host 'OneDrive machine absent ou desinstalle et verifie.'
        } else {
            Write-Warning ("Desinstallation OneDrive machine incomplete : {0}. La passe utilisateur reessaiera." -f (@($result.Errors) -join ' | '))
        }
    } catch {
        Write-Warning "Desinstallation OneDrive machine ignoree : $($_.Exception.Message). BASTOS poursuit le profil machine."
    }
}

function Invoke-BastosSelectedAppxRemoval {
    $selectionList = Join-Path $profileRoot 'Remove-Appx-Selection.txt'
    $defaultList = Join-Path $profileRoot 'Remove-Appx.txt'
    $removeList = if (Test-Path -LiteralPath $selectionList -PathType Leaf) { $selectionList } else { $defaultList }
    if (-not (Test-Path -LiteralPath $removeList -PathType Leaf)) {
        Write-Warning 'Liste de retrait Appx absente : aucune application facultative retiree.'
        return
    }

    $names = @(Get-Content -LiteralPath $removeList -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique)
    if ($names.Count -eq 0) {
        Write-Host 'Aucune application Appx selectionnee pour retrait.'
        return
    }

    $errors = [Collections.Generic.List[string]]::new()
    try {
        foreach ($package in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { [string]$_.DisplayName -in $names })) {
            try {
                Write-Host "Retrait Appx provisionne pour tous les futurs profils : $($package.DisplayName)"
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
            } catch {
                $errors.Add(("Provisionnement {0}: {1}" -f $package.DisplayName,$_.Exception.Message))
            }
        }
    } catch {
        $errors.Add(("Lecture du provisionnement : {0}" -f $_.Exception.Message))
    }

    try {
        foreach ($package in @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { [string]$_.Name -in $names })) {
            try {
                Write-Host "Retrait Appx enregistre pour tous les utilisateurs : $($package.Name)"
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop | Out-Null
            } catch {
                $errors.Add(("Enregistrement {0}: {1}" -f $package.Name,$_.Exception.Message))
            }
        }
    } catch {
        $errors.Add(("Lecture des paquets enregistres : {0}" -f $_.Exception.Message))
    }

    $remainingProvisioned = @()
    $remainingRegistered = @()
    try { $remainingProvisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { [string]$_.DisplayName -in $names } | Select-Object -ExpandProperty DisplayName -Unique) } catch { $errors.Add($_.Exception.Message) }
    try { $remainingRegistered = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { [string]$_.Name -in $names } | Select-Object -ExpandProperty Name -Unique) } catch { $errors.Add($_.Exception.Message) }
    $success = $errors.Count -eq 0 -and $remainingProvisioned.Count -eq 0 -and $remainingRegistered.Count -eq 0
    $status = [pscustomobject]@{
        Success = $success
        SelectedCount = $names.Count
        RemainingProvisioned = $remainingProvisioned
        RemainingRegistered = $remainingRegistered
        Errors = @($errors)
        CheckedUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $profileRoot 'Appx-Machine-Removal.json'), ($status | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    if ($success) {
        Write-Host "Retrait Appx machine verifie : $($names.Count) selection(s) absente(s)."
    } else {
        Write-Warning ("Retrait Appx machine incomplet; la passe utilisateur reessaiera. Restants : {0}. Erreurs : {1}" -f ((@($remainingProvisioned) + @($remainingRegistered)) -join ', '),(@($errors) -join ' | '))
    }
}

try {
    if ((Test-Path -LiteralPath $machineMarker -PathType Leaf) -and -not $Force) {
        Write-Host 'Profil machine BASTOS deja applique; seconde execution ignoree.'
        return
    }
    Remove-Item -LiteralPath $machineMarker -Force -ErrorAction SilentlyContinue
    Reset-BastosOneTimeBootMenu
    Write-Host 'Application du profil machine PUBG-Stable...'

    # Applique d'abord les strategies critiques. Une operation facultative lente ne doit jamais les bloquer.
    if ($removalOptions.DisableConsumerContent) {
        Set-DwordValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        Set-DwordValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    }
    Set-DwordValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1
    # Empêche Windows Backup / le compte Microsoft de réimporter une ancienne
    # disposition clavier après le choix explicite effectué dans BASTOS.
    Set-DwordValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableLanguageSettingSync' 1
    # Empeche Windows de reprovisionner ou relancer le client de synchronisation OneDrive.
    if ($removalOptions.RemoveOneDrive) {
        Set-DwordValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    }
    # Retire une ancienne restriction BASTOS afin que Game Bar et Xbox restent entierement fonctionnels.
    Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Force -ErrorAction SilentlyContinue
    Set-BastosStartLayoutPolicy

    # La suppression de OneDrive est facultative et bornee pour ne jamais immobiliser Windows Setup.
    if ($removalOptions.RemoveOneDrive) { Invoke-OneDriveUninstall -TimeoutSeconds 45 }

    # Le navigateur et le retrait conditionnel d'Edge sont désormais lancés manuellement
    # depuis la rubrique Configuration après installation. Aucune tâche de connexion n'est créée.

    # Les trois plans sont fournis par l'executable, sans telechargement.
    $powerLauncher = Join-Path $profileRoot 'Bastos.Native\BASTOS-Native.exe'
    $powerSetup = Start-Process -FilePath $powerLauncher -ArgumentList @('--native-worker','power-install') -WindowStyle Hidden -Wait -PassThru
    if ($powerSetup.ExitCode -ne 0) { throw "Installation des plans Bastos en echec (code $($powerSetup.ExitCode))." }

    # Windows Equilibre est le profil de reference stable pour ce Ryzen X3D.
    & powercfg.exe /setactive SCHEME_BALANCED | Out-Null

    # Le RTL8125D de cette carte mère est plus stable sans EEE/Green Ethernet.
    # RSS reste actif et Interrupt Moderation n'est pas forcé dans le profil stable.
    $experimentScript = Join-Path $profileRoot 'Set-PUBG-Experiment.ps1'
    if (Test-Path -LiteralPath $experimentScript) {
        try {
            & $experimentScript -Mode NicStable -NoRestart -Quiet
        } catch {
            Write-Warning "Profil Realtek reporté après installation du pilote LAN : $($_.Exception.Message)"
        }
    }

    # Deuxieme passe machine : provisionnement et paquets deja enregistres sont tous deux controles.
    Invoke-BastosSelectedAppxRemoval

    # Apply-User est appelé une seule fois par FirstLogonCommands; aucun RunOnce de secours
    # n'est ajouté afin d'éviter une fenêtre PowerShell à chaque ouverture de session.

    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name)
    $gpu = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join '; '
    Write-Host "CPU detecte : $cpu"
    Write-Host "GPU detecte : $gpu"
    New-Item -ItemType File -Path $machineMarker -Force | Out-Null
}
finally {
    Stop-Transcript | Out-Null
}
