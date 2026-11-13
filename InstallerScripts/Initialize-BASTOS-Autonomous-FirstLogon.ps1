[CmdletBinding()]
param([string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = 'C:\ProgramData\BASTOS-ISO'
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\BASTOS'
$dataRoot = Join-Path $env:LOCALAPPDATA 'BASTOS'
$gameRoot = Join-Path $dataRoot 'Bastos Game'
$logRoot = Join-Path $dataRoot 'Logs'
$logPath = Join-Path $logRoot 'Autonomous-FirstLogon.log'
$runOncePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$runOnceName = 'BASTOS Autonomous Recovery'
$diagnosticContext = $null
$diagnosticModuleLoaded = $false
try {
    $diagnosticModule = Join-Path $sourceRoot 'BASTOS-SetupDiagnostics.psm1'
    if (Test-Path -LiteralPath $diagnosticModule -PathType Leaf) {
        Import-Module $diagnosticModule -Force
        $diagnosticModuleLoaded = $true
        $volumes = @(Get-Volume -FileSystemLabel 'BASTOS_RECOVERY' -ErrorAction SilentlyContinue | Where-Object DriveLetter)
        $diagnosticStorage = if ($volumes.Count -eq 1) { ('{0}:\' -f $volumes[0].DriveLetter) } else { $env:ProgramData }
        $diagnosticContext = Get-BastosDiagnosticContext -StorageRoot $diagnosticStorage -Create
    }
} catch {}

function Write-AutonomousLog {
    param([string]$Message,[string]$Level='INFO')
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Add-Content -LiteralPath $logPath -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message) -Encoding UTF8
    $color = switch ($Level) { 'OK' { 'Green' } 'WARNING' { 'Yellow' } 'ERROR' { 'Red' } default { 'Cyan' } }
    Write-Host ("[{0}] {1}" -f $Level,$Message) -ForegroundColor $color
    if ($diagnosticModuleLoaded -and $diagnosticContext) {
        try { Write-BastosDiagnosticEvent -Context $diagnosticContext -Component 'FirstLogon' -Level $(if($Level -in @('INFO','OK','WARNING','ERROR')){$Level}else{'INFO'}) -Message $Message } catch {}
    }
}

function Set-BastosFirstLogonDriverPolicy {
    # Before machine setup, Windows Update restart and any application download.
    # DriverSearching: DeviceSetup.admx, NeverCheckWU = 0.
    # Do not disable Windows Update itself or prevent installation of local/manual drivers.
    $settings = @(
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='ExcludeWUDriversInQualityUpdate'; Value=1 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'; Name='SearchOrderConfig'; Value=0 }
    )
    foreach ($setting in $settings) {
        if (-not (Test-Path -LiteralPath $setting.Path)) {
            New-Item -Path $setting.Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -PropertyType DWord -Value $setting.Value -Force -ErrorAction Stop | Out-Null
        $actual = Get-ItemPropertyValue -LiteralPath $setting.Path -Name $setting.Name -ErrorAction Stop
        if ([int]$actual -ne $setting.Value) {
            throw "Echec de verification du blocage des pilotes Windows : $($setting.Name)."
        }
    }
    Write-AutonomousLog 'Pilotes Windows Update exclus et recherche de pilotes en ligne desactivee. Pilotes locaux/manuels et mises a jour Windows de securite conserves.' 'OK'
}

function Show-BastosBanner {
    try { $Host.UI.RawUI.WindowTitle = 'Administrateur : Installation BASTOS' } catch {}
    Clear-Host
    Write-Host ('=' * 78) -ForegroundColor Green
    Write-Host '                         BIENVENUE DANS BASTOS' -ForegroundColor Green
    Write-Host ('=' * 78) -ForegroundColor Green
    Write-Host 'BASTOS termine le premier Bureau, installe son application et demarre Bastos Game.' -ForegroundColor Gray
    Write-Host 'Les reglages risques restent desactives et accessibles dans BASTOS > Optimisations.' -ForegroundColor Yellow
    Write-Host ''
}

function Save-AutonomousResult {
    param([bool]$Success,[string]$Message)
    $payload=[ordered]@{Success=$Success;Message=$Message;InstallRoot=$installRoot;GameConfig=(Join-Path $gameRoot 'Config.json');Date=[DateTime]::UtcNow.ToString('o')}
    if($ResultPath){
        $parent=Split-Path -Parent $ResultPath
        if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        [IO.File]::WriteAllText($ResultPath,($payload|ConvertTo-Json -Depth 3),[Text.UTF8Encoding]::new($false))
    }
    [pscustomobject]$payload
}

function Invoke-RequiredPowerShell {
    param([Parameter(Mandatory)][string]$Script,[string[]]$Arguments=@())
    if(-not(Test-Path -LiteralPath $Script -PathType Leaf)){throw "Script BASTOS absent : $Script"}
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList (@(
        '-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$Script
    )+$Arguments) -PassThru -WindowStyle Hidden
    $elapsedSeconds = 0
    while (-not $process.WaitForExit(30000)) {
        $elapsedSeconds += 30
        Write-AutonomousLog ("Etape toujours en cours : {0} ({1} s)." -f ([IO.Path]::GetFileName($Script)),$elapsedSeconds) 'INFO'
    }
    $process.WaitForExit()
    if($process.ExitCode -ne 0){throw "$([IO.Path]::GetFileName($Script)) a retourne le code $($process.ExitCode)."}
}

function Invoke-OptionalPowerShell {
    param([Parameter(Mandatory)][string]$Script,[string[]]$Arguments=@(),[string]$Label='Etape facultative')
    try {
        Invoke-RequiredPowerShell -Script $Script -Arguments $Arguments
        Write-AutonomousLog "$Label terminee." 'OK'
    } catch {
        Write-AutonomousLog "$Label non terminee : $($_.Exception.Message)" 'WARNING'
    }
}

function Install-BastosRuntime {
    $manifestPath = Join-Path $sourceRoot 'INSTALLER-MANIFEST.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Manifeste d installation BASTOS absent.' }
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    $sourcePrefix = ([IO.Path]::GetFullPath($sourceRoot)).TrimEnd('\') + '\'
    $targetPrefix = ([IO.Path]::GetFullPath($installRoot)).TrimEnd('\') + '\'
    $manifestEntryCount = @(Get-Content -LiteralPath $manifestPath | Where-Object { $_ -match '^([0-9A-Fa-f]{64})\s+(.+)$' }).Count
    if ($manifestEntryCount -eq 0) { throw 'Manifeste d installation BASTOS vide ou invalide.' }
    $copied = 0
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+(.+)$') { continue }
        $expected = $matches[1].ToUpperInvariant()
        $relative = $matches[2].Trim().Replace('/','\')
        if ([IO.Path]::IsPathRooted($relative) -or @($relative.Split('\')) -contains '..') { throw "Chemin de manifeste refuse : $relative" }
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $sourceRoot $relative))
        $targetFile = [IO.Path]::GetFullPath((Join-Path $installRoot $relative))
        if (-not $sourceFile.StartsWith($sourcePrefix,[StringComparison]::OrdinalIgnoreCase) -or
            -not $targetFile.StartsWith($targetPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Chemin hors racine refuse : $relative" }
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Fichier BASTOS absent : $relative" }
        if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne $expected) { throw "Empreinte source BASTOS incorrecte : $relative" }
        $parent = Split-Path -Parent $targetFile
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        if ((Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash -ne $expected) { throw "Copie BASTOS incorrecte : $relative" }
        $copied++
    }
    if ($copied -ne $manifestEntryCount) { throw "Copie BASTOS incomplete : $copied fichiers copies sur $manifestEntryCount attendus." }
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $installRoot 'INSTALLER-MANIFEST.sha256') -Force

    $nativeExe = Join-Path $installRoot 'Bastos.Native\BASTOS-Native.exe'
    if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) { throw 'BASTOS natif est absent apres la copie manifestee.' }
    $iconPath = Join-Path $installRoot 'Assets\Bastos-App.ico'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'BASTOS.lnk'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\BASTOS.lnk')
    )) {
        $shortcutParent = Split-Path -Parent $shortcutPath
        if ($shortcutParent) { New-Item -ItemType Directory -Path $shortcutParent -Force | Out-Null }
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $nativeExe
        $shortcut.WorkingDirectory = $installRoot
        $shortcut.Description = 'BASTOS - maintenance, optimisations et pilotes officiels'
        if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $shortcut.IconLocation = "$iconPath,0" }
        $shortcut.Save()
    }
    Write-AutonomousLog "Runtime BASTOS installe et verifie depuis $copied fichiers manifestes." 'OK'
    return $nativeExe
}

function Complete-BastosStartMenuAfterRuntimeInstall {
    param([Parameter(Mandatory)][string]$NativeExecutable)

    if(-not(Test-Path -LiteralPath $NativeExecutable -PathType Leaf)){
        throw "BASTOS natif est absent lors de la finalisation du menu Demarrer : $NativeExecutable"
    }
    $startShortcut=Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\BASTOS.lnk'
    if(-not(Test-Path -LiteralPath $startShortcut -PathType Leaf)){
        throw "Le raccourci BASTOS du menu Demarrer est absent : $startShortcut"
    }

    $modernPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if(-not(Test-Path -LiteralPath $modernPolicy)){New-Item -Path $modernPolicy|Out-Null}
    $layoutPath = Join-Path $sourceRoot 'LayoutModification.json'
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) {
        throw "Disposition du menu Demarrer absente : $layoutPath"
    }
    $layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$layout.applyOnce -or @($layout.pinnedList).Count -ne 3) {
        throw 'La disposition BASTOS doit etre applyOnce et contenir exactement trois epingles.'
    }
    New-ItemProperty -LiteralPath $modernPolicy -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force|Out-Null
    New-ItemProperty -LiteralPath $modernPolicy -Name ConfigureStartPinsJSON -PropertyType ExpandString -Value $layoutPath -Force|Out-Null
    New-ItemProperty -LiteralPath $modernPolicy -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force|Out-Null
    $registeredLayoutPath = [Environment]::ExpandEnvironmentVariables([string](Get-ItemPropertyValue -LiteralPath $modernPolicy -Name ConfigureStartPinsJSON -ErrorAction Stop))
    if ([int](Get-ItemPropertyValue -LiteralPath $modernPolicy -Name ConfigureStartPins -ErrorAction Stop) -ne 1 -or
        $registeredLayoutPath -ne $layoutPath) {
        throw 'La strategie finale du menu Demarrer n a pas ete enregistree.'
    }
    foreach($classicPolicy in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    )){
        Remove-ItemProperty -LiteralPath $classicPolicy -Name NoStartMenuMorePrograms -Force -ErrorAction SilentlyContinue
    }

    # Recharge uniquement l'interface Start apres la creation du raccourci
    # definitif. La disposition applyOnce reste personnalisable par le client.
    Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
    Write-AutonomousLog 'Menu Demarrer actualise : profil initial BASTOS, Explorateur et Parametres demande a Windows.' 'OK'
}

