# BASTOS local graphics driver workflows.
# The adapted debloat workflow retains its upstream attribution and MIT notice.
# Launched visibly and elevated only when the user selects the BASTOS button.
param(
    [ValidateSet('Standard','Debloat')][string]$Mode='Standard',
    [ValidateSet('Run','Plan','CheckHardware')][string]$Action='Run',
    [ValidateSet('Auto','NVIDIA','AMD','Intel')][string]$Vendor='Auto',
    [string]$ResultPath
)
$ErrorActionPreference='Stop'

# Debloat workflow adapted from FR33THYFR33THY/Ultimate,
# 5 Graphics/4 Driver Debloat Install & Settings.ps1, MIT license.
# This local workflow never executes downloaded PowerShell code. The existing
# ThirdParty/Ultimate-LICENSE.txt contains the upstream license notice.
function Get-BastosDebloatPlan([string]$SelectedVendor) {
    switch($SelectedVendor) {
        'NVIDIA' { return [pscustomobject]@{Vendor='NVIDIA';OfficialUrl='https://www.nvidia.com/en-us/drivers/';Summary='Extract official NVIDIA package; omit FrameView, ShadowPlay, NView, telemetry and virtual audio from the temporary copy; keep display driver, HDMI audio, PhysX and control panel.'} }
        'AMD' { return [pscustomobject]@{Vendor='AMD';OfficialUrl='https://www.amd.com/en/support/download/drivers.html';Summary='Extract official AMD package; disable optional updater, analytics, Link and relauncher components in the temporary configuration; keep display, HDMI audio and Radeon Software.'} }
        'Intel' { return [pscustomobject]@{Vendor='Intel';OfficialUrl='https://www.intel.com/content/www/us/en/download-center/home.html';Summary='Extract official Intel package; install the display driver with --noExtras; keep existing system services and audio devices.'} }
    }
    throw 'Constructeur graphique non pris en charge.'
}
function Get-BastosStandardPlan([string]$SelectedVendor) {
    $source=Get-BastosDebloatPlan $SelectedVendor
    return [pscustomobject]@{Vendor=$source.Vendor;OfficialUrl=$source.OfficialUrl;Summary='Pilote officiel complet, sans modification du paquet par BASTOS.'}
}
function Select-BastosDebloatVendor {
    Write-Host 'Pilote graphique allege : 1 NVIDIA / 2 AMD / 3 Intel' -ForegroundColor Cyan
    $choice=Read-Host 'Choisis le constructeur (1, 2 ou 3)'
    switch($choice){'1'{return 'NVIDIA'} '2'{return 'AMD'} '3'{return 'Intel'} default{throw 'Choix annule ou invalide.'}}
}
function Test-BastosDebloatHardware([string]$SelectedVendor) {
    $ids=@(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {[string]$_.PNPDeviceID})
    $code=switch($SelectedVendor){'NVIDIA'{'VEN_10DE'} 'AMD'{'VEN_1002'} 'Intel'{'VEN_8086'}}
    $pattern='(?i)^PCI\\'+$code+'&'
    if(-not @($ids|Where-Object {$_ -match $pattern}).Count){throw "Aucune carte $SelectedVendor detectee. Installation annulee."}
}
function Write-BastosGraphicsResult([bool]$Success,[string]$Message) {
    if(-not $ResultPath){return}
    $base=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'BASTOS\Logs')).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath($ResultPath)
    if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetExtension($path) -ne '.json'){throw 'Chemin de compte rendu refuse.'}
    New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
    $json=[ordered]@{Success=$Success;Message=$Message;Vendor=$selected;Utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
    [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
}
function Select-BastosOfficialPackage([string]$SelectedVendor) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=[Windows.Forms.OpenFileDialog]::new()
    $dialog.Title="Choisir le pilote $SelectedVendor telecharge depuis le fabricant"
    $dialog.Filter='Installateur Windows (*.exe)|*.exe'
    $dialog.CheckFileExists=$true
    try {
        if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){throw 'Selection du pilote annulee.'}
        $file=[IO.Path]::GetFullPath($dialog.FileName)
    } finally {$dialog.Dispose()}
    $signature=Get-AuthenticodeSignature -LiteralPath $file
    if($signature.Status -ne 'Valid'){throw 'Signature numerique du pilote absente ou invalide.'}
    $subject=[string]$signature.SignerCertificate.Subject
    $expected=switch($SelectedVendor){'NVIDIA'{'NVIDIA'} 'AMD'{'Advanced Micro Devices|AMD'} 'Intel'{'Intel'}}
    if($subject -notmatch $expected){throw "Le signataire ne correspond pas a $SelectedVendor : $subject"}
    return $file
}
function Get-BastosExtractor {
    foreach($path in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")){
        if($path -and (Test-Path -LiteralPath $path -PathType Leaf)){return $path}
    }
    throw '7-Zip est requis pour extraire le pilote officiel. Installe-le puis relance cette option.'
}
function Remove-BastosStagedComponent([string]$Stage,[string]$Relative) {
    $base=[IO.Path]::GetFullPath($Stage).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath((Join-Path $Stage $Relative))
    if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Composant hors du dossier temporaire.'}
    if(Test-Path -LiteralPath $path){
        $item=Get-Item -LiteralPath $path -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Lien de fichier inattendu dans le pilote.'}
        Remove-Item -LiteralPath $path -Recurse -Force
        Write-Host "Composant facultatif retire de la copie temporaire : $Relative"
    }
}
function Invoke-BastosDebloatDriver([string]$SelectedVendor) {
    $plan=Get-BastosDebloatPlan $SelectedVendor
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Autorisation administrateur requise.'}
    Test-BastosDebloatHardware $SelectedVendor
    Write-Host $plan.Summary -ForegroundColor Cyan
    Write-Host 'Telecharge le pilote depuis la page officielle qui va s ouvrir, puis reviens ici.'
    Start-Process $plan.OfficialUrl
    [void](Read-Host 'Appuie sur Entree quand le fichier est telecharge')
    $package=Select-BastosOfficialPackage $SelectedVendor
    $extractor=Get-BastosExtractor
    if((Read-Host "Preparer puis installer ce pilote $SelectedVendor allege ? (O/N)") -notmatch '^(?i:o|oui)$'){throw 'Installation annulee.'}
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $stage=Join-Path $tempRoot ('BASTOS-Graphics-Debloat-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    try {
        & $extractor x $package ('-o'+$stage) '-y' | Out-Null
        if($LASTEXITCODE -ne 0){throw "Extraction du pilote echouee (code $LASTEXITCODE)."}
        $links=@(Get-ChildItem -LiteralPath $stage -Force -Recurse -ErrorAction Stop | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint})
        if($links.Count){throw 'Le paquet contient un lien de fichier inattendu.'}
        $installer=$null; $arguments=$null
        switch($SelectedVendor){
            'NVIDIA' {
                foreach($name in @('Display.Nview','FrameViewSDK','NvTelemetry','NvVAD','ShadowPlay')){Remove-BastosStagedComponent $stage $name}
                $installer=Join-Path $stage 'setup.exe'; $arguments='-clean -noreboot'
            }
            'AMD' {
                $optional=@('AMDAUEPInstaller.xml','AMDCOMPUTE.xml','AMDLinkDriverUpdate.xml','AMDRELAUNCHER.xml','AMDScoSupportTypeUpdate.xml','AMDUpdater.xml','AMDUWPLauncher.xml','InstallUEP.xml')
                foreach($name in $optional){
                    $file=Join-Path $stage ('Config\'+$name)
                    if(Test-Path -LiteralPath $file -PathType Leaf){
                        $text=[IO.File]::ReadAllText($file)
                        $updated=[regex]::Replace($text,'<Enabled>\s*true\s*</Enabled>','<Enabled>false</Enabled>',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
                        if($updated -ne $text){[IO.File]::WriteAllText($file,$updated);Write-Host "Module facultatif desactive : $name"}
                    }
                }
                $installer=Join-Path $stage 'Bin64\ATISetup.exe'; $arguments='-INSTALL -VIEW:2'
            }
            'Intel' {$installer=Join-Path $stage 'Installer.exe';$arguments='-f --noExtras --terminateProcesses -s'}
        }
        if(-not(Test-Path -LiteralPath $installer -PathType Leaf)){throw "Installateur $SelectedVendor absent de l archive officielle."}
        $process=Start-Process -FilePath $installer -ArgumentList $arguments -WorkingDirectory (Split-Path $installer) -Wait -PassThru
        if($process.ExitCode -notin @(0,3010)){throw "L installateur a retourne le code $($process.ExitCode)."}
        if($SelectedVendor -eq 'AMD'){Start-Sleep -Seconds 90}
        Write-Host "Pilote $SelectedVendor installe. Un redemarrage est recommande." -ForegroundColor Green
    } finally {
        $full=[IO.Path]::GetFullPath($stage)
        if($full.StartsWith($tempRoot+'BASTOS-Graphics-Debloat-',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)){
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
if($Mode -eq 'Debloat'){
    try {
        $selected=if($Vendor -eq 'Auto' -and $Action -eq 'Run'){Select-BastosDebloatVendor}else{$Vendor}
        if($Action -eq 'Plan'){
            if($selected -eq 'Auto'){@('NVIDIA','AMD','Intel')|ForEach-Object {Write-Output (Get-BastosDebloatPlan $_)}}
            else{Write-Output (Get-BastosDebloatPlan $selected)}
        } elseif($Action -eq 'CheckHardware'){
            Test-BastosDebloatHardware $selected
            Write-BastosGraphicsResult $true "Carte $selected detectee."
            Write-Output "Carte $selected detectee."
        } else {
            Invoke-BastosDebloatDriver $selected
            Write-BastosGraphicsResult $true "Installation du pilote $selected terminee. Redemarrage recommande."
            [void](Read-Host 'Appuie sur Entree pour fermer')
        }
        return
    } catch {
        $message='Echec du pilote allege : '+$_.Exception.Message
        Write-Host $message -ForegroundColor Red
        try{Write-BastosGraphicsResult $false $message}catch{}
        if($Action -eq 'Run'){[void](Read-Host 'Appuie sur Entree pour fermer')}
        exit 1
    }
}
$ErrorActionPreference = 'Stop'
try {
    $Host.UI.RawUI.WindowTitle = 'BASTOS - Pilotes graphiques NVIDIA / AMD / Intel'
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Lance ce menu depuis BASTOS et accepte la demande administrateur.'
    }
    $selected=if($Vendor -eq 'Auto' -and $Action -eq 'Run'){Select-BastosDebloatVendor}else{$Vendor}
    if($selected -eq 'Auto' -and $Action -eq 'Plan'){@('NVIDIA','AMD','Intel')|ForEach-Object{Get-BastosStandardPlan $_};return}
    if($selected -eq 'Auto'){throw 'Choisis NVIDIA, AMD ou Intel.'}
    if($Action -eq 'Plan'){Get-BastosStandardPlan $selected;return}
    Test-BastosDebloatHardware $selected
    if($Action -eq 'CheckHardware'){Write-BastosGraphicsResult $true "Carte $selected detectee.";return}
    $plan=Get-BastosStandardPlan $selected
    Write-Host "Ouvre la page officielle $selected, telecharge le pilote adapte a ta carte, puis selectionne son installateur signe." -ForegroundColor Cyan
    Start-Process $plan.OfficialUrl
    [void](Read-Host 'Appuie sur Entree quand le pilote officiel est telecharge')
    $package=Select-BastosOfficialPackage $selected
    $process=Start-Process -FilePath $package -Wait -PassThru
    if($process.ExitCode -notin @(0,3010)){throw "L installateur $selected a retourne le code $($process.ExitCode)."}
    $message="L installateur signe $selected s est termine (code $($process.ExitCode)). Controle la version du pilote apres redemarrage."
    Write-BastosGraphicsResult $true $message
    Write-Host $message -ForegroundColor Green
    if($Action -eq 'Run'){[void](Read-Host 'Appuie sur Entree pour fermer')}
}
catch {
    $message='Echec du pilote graphique : '+$_.Exception.Message
    Write-Host $message -ForegroundColor Red
    try{Write-BastosGraphicsResult $false $message}catch{}
    if($Action -eq 'Run'){[void](Read-Host 'Appuie sur Entree pour fermer')}
    exit 1
}
