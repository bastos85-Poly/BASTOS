[CmdletBinding()]
param(
    [string]$ProfilePath='',
    [string]$ResultPath='',
    [string]$RequestId=([guid]::NewGuid().ToString('D')),
    [string]$ExpectedUserSid=''
)
# Read-only Windows inspection. Only the report is written; no settings are repaired.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $ProfilePath){$ProfilePath=Join-Path $PSScriptRoot 'Installation-Expected.json'}
if(-not $ResultPath){$ResultPath=Join-Path $PSScriptRoot 'Logs\Installation-Verification.json'}
$profile=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8|ConvertFrom-Json
if($profile.Schema -notin @(1,2) -or [guid]$profile.ProfileId -eq [guid]::Empty){throw 'Profil de verification invalide.'}
if($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid){throw 'Le controle doit etre execute avec le meme compte Windows ; une elevation sous un autre compte est refusee.'}
$checks=[Collections.Generic.List[object]]::new()
function Test-Setting {
    param([string]$Id,[string]$Name,[string]$Expected,[scriptblock]$Read,[string]$Action)
    $actual='';$status='Unavailable';$detail=''
    try{
        $actual=[string](& $Read)
        if([string]::IsNullOrWhiteSpace($Expected)){$detail='Valeur attendue absente du profil. Reprepare le media avec cette version de Bastos.'}
        elseif([string]::IsNullOrWhiteSpace($actual)){$detail='Windows ne fournit pas de valeur exploitable. '+$Action}
        elseif($actual -ieq $Expected){$status='Passed';$detail='Conforme au profil demande.'}
        else{$status='Mismatch';$detail=$Action}
    }catch{$detail='Controle impossible : '+$_.Exception.Message+' '+$Action}
    $checks.Add([pscustomobject]@{Id=$Id;Name=$Name;Expected=$Expected;Actual=$actual;Status=$status;Detail=$detail})
}
Test-Setting edition 'Edition de Windows' $profile.EditionId {
    (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID).EditionID
} 'Verifie l edition dans Parametres > Systeme > Informations systeme et le choix fait dans le profil ISO.'
Test-Setting language 'Langue de Windows' $profile.UILanguage {
    $override=Get-WinUILanguageOverride
    if($override){$override.Name}else{(Get-UICulture).Name}
} 'Ouvre Parametres > Heure et langue > Langue et region. Une deconnexion peut etre necessaire apres un changement.'
Test-Setting region 'Format regional' $profile.Locale { (Get-Culture).Name } 'Verifie le format regional dans Parametres > Heure et langue > Langue et region.'
Test-Setting keyboard 'Clavier principal' $profile.KeyboardLayout {
    $override=Get-WinDefaultInputMethodOverride
    if($override){$override.InputMethodTip}else{
        $languages=@(Get-WinUserLanguageList)
        if($languages.Count -gt 0){
            $tips=@($languages[0].InputMethodTips)
            if($tips.Count -gt 0){$tips[0]}
        }
    }
} 'Ouvre Parametres > Heure et langue > Saisie > Parametres avances du clavier et verifie la methode de saisie par defaut.'
Test-Setting computer 'Nom du PC' $profile.ComputerName { $env:COMPUTERNAME } 'Verifie le nom dans Parametres > Systeme > Informations systeme. Redemarre si un renommage est en attente.'
Test-Setting account 'Compte local actif' $profile.UserName {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $account=Get-CimInstance Win32_UserAccount -Filter "SID='$sid'" -ErrorAction Stop
    if(-not $account){throw 'Identite du compte actif indisponible.'}
    if(-not $account.LocalAccount){return 'Compte non local'}
    if($account.Disabled){return 'Compte desactive'}
    if($sid.EndsWith('-500')){return 'Compte integre Windows'}
    $account.Name
} 'Connecte-toi au compte local choisi pendant la preparation, puis relance le controle dans Bastos.'
Test-Setting shortcut 'Raccourci Bastos sur le Bureau' 'Verified' {
    $desktop=[Environment]::GetFolderPath('DesktopDirectory')
    if(-not $desktop){throw 'Bureau du compte actif indisponible.'}
    $link=Join-Path $desktop 'BASTOS.lnk'
    if(-not(Test-Path -LiteralPath $link -PathType Leaf)){return 'Absent'}
    $shell=New-Object -ComObject WScript.Shell
    try{
        $shortcut=$shell.CreateShortcut($link)
        $target=[string]$shortcut.TargetPath
        if($target -notmatch '^[A-Za-z]:\\'){return 'Cible locale requise'}
        if([IO.Path]::GetFileName($target) -ine 'BASTOS-Native.exe' -or -not(Test-Path -LiteralPath $target -PathType Leaf)){return 'Cible absente ou incorrecte'}
        $appRoot=Split-Path -Parent (Split-Path -Parent $target)
        if($profile.PSObject.Properties['ApplicationPlacement'] -and $profile.ApplicationPlacement -eq 'Windows'){
            $expectedTarget=Join-Path $env:ProgramData 'BASTOS-ISO\Bastos.Native\BASTOS-Native.exe'
            if($target -ine $expectedTarget){return 'Application Bastos hors du lecteur Windows'}
            $volume=Get-Volume -FilePath $target -ErrorAction Stop
            $windowsPartition=Get-Partition -DriveLetter ([string]$env:SystemDrive).Substring(0,1) -ErrorAction Stop
            $appPartition=Get-Partition -Volume $volume -ErrorAction Stop
            if([guid]$appPartition.Guid -ne [guid]$windowsPartition.Guid){return 'Application Bastos hors de C:'}
        }elseif($profile.RecoveryPartitionGuid -or $profile.WindowsDiskIdentity){
            $volume=Get-Volume -FilePath $target -ErrorAction Stop
            $partition=Get-Partition -Volume $volume -ErrorAction Stop
            $disk=Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
            if([guid]$partition.Guid -ne [guid]$profile.RecoveryPartitionGuid -or [guid]$disk.Guid -ne [guid]$profile.WindowsDiskIdentity){return 'Disque ou partition Recovery different'}
            $expectedTarget=Join-Path (([string]$volume.DriveLetter)+':\') 'Application\Bastos.Native\BASTOS-Native.exe'
            if($target -ine $expectedTarget){return 'Application differente du profil'}
        }
        $build=Get-Content -LiteralPath (Join-Path $appRoot 'BASTOS-Build.json') -Raw -Encoding UTF8|ConvertFrom-Json
        if($build.NativeAppSha256 -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $build.NativeAppSha256){return 'Executable different du manifeste Bastos'}
        if($shortcut.WorkingDirectory -ine (Split-Path -Parent $target) -or $shortcut.IconLocation -ine ($target+',0')){return 'Cible ou icone incorrecte'}
        'Verified'
    }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
} 'Verifie le raccourci Bureau et l application sur C:. Consulte le journal Rufus-FirstLogon si sa creation a echoue.'
Test-Setting finalization 'Finalisation du premier demarrage' 'Completed' {
    $marker=Join-Path (Split-Path -Parent $ProfilePath) 'Logs\Rufus-FirstLogon.ok'
    if(-not(Test-Path -LiteralPath $marker -PathType Leaf)){return 'Non confirmee'}
    if($profile.Schema -eq 2){
        $receipt=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
        if($receipt.ProfileId -ne $profile.ProfileId -or $receipt.ProfileSha256 -ine (Get-FileHash -LiteralPath $ProfilePath).Hash){return 'Finalisation d un autre profil'}
        $machine=[Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography','MachineGuid',$null)
        if(-not $machine -or $receipt.MachineGuid -ne $machine -or ([datetime]$receipt.CompletedUtc).ToUniversalTime() -lt ([datetime]$profile.CreatedUtc).ToUniversalTime()){return 'Finalisation ancienne ou d un autre Windows'}
    }
    'Completed'
} 'La finalisation peut encore etre en cours. Attends sa fin puis clique sur Recontroler. Si le probleme persiste, consulte Rufus-FirstLogon.log.'
if($profile.Schema -eq 2){
    Import-Module (Join-Path $PSScriptRoot 'Bastos.InstallationOptions.psm1') -Force -ErrorAction Stop
    foreach($check in @(Get-BastosInstallationOptionChecks $profile)){$checks.Add($check)}
}
$report=[ordered]@{
    Schema=[int]$profile.Schema;RequestId=$RequestId;ProfileId=$profile.ProfileId
    ProfileSha256=(Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    CheckedUtc=[DateTime]::UtcNow.ToString('o')
    MachineGuid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
    UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Checks=@($checks.ToArray())
}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($ResultPath))
New-Item -ItemType Directory -Path $parent -Force|Out-Null
$temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
try{
    [IO.File]::WriteAllText($temporary,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