function Register-BastosGameScheduledStartup {
    $taskName='BASTOS Game'
    $startupTaskName='BASTOS Game Startup'
    $taskPath='\BASTOS\'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $identity.User){throw 'SID utilisateur indisponible pour la tache Bastos Game.'}
    $userSid=$identity.User.Value
    $installRoot=Join-Path $env:LOCALAPPDATA 'Programs\BASTOS'
    $gameRoot=Join-Path $env:LOCALAPPDATA 'BASTOS\Bastos Game'
    $engine=Join-Path $installRoot 'Bastos.Game\BASTOS-Game.exe'
    $configPath=Join-Path $gameRoot 'Config.json'
    $status=Join-Path $gameRoot 'Status.json'
    $stop=Join-Path $gameRoot 'Stop.request'
    $log=Join-Path $env:LOCALAPPDATA 'BASTOS\Logs\Bastos-Game.log'
    $recovery=Join-Path $gameRoot 'Recovery.json'
    $app=Join-Path $installRoot 'Bastos.Native\BASTOS-Native.exe'
    $icon=Join-Path $installRoot 'Assets\Bastos-Game-Tray.ico'
    $engineArguments='--config "{0}" --status "{1}" --stop "{2}" --log "{3}" --recovery "{4}" --app "{5}" --icon "{6}"' -f $configPath,$status,$stop,$log,$recovery,$app,$icon
    $startupScript=Join-Path $gameRoot 'Start-BASTOS-Game-Silent.vbs'
    $startupWorker=@'
Option Explicit
On Error Resume Next
Dim shell, fso, configPath, configText, configFile, enabledPattern, startupPattern
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
configPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\BASTOS\Bastos Game\Config.json"
If Not fso.FileExists(configPath) Then WScript.Quit 0
Set configFile = fso.OpenTextFile(configPath, 1, False)
configText = configFile.ReadAll
configFile.Close
Set enabledPattern = New RegExp
enabledPattern.IgnoreCase = True
enabledPattern.Pattern = """Enabled""\s*:\s*true"
Set startupPattern = New RegExp
startupPattern.IgnoreCase = True
startupPattern.Pattern = """RunAtStartup""\s*:\s*true"
If enabledPattern.Test(configText) And startupPattern.Test(configText) Then
    shell.Run "schtasks.exe /Run /TN ""\BASTOS\BASTOS Game""", 0, False
End If
'@
    New-Item -ItemType Directory -Path $gameRoot -Force|Out-Null
    [IO.File]::WriteAllText($startupScript,$startupWorker,[Text.UTF8Encoding]::new($false))
    $engineAction=New-ScheduledTaskAction -Execute $engine -Argument $engineArguments
    $enginePrincipal=New-ScheduledTaskPrincipal -UserId $userSid -LogonType Interactive -RunLevel Highest
    $engineSettings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $engineAction -Principal $enginePrincipal -Settings $engineSettings -Description 'Moteur Bastos Game autorise une seule fois et lance sans UAC recurrent.' -Force|Out-Null
    $startupAction=New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') -Argument ('//B //NoLogo "{0}"' -f $startupScript)
    $startupTrigger=New-ScheduledTaskTrigger -AtLogOn -User $userSid
    $startupPrincipal=New-ScheduledTaskPrincipal -UserId $userSid -LogonType Interactive -RunLevel Limited
    $startupSettings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $startupTaskName -TaskPath $taskPath -Action $startupAction -Trigger $startupTrigger -Principal $startupPrincipal -Settings $startupSettings -Description 'Respecte le reglage de demarrage de Bastos Game puis appelle le moteur deja autorise.' -Force|Out-Null
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BASTOS Game' -Force -ErrorAction SilentlyContinue
    $registered=Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
    if([string]$registered.Principal.RunLevel -ne 'Highest' -or [string]$registered.Actions.Execute -ne $engine){throw 'La tache Bastos Game autorisee est invalide.'}
    Write-AutonomousLog 'Demarrage Bastos Game enregistre avec droits eleves, sans UAC recurrent.' 'OK'
}

