[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SelectionPath,
    [Parameter(Mandatory)][string]$ProgressPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [ValidateSet('winget','chocolatey')][string]$Manager='winget',
    [string]$ManagerPath='',
    [string]$ExpectedUserSid='',
    [switch]$ElevatedRetry
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Write-ProgressState([int]$Percent,[string]$Phase,[string]$Detail){
    [IO.File]::WriteAllText($ProgressPath,("{0}`t{1}`t{2}" -f $Percent,$Phase,$Detail),[Text.UTF8Encoding]::new($false))
}

function Get-BastosChocolateyId([string]$WingetId){
    $map=@{
        'Google.Chrome'='googlechrome';'Opera.Opera'='opera';'Mozilla.Firefox'='firefox';'Mozilla.Firefox.Nightly.MSIX'='firefox-nightly';'Microsoft.Edge'='microsoft-edge'
        'Brave.Brave'='brave';'Vivaldi.Vivaldi'='vivaldi';'Zoom.Zoom'='zoom';'Discord.Discord'='discord'
        'Microsoft.Teams'='microsoft-teams-new-bootstrapper';'Pidgin.Pidgin'='pidgin';'Mozilla.Thunderbird'='thunderbird';'CeruleanStudios.Trillian'='trillian'
        'Apple.iTunes'='itunes';'VideoLAN.VLC'='vlc';'AIMP.AIMP'='aimp';'PeterPawlowski.foobar2000'='foobar2000'
        'Winamp.Winamp'='winamp';'Audacity.Audacity'='audacity';'CodecGuide.K-LiteCodecPack.Full'='k-litecodecpackfull'
        'GOMLab.GOMPlayer'='gom-player';'Spotify.Spotify'='spotify';'VentisMedia.MediaMonkey.2024'='mediamonkey';'HandBrake.HandBrake'='handbrake';'FxSound.FxSound'='fxsound'
        '7zip.7zip'='7zip';'Giorgiotani.Peazip'='peazip';'RARLab.WinRAR'='winrar'
        'KDE.Krita'='krita';'BlenderFoundation.Blender'='blender';'dotPDN.PaintDotNet'='paint.net';'GIMP.GIMP.3'='gimp'
        'IrfanSkiljan.IrfanView'='irfanview';'XnSoft.XnView.Classic'='xnview';'Inkscape.Inkscape'='inkscape'
        'FastStone.Viewer'='faststone-image-viewer';'Greenshot.Greenshot'='greenshot';'ShareX.ShareX'='sharex'
        'Foxit.FoxitReader'='foxitreader';'TheDocumentFoundation.LibreOffice'='libreoffice-fresh';'SumatraPDF.SumatraPDF'='sumatrapdf'
        'AcroSoftware.CutePDFWriter'='cutepdf';'Apache.OpenOffice'='openoffice';'AnyDesk.AnyDesk'='anydesk';'TeamViewer.TeamViewer'='teamviewer';'LIGHTNINGUK.ImgBurn'='imgburn'
        'RealVNC.VNCViewer'='vnc-viewer';'GlavSoft.TightVNC'='tightvnc';'CodeSector.TeraCopy'='teracopy'
        'RevoUninstaller.RevoUninstaller'='revo-uninstaller';'CodeJelly.Launchy'='launchy';'WinDirStat.WinDirStat'='windirstat'
        'AntibodySoftware.WizTree'='wiztree';'Glarysoft.GlaryUtilities'='glaryutilities-free';'Open-Shell.Open-Shell-Menu'='open-shell'
        'Piriform.CCleaner'='ccleaner';'GlennDelahoy.SnappyDriverInstallerOrigin'='snappy-driver-installer-origin';'WiseCleaner.WiseRegistryCleaner'='wise-registry-cleaner'
        'Evernote.Evernote'='evernote';'Google.EarthPro'='googleearthpro';'Valve.Steam'='steam'
        'EpicGames.EpicGamesLauncher'='epicgameslauncher';'DominikReichl.KeePass'='keepass';'voidtools.Everything'='everything'
        'Sinew.Enpass'='enpass';'NVAccess.NVDA'='nvda';'qBittorrent.qBittorrent'='qbittorrent';'Dropbox.Dropbox'='dropbox';'Google.GoogleDrive'='googledrive'
        'Microsoft.OneDrive'='onedrive';'Python.Python.3.13'='python313';'Python.Python.3.12'='python312';'Git.Git'='git'
        'Notepad++.Notepad++'='notepadplusplus';'WinSCP.WinSCP'='winscp';'PuTTY.PuTTY'='putty';'WinMerge.WinMerge'='winmerge'
        'Microsoft.VisualStudioCode'='vscode';'Anysphere.Cursor'='cursoride';'Microsoft.PowerShell'='powershell-core'
        'Microsoft.DotNet.DesktopRuntime.8'='dotnet-8.0-desktopruntime';'Microsoft.DotNet.DesktopRuntime.9'='dotnet-9.0-desktopruntime'
        'Microsoft.DotNet.DesktopRuntime.10'='dotnet-10.0-desktopruntime';'Microsoft.DotNet.AspNetCore.8'='dotnet-8.0-aspnetruntime'
        'Microsoft.DotNet.AspNetCore.9'='dotnet-9.0-aspnetruntime';'EclipseAdoptium.Temurin.8.JRE'='temurin8jre'
        'EclipseAdoptium.Temurin.11.JRE'='temurin11jre';'EclipseAdoptium.Temurin.17.JRE'='temurin17jre'
        'EclipseAdoptium.Temurin.21.JRE'='temurin21jre';'EclipseAdoptium.Temurin.8.JDK'='temurin8'
        'EclipseAdoptium.Temurin.11.JDK'='temurin11';'EclipseAdoptium.Temurin.17.JDK'='temurin17';'EclipseAdoptium.Temurin.21.JDK'='temurin21'
        'Malwarebytes.Malwarebytes'='malwarebytes';'Malwarebytes.AdwCleaner'='adwcleaner';'Microsoft.EdgeWebView2Runtime'='webview2-runtime'
        'Builtbybel.FluentCleaner'='fluentcleaner';'Wagnardsoft.DisplayDriverUninstaller'='display-driver-uninstaller';'Microsoft.DirectX'='directx'
        'CXWorld.CapFrameX'='capframex';'Guru3D.RTSS'='rivatuner-statistics-server';'REALiX.HWiNFO'='hwinfo'
        'OCBase.OCCT.Personal'='occt';'Resplendence.LatencyMon'='latencymon'
    }
    if($map.ContainsKey($WingetId)){return [string]$map[$WingetId]}
    return ''
}

function Test-BastosInstallerAdmin {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BastosPublisherDefinition([string]$Id){
    switch($Id){
        'AIMP.AIMP' { return @{Uri='https://aimp.ru/files/desktop/builds/aimp_5.40.2731_w64.exe';File='AIMP.exe';Signer='IP Izmaylov Artem Andreevich';Product='^AIMP$';Hash='715B781BD09E08C059CE0495A3A3F2BA540F35168C95CC1EC928F93340140E4B';Arguments=@('/AUTO','/SILENT')} }
        'REALiX.HWiNFO' { return @{Uri='https://www.sac.sk/download/utildiag/hwi_860x.exe';File='HWiNFO.exe';Signer='REALiX, s.r.o.';Product='^HWiNFO\s*$';Hash='A91126CF6BDBA645DA00B95BE7CA54157666391798042BB2037BC23BFFE791F9';Arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-')} }
        'Piriform.CCleaner' { return @{Uri='https://bits.avcdn.net/productfamily_CCLEANER7/insttype_FREE/platform_WIN/installertype_ONLINE/build_RELEASE';File='CCleaner.exe';Signer='Gen Digital Inc.';Product='^CCleaner$';Hash='';Arguments=@('/S')} }
        'Resplendence.LatencyMon' { return @{Uri='https://www.resplendence.com/download/LatencyMon.exe';File='LatencyMon.exe';Signer='SOFTREV LABS S.R.L.S.';Product='^LatencyMon \(Home Edition\)\s*$';Hash='';Arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-')} }
    }
    return $null
}

function Assert-BastosPublisherFile([string]$Path,$Definition){
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    if([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -ne $Definition.Signer){throw 'Signature de l editeur attendue absente ou non valide.'}
    $product=[string](Get-Item -LiteralPath $Path).VersionInfo.ProductName
    if($product -notmatch $Definition.Product){throw 'Le produit signe ne correspond pas au logiciel demande.'}
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if($Definition.Hash -and $hash -ne $Definition.Hash){throw 'Empreinte du telechargement versionne non conforme.'}
    return $hash
}

function Invoke-BastosPublisherInstall($Definition){
    if(([Uri]$Definition.Uri).Scheme -ne 'https'){throw 'Source non HTTPS refusee.'}
    $directory=Join-Path (Split-Path -Parent $ResultPath) ('Software-Publisher-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $directory -Force|Out-Null
    $file=Join-Path $directory $Definition.File
    Invoke-WebRequest -Uri $Definition.Uri -OutFile $file -UseBasicParsing -TimeoutSec 180
    $lease=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $hash=Assert-BastosPublisherFile $file $Definition
        $process=Start-Process -FilePath $file -ArgumentList $Definition.Arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
        try{
            if(-not $process.WaitForExit(900000)){return [pscustomobject]@{ExitCode=-2;Output='Installateur encore actif ; verifier avant de relancer.'}}
            return [pscustomobject]@{ExitCode=$process.ExitCode;Output=('Source editeur controlee : '+$Definition.Uri+' ; signature '+$Definition.Signer+' ; SHA256 '+$hash+' ; presence verifiee ensuite par le gestionnaire.')}
        }finally{$process.Dispose()}
    }finally{$lease.Dispose()}
}

function Test-BastosKnownAdminPackage([string]$Id,[string]$ManagerName,[string]$SourceName) {
    return $ManagerName -eq 'chocolatey' -or ($SourceName -eq 'winget' -and ($Id -in @('Open-Shell.Open-Shell-Menu','Glarysoft.GlaryUtilities') -or $null -ne (Get-BastosPublisherDefinition $Id)))
}

function Test-BastosGlaryPublisherFallback([string]$Id,[string]$ManagerName,[string]$SourceName,[int]$ExitCode){
    return $Id -eq 'Glarysoft.GlaryUtilities' -and $ManagerName -eq 'winget' -and $SourceName -eq 'winget' -and $ExitCode -eq -1978335215
}

function Test-BastosGlaryPublisherSignature($Signature){
    return [string]$Signature.Status -eq 'Valid' -and $null -ne $Signature.SignerCertificate -and $Signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -eq 'Glarysoft Ltd'
}

function Invoke-BastosGlaryPublisherInstall {
    # The vendor's evergreen URL can change before the WinGet manifest catches up.
    # This is a separate publisher-authenticated path, never a WinGet hash override.
    $directory=Join-Path (Split-Path -Parent $ResultPath) ('Glary-Official-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $directory -Force|Out-Null
    $installer=Join-Path $directory 'gusetup.exe'
    $uri='https://download.glarysoft.com/gusetup.exe'
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $uri -UseBasicParsing -MaximumRedirection 0 -OutFile $installer -TimeoutSec 180
    # Deny writes/deletion between authentication and process creation.
    $lease=[IO.File]::Open($installer,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $signature=Get-AuthenticodeSignature -LiteralPath $installer
        if(-not(Test-BastosGlaryPublisherSignature $signature)){throw 'Installateur Glary refuse : signature valide Glarysoft Ltd requise.'}
        $hash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        $process=Start-Process -FilePath $installer -ArgumentList '/S' -PassThru -ErrorAction Stop
        try{
            if(-not $process.WaitForExit(900000)){return [pscustomobject]@{ExitCode=-2;Output='Installateur Glary toujours actif apres le delai ; verifier avant de relancer.'}}
            return [pscustomobject]@{ExitCode=$process.ExitCode;Output=('Source officielle Glarysoft ; signature Authenticode valide Glarysoft Ltd ; SHA256 '+$hash+'. Code installateur : '+$process.ExitCode+'. Presence verifiee ensuite par WinGet.')}
        }finally{$process.Dispose()}
    }finally{$lease.Dispose()}
}

function Get-BastosInstallerPrivilegeEvidence {
    param([int]$ExitCode,[string]$Output,[string]$PackageId,[datetime]$StartedUtc,[string]$LogRoot=(Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'))
    if($ExitCode -eq 740 -or $Output -match '(?im)\b(?:Error|Erreur)\s+1925\b') {return [pscustomobject]@{Required=$true;LogPath=''}}
    # 1603 alone is deliberately insufficient: it also represents unrelated failures.
    if(Test-Path -LiteralPath $LogRoot){
        foreach($file in @(Get-ChildItem -LiteralPath $LogRoot -Filter ('WinGet-'+$PackageId+'.*.log') -File -ErrorAction SilentlyContinue|Where-Object {$_.LastWriteTimeUtc -ge $StartedUtc.AddSeconds(-2)}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 3)){
            if($file.Length -gt 8MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
            try{if([IO.File]::ReadAllText($file.FullName) -match '(?im)\b(?:Error|Erreur)\s+1925\b'){return [pscustomobject]@{Required=$true;LogPath=$file.FullName}}}catch{}
        }
    }
    return [pscustomobject]@{Required=$false;LogPath=''}
}

function ConvertTo-BastosInstallerArgument([string]$Value){
    if($Value -match '["\r\n]'){throw 'Argument du processus administrateur refuse.'}
    return '"'+$Value+'"'
}

function Invoke-BastosElevatedSoftwareItem($Item,[string]$ManagerExe) {
    $directory=Split-Path -Parent $ResultPath
    $request=Join-Path $directory ('Software-Admin-Selection-'+[guid]::NewGuid().ToString('N')+'.json')
    $result=Join-Path $directory ('Software-Admin-Result-'+[guid]::NewGuid().ToString('N')+'.json')
    $progress=Join-Path $directory ('Software-Admin-Progress-'+[guid]::NewGuid().ToString('N')+'.txt')
    [IO.File]::WriteAllText($request,($Item|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-SelectionPath',$request,'-ProgressPath',$progress,'-ResultPath',$result,'-Manager',$Manager,'-ManagerPath',$ManagerExe,'-ExpectedUserSid',$sid,'-ElevatedRetry')
    $argumentLine=($arguments|ForEach-Object {ConvertTo-BastosInstallerArgument $_}) -join ' '
    $finished=$false
    try{
        try{
            $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argumentLine -Verb RunAs -PassThru -WindowStyle Hidden -ErrorAction Stop
        }catch{
            $errorObject=$_.Exception;$cancelled=$false
            while($errorObject){if($errorObject -is [ComponentModel.Win32Exception] -and $errorObject.NativeErrorCode -eq 1223){$cancelled=$true};$errorObject=$errorObject.InnerException}
            return [pscustomobject]@{Name=$Item.Name;Id=$Item.Id;Source=$(if($Item.PSObject.Properties['Source']){$Item.Source}else{'winget'});Manager=$Manager;Success=$false;Verified=$false;Status='Failed';ExitCode=$(if($cancelled){1223}else{-1});ErrorCode=$(if($cancelled){'ADMIN_CANCELLED'}else{'ADMIN_START_FAILED'});Detail=$(if($cancelled){'Autorisation administrateur annulee. Relance Installer et accepte la demande Windows.'}else{'Demarrage administrateur impossible : '+$_.Exception.Message})}
        }
        if(-not $process.WaitForExit(3600000)){
            return [pscustomobject]@{Name=$Item.Name;Id=$Item.Id;Source=$(if($Item.PSObject.Properties['Source']){$Item.Source}else{'winget'});Manager=$Manager;Success=$false;Verified=$false;Status='Failed';ExitCode=-2;ErrorCode='INSTALLATION_UNCONFIRMED';Detail='Le processus administrateur peut encore travailler. Verifie son etat avant de relancer.'}
        }
        $finished=$true
        if(-not(Test-Path -LiteralPath $result)){throw 'Rapport administrateur absent.'}
        $report=Get-Content -LiteralPath $result -Raw -Encoding UTF8|ConvertFrom-Json
        if($report.PSObject.Properties['Error']){throw ([string]$report.Error)}
        $items=@($report.Items)
        if($report.Schema -ne 2 -or $report.Requested -ne 1 -or $items.Count -ne 1 -or $items[0].Id -ne $Item.Id -or $report.UserSid -ne $sid){throw 'Rapport administrateur incoherent.'}
        if($process.ExitCode -ne 0 -and $items[0].Success){throw 'Succes contredit par le processus administrateur.'}
        return $items[0]
    }finally{
        # Keep the report; do not remove arguments while an unconfirmed process might use them.
        if($finished){foreach($path in @($request,$progress)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}}
    }
}

$result=[ordered]@{Schema=2;Success=$false;Manager=$Manager;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Requested=0;Installed=0;AlreadyPresent=0;Failed=0;Items=@();UpdatedUtc=[datetime]::UtcNow.ToString('o')}
try{
    if($ExpectedUserSid -and $result.UserSid -ne $ExpectedUserSid){throw 'Elevation sous un autre compte refusee : aucune installation lancee.'}
    $isAdmin=Test-BastosInstallerAdmin
    if($ElevatedRetry -and -not $isAdmin){throw 'Autorisation administrateur requise ; aucune nouvelle tentative automatique.'}
    $managerExe=$null
    if($ManagerPath -and (Test-Path -LiteralPath $ManagerPath -PathType Leaf)){$managerExe=[IO.Path]::GetFullPath($ManagerPath)}
    if(-not $managerExe){
        $commandName=if($Manager -eq 'winget'){'winget.exe'}else{'choco.exe'}
        $managerExe=(Get-Command $commandName -ErrorAction Stop).Source
    }
    $chocoLocal=@()
    if($Manager -eq 'chocolatey'){
        $versionText=(& $managerExe --version 2>&1|Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or $versionText -notmatch '^(\d+)\.'){throw 'Version de Chocolatey non confirmee.'}
        if([int]$Matches[1] -lt 2){$chocoLocal=@('--local-only')}
    }
    # ConvertFrom-Json renvoie un objet scalaire lorsqu'une seule application
    # est sélectionnée. Le tableau explicite garantit que la boucle traite
    # aussi correctement ce cas.
    $decoded=Get-Content -LiteralPath $SelectionPath -Raw -Encoding UTF8|ConvertFrom-Json
    $selection=[Collections.Generic.List[object]]::new()
    if($decoded -is [Array]){
        foreach($decodedItem in [Array]$decoded){$selection.Add($decodedItem)}
    }elseif($null -ne $decoded){
        $selection.Add($decoded)
    }
    if($selection.Count -eq 0){throw 'Aucune application sélectionnée.'}
    $result.Requested=$selection.Count
    for($index=0;$index -lt $selection.Count;$index++){
        $item=$selection[$index]
        $name=[string]$item.Name
        $id=[string]$item.Id
        $source=if($item.PSObject.Properties['Source'] -and [string]$item.Source){[string]$item.Source}else{'winget'}
        if($id -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{1,127}$'){throw "Identifiant WinGet non sûr refusé : $id"}
        if($source -notin @('winget','msstore')){throw "Source WinGet non sure refusee : $source"}
        $percent=[math]::Max(1,[int][math]::Floor(($index*100)/$selection.Count))
        Write-ProgressState $percent ("Installation {0}/{1}" -f ($index+1),$selection.Count) $name
        $adminItem=$null
        if(-not $isAdmin -and -not $ElevatedRetry -and (Test-BastosKnownAdminPackage $id $Manager $source)){
            Write-ProgressState $percent 'Autorisation administrateur' $name
            $adminItem=Invoke-BastosElevatedSoftwareItem $item $managerExe
        }
        $startedUtc=[datetime]::UtcNow
        if($null -ne $adminItem){
            $result.Items+=,$adminItem
            if($adminItem.Success){if($adminItem.Status -eq 'AlreadyPresent'){$result.AlreadyPresent++}else{$result.Installed++}}else{$result.Failed++}
            continue
        }
        $publisherDefinition=if($Manager -eq 'winget' -and $source -eq 'winget'){Get-BastosPublisherDefinition $id}else{$null}
        if($null -ne $publisherDefinition){
            $alreadyPresent=$false
            try{
                if(-not $isAdmin){throw 'Droits administrateur requis pour ce programme.'}
                $publisherResult=Invoke-BastosPublisherInstall $publisherDefinition
                $output=$publisherResult.Output;$exitCode=$publisherResult.ExitCode
            }catch{$output='Installation depuis la source officielle refusee : '+$_.Exception.Message;$exitCode=-1}
        }elseif($Manager -eq 'winget'){
            $output=& $managerExe install --id $id --exact --source $source --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1|Out-String
            $exitCode=$LASTEXITCODE
            # WinGet 0x8A15002B / -1978335189 means that the package is already
            # installed and that no newer version applies. This is not a failure.
            $alreadyPresent=$exitCode -eq -1978335189
        }else{
            $chocolateyId=if($item.PSObject.Properties['ChocolateyId'] -and [string]$item.ChocolateyId){[string]$item.ChocolateyId}else{Get-BastosChocolateyId -WingetId $id}
            if($chocolateyId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$'){
                $output="Aucun identifiant Chocolatey fiable n est défini pour $name ($id)."
                $exitCode=2
                $alreadyPresent=$false
            }else{
                $listArguments=@('list')+$chocoLocal+@('--exact',$chocolateyId,'--limit-output')
                $installedOutput=& $managerExe @listArguments 2>&1|Out-String
                $alreadyPresent=$LASTEXITCODE -eq 0 -and $installedOutput -match ('(?im)^'+[regex]::Escape($chocolateyId)+'\|')
                if($alreadyPresent){$output=$installedOutput;$exitCode=0}
                else{$output=& $managerExe install $chocolateyId --yes --no-progress --limit-output 2>&1|Out-String;$exitCode=$LASTEXITCODE}
            }
        }
        $ok=($exitCode -in @(0,3010)) -or $alreadyPresent
        if(Test-BastosGlaryPublisherFallback $id $Manager $source $exitCode){
            try{
                if(-not $isAdmin){throw 'Relance Bastos en administrateur pour installer Glary depuis sa source officielle.'}
                Write-ProgressState $percent 'Installation officielle Glarysoft' $name
                $publisherResult=Invoke-BastosGlaryPublisherInstall
                $exitCode=$publisherResult.ExitCode
                $output+="`r`n"+$publisherResult.Output
                $ok=$exitCode -in @(0,3010)
            }catch{
                $output+="`r`nSource officielle Glary non confirmee : "+$_.Exception.Message
                $ok=$false
            }
        }
        if(-not $ok -and -not $isAdmin -and -not $ElevatedRetry -and $Manager -eq 'winget'){
            $evidence=Get-BastosInstallerPrivilegeEvidence -ExitCode $exitCode -Output $output -PackageId $id -StartedUtc $startedUtc
            if($evidence.Required){
                Write-ProgressState $percent 'Autorisation administrateur pour reprendre' $name
                $adminItem=Invoke-BastosElevatedSoftwareItem $item $managerExe
                $result.Items+=,$adminItem
                if($adminItem.Success){if($adminItem.Status -eq 'AlreadyPresent'){$result.AlreadyPresent++}else{$result.Installed++}}else{$result.Failed++}
                continue
            }
        }
        $verified=$false
        if($ok){
            if($Manager -eq 'winget'){
                $presence=& $managerExe list --id $id --exact --source $source --accept-source-agreements --disable-interactivity 2>&1|Out-String
                $verified=$LASTEXITCODE -eq 0 -and $presence -match ('(?im)(?:^|\s)'+[regex]::Escape($id)+'(?:\s|$)')
            }else{
                $listArguments=@('list')+$chocoLocal+@('--exact',$chocolateyId,'--limit-output')
                $presence=& $managerExe @listArguments 2>&1|Out-String
                $verified=$LASTEXITCODE -eq 0 -and $presence -match ('(?im)^'+[regex]::Escape($chocolateyId)+'\|')
            }
            if(-not $verified){$ok=$false;$alreadyPresent=$false;$output+="`r`nL installation est annoncee terminee mais la presence du logiciel n est pas confirmee. Actualise avant de relancer."}
        }
        # Portable FluentCleaner does not create a desktop shortcut itself.
        # Run for successful installs and already-present results, for the caller's own Desktop.
        if($ok -and $id -eq 'Builtbybel.FluentCleaner'){
            try{
                . (Join-Path $PSScriptRoot 'BASTOS-SoftwareShortcuts.ps1')
                $shortcutPath=New-BastosFluentCleanerDesktopShortcut
                $output+="`r`nRaccourci Bureau : $shortcutPath"
            }catch{
                $ok=$false
                $alreadyPresent=$false
                $output+="`r`nCréation du raccourci impossible : $($_.Exception.Message)"
            }
        }
        $status=if($alreadyPresent){'AlreadyPresent'}elseif($ok){'Installed'}else{'Failed'}
        if($alreadyPresent){$result.AlreadyPresent++}elseif($ok){$result.Installed++}else{$result.Failed++}
        $result.Items+=,[pscustomobject]@{Name=$name;Id=$id;Source=$source;Manager=$Manager;Success=$ok;Verified=$verified;Status=$status;ExitCode=$exitCode;RestartRequired=($exitCode -eq 3010);Detail=$output.Trim()}
    }
    $result.Success=$result.Failed -eq 0
    Write-ProgressState 100 'Installation groupée terminée' ("{0} installée(s), {1} déjà présente(s), {2} échec(s)" -f $result.Installed,$result.AlreadyPresent,$result.Failed)
}catch{
    $result['Error']=$_.Exception.Message
    Write-ProgressState 100 'Installation groupée interrompue' $_.Exception.Message
}finally{
    $result.UpdatedUtc=[datetime]::UtcNow.ToString('o')
    $temporary=$ResultPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{[IO.File]::WriteAllText($temporary,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $temporary -Destination $ResultPath -Force}
    finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}}
}
if($result.Success){exit 0}else{exit 1}