function Disable-BastosInstallationAutoLogon {
    $winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $passwordCleared=$false
    try {
        if([string]::IsNullOrWhiteSpace($env:USERNAME)){throw 'Le compte courant est inconnu.'}
        $account=[ADSI]('WinNT://./{0},user' -f $env:USERNAME)
        $account.SetPassword('')
        $account.SetInfo()
        $passwordCleared=$true
        Write-AutonomousLog 'Le mot de passe temporaire d installation a ete supprime.' 'OK'
    } catch {
        Write-AutonomousLog "Le mot de passe temporaire n a pas pu etre supprime automatiquement : $($_.Exception.Message)" 'WARNING'
    } finally {
        # New-Item -Force peut tenter de recréer une clé existante et échouer sur
        # Winlogon. Ne créer la clé que lorsqu'elle est réellement absente.
        if (-not (Test-Path -LiteralPath $winlogon)) { New-Item -Path $winlogon | Out-Null }
        New-ItemProperty -Path $winlogon -Name AutoAdminLogon -PropertyType String -Value '0' -Force|Out-Null
        Remove-ItemProperty -Path $winlogon -Name AutoLogonCount,DefaultPassword,DefaultDomainName,DefaultUserName,ForceAutoLogon -Force -ErrorAction SilentlyContinue
    }
    return $passwordCleared
}

function Invoke-OptionalIntegrityCheck {
    Write-Host ''
    Write-Host 'Controle d integrite systeme (facultatif)' -ForegroundColor Green
    Write-Host 'DISM puis SFC verifient et reparent les fichiers Windows. Cela peut prendre 30 minutes ou plus.' -ForegroundColor Gray
    Write-Host 'Sans reponse pendant 30 secondes, BASTOS continue sans le lancer.' -ForegroundColor Gray
    & choice.exe /C ON /N /T 30 /D N /M 'Lancer le controle maintenant ? (O/N) : '
    if ($LASTEXITCODE -ne 1) { Write-AutonomousLog 'Controle DISM/SFC ignore; il reste disponible dans Tests systeme.' 'INFO'; return }
    Write-AutonomousLog 'Controle DISM RestoreHealth demarre.'
    & dism.exe /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -ne 0) { Write-AutonomousLog "DISM a retourné le code $LASTEXITCODE." 'WARNING' }
    Write-AutonomousLog 'Controle SFC demarre.'
    & sfc.exe /scannow
    if ($LASTEXITCODE -ne 0) { Write-AutonomousLog "SFC a retourné le code $LASTEXITCODE." 'WARNING' }
}

try {
    # Supprimer le secret de bootstrap avant toute interface visible : le compte
    # livre a l utilisateur est immediatement sans mot de passe.
    [void](Disable-BastosInstallationAutoLogon)
    Set-BastosFirstLogonDriverPolicy
    Show-BastosBanner
    if ($diagnosticModuleLoaded -and $diagnosticContext) {
        Set-BastosDiagnosticState -Context $diagnosticContext -Stage 'FirstLogonStarted' -Message 'OOBE terminee; sequence utilisateur BASTOS demarree.'
        Copy-BastosSetupDiagnostics -Context $diagnosticContext -WindowsRoot $env:SystemRoot -SnapshotName 'FirstLogonStart'
    }
    foreach($required in @('VERSION.txt','Bastos-Uninstall.exe','Bastos.Native\BASTOS-Native.exe','Bastos.Game\BASTOS-Game.exe','Assets\Bastos-Game-Tray.ico','Invoke-BASTOS-Specialize.ps1','Apply-User.ps1','Complete-BASTOS-UserSetup.ps1','Invoke-BASTOS-PostInstall.ps1','Remove-BASTOS-OneDrive.ps1','Remove-BASTOS-Edge.ps1','Invoke-BASTOS-FirstDesktopEssentials.ps1','Install-BASTOS-SoftwareSelection.ps1')){
        if(-not(Test-Path -LiteralPath (Join-Path $sourceRoot $required) -PathType Leaf)){throw "Runtime BASTOS incomplet : $required"}
    }
    # FirstLogonCommands n est plus sequentiel sur les versions modernes de
    # Windows. Un seul orchestrateur execute donc toutes les etapes dans l ordre.
    # Conserver un RunOnce tant que la convergence n est pas entierement reussie.
    if (-not (Test-Path -LiteralPath $runOncePath)) { New-Item -Path $runOncePath | Out-Null }
    $retryCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path.Replace('"','')+'"'
    New-ItemProperty -Path $runOncePath -Name $runOnceName -PropertyType String -Value $retryCommand -Force|Out-Null
    Write-AutonomousLog 'Installation autonome de BASTOS demandee; Windows et OOBE sont termines.'
    Invoke-RequiredPowerShell -Script (Join-Path $sourceRoot 'Invoke-BASTOS-Specialize.ps1')
    Write-AutonomousLog 'Phase machine BASTOS executee apres OOBE.' 'OK'
    $wu='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au=Join-Path $wu 'AU'
    Remove-ItemProperty -Path $wu -Name DoNotConnectToWindowsUpdateInternetLocations -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $au -Name NoAutoUpdate -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -Name Start -Value 3 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc' -Name Start -Value 2 -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-AutonomousLog 'Windows Update reactive apres OOBE.' 'OK'

    Invoke-RequiredPowerShell -Script (Join-Path $sourceRoot 'Apply-User.ps1')
    Write-AutonomousLog 'Profil utilisateur BASTOS applique.' 'OK'
    Invoke-RequiredPowerShell -Script (Join-Path $sourceRoot 'Complete-BASTOS-UserSetup.ps1') -Arguments @(
        '-MaxAttempts','8','-WingetWaitSeconds','15','-MarkProfileComplete'
    )
    Write-AutonomousLog 'Profil utilisateur BASTOS converge et verifie.' 'OK'

    $postInstall=Join-Path $sourceRoot 'Invoke-BASTOS-PostInstall.ps1'
    Invoke-RequiredPowerShell -Script $postInstall
    Write-AutonomousLog 'Configuration systeme post-installation terminee.' 'OK'
    Write-AutonomousLog 'Installation des composants requis en cours; cette etape peut prendre plusieurs minutes.' 'INFO'
    Invoke-OptionalPowerShell -Script (Join-Path $sourceRoot 'Invoke-BASTOS-FirstDesktopEssentials.ps1') -Arguments @('-ResultPath',(Join-Path $sourceRoot 'FirstDesktop-Essentials.json')) -Label 'Installation de 7-Zip, DirectX et Visual C++'
    # Bastos-Uninstall.exe est le désinstalleur et ne doit jamais servir de
    # bootstrap. Installer le runtime directement depuis le manifeste vérifié.
    $nativeExe = Install-BastosRuntime
    $sourceVersion=(Get-Content -LiteralPath (Join-Path $sourceRoot 'VERSION.txt') -Raw).Trim()
    $installedVersion=(Get-Content -LiteralPath (Join-Path $installRoot 'VERSION.txt') -Raw).Trim()
    if($sourceVersion -ne $installedVersion){throw "Version BASTOS installee incorrecte : $installedVersion au lieu de $sourceVersion."}
    Complete-BastosStartMenuAfterRuntimeInstall -NativeExecutable $nativeExe

    New-Item -ItemType Directory -Path $gameRoot,$logRoot -Force|Out-Null
    $configPath=Join-Path $gameRoot 'Config.json'
    $statusPath=Join-Path $gameRoot 'Status.json'
    $stopPath=Join-Path $gameRoot 'Stop.request'
    $recoveryPath=Join-Path $gameRoot 'Recovery.json'
    $gameLog=Join-Path $logRoot 'Bastos-Game.log'
    $config=[ordered]@{Version=2;Enabled=$true;AutoDetect=$true;RunAtStartup=$true;OptimizeBackground=$false;Games=@();BlockedApps=@()}
    [IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    Register-BastosGameScheduledStartup
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'BASTOS Game' -TaskPath '\BASTOS\'

    $deadline=(Get-Date).AddSeconds(15)
    $ready=$false
    do{
        if(Test-Path -LiteralPath $statusPath -PathType Leaf){
            try{$state=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json;$ready=[string]$state.State -eq 'Ready' -and [string]$state.Engine -eq 'Native Win32'}catch{}
        }
        if(-not $ready){Start-Sleep -Milliseconds 300}
    }while(-not $ready -and (Get-Date)-lt $deadline)
    if(-not $ready){
        # La tache planifiee restera enregistree et retentera a la prochaine
        # ouverture de session sans nouvelle demande UAC.
        Write-AutonomousLog 'Bastos Game est installe; son demarrage interactif est reporte a la prochaine ouverture de session.' 'WARNING'
    } else {
        Write-AutonomousLog 'Bastos Game natif est actif et Ready.' 'OK'
    }

    # Le raccourci commun est la cible stable de la disposition du menu Demarrer.
    # Retirer uniquement une ancienne copie utilisateur afin d eviter un doublon.
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'BASTOS.lnk') -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runOncePath -Name $runOnceName -Force -ErrorAction SilentlyContinue
    Write-AutonomousLog "BASTOS $installedVersion et Bastos Game sont installes et verifies." 'OK'
    Invoke-OptionalIntegrityCheck
    if ($diagnosticModuleLoaded -and $diagnosticContext) {
        Copy-BastosSetupDiagnostics -Context $diagnosticContext -WindowsRoot $env:SystemRoot -SnapshotName 'FirstLogonCompleted'
        Set-BastosDiagnosticState -Context $diagnosticContext -Stage 'Completed' -Success $true -Message "Windows OOBE et BASTOS $installedVersion sont termines." -Extra @{OobeCompleted=$true;FirstLogonCompleted=$true}
    }
    Save-AutonomousResult -Success $true -Message "BASTOS $installedVersion installe; Bastos Game est actif."|Out-Null
    Write-Host ''
    Write-Host 'BASTOS est pret. Cette fenetre va se fermer dans 8 secondes.' -ForegroundColor Green
    Start-Sleep -Seconds 8
    exit 0
}catch{
    Write-AutonomousLog $_.Exception.Message 'ERROR'
    if ($diagnosticModuleLoaded -and $diagnosticContext) {
        try {
            Copy-BastosSetupDiagnostics -Context $diagnosticContext -WindowsRoot $env:SystemRoot -SnapshotName 'FirstLogonFailure'
            Set-BastosDiagnosticState -Context $diagnosticContext -Stage 'FirstLogonFailed' -Success $false -Message $_.Exception.Message -Extra @{OobeCompleted=$true;FirstLogonCompleted=$false}
        } catch {}
    }
    Save-AutonomousResult -Success $false -Message $_.Exception.Message|Out-Null
    exit 1
}
