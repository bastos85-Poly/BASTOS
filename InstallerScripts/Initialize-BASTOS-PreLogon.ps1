[CmdletBinding()]
param(
    [string]$AccountMarkerPath = '',
    [string]$LogPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if(-not $AccountMarkerPath){$AccountMarkerPath=Join-Path $PSScriptRoot 'BASTOS-LocalAccount.txt'}
if(-not $LogPath){$LogPath=Join-Path $PSScriptRoot 'Logs\PreLogon.log'}

if(-not ('BastosPreLogonNative' -as [type])){
    Add-Type @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct BastosUserInfo1003
{
    [MarshalAs(UnmanagedType.LPWStr)]
    public string Password;
}

public static class BastosPreLogonNative
{
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool LogonUser(
        string username,
        string domain,
        string password,
        int logonType,
        int logonProvider,
        out IntPtr token);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int NetUserSetInfo(
        string serverName,
        string userName,
        int level,
        ref BastosUserInfo1003 buffer,
        out uint parameterError);
}
'@
}

function Write-PreLogonLog {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','OK','WARNING','ERROR')][string]$Level='INFO')
    $parent = Split-Path -Parent $LogPath
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    Add-Content -LiteralPath $LogPath -Value ('{0:o} [{1}] {2}' -f [DateTime]::Now,$Level,$Message) -Encoding UTF8
}

function Get-LocalAccounts {
    @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop)
}

function Get-LocalAccountByName {
    param([Parameter(Mandatory)][string]$Name)
    @(Get-LocalAccounts | Where-Object { [string]$_.Name -ieq $Name }) | Select-Object -First 1
}

function Get-BuiltInAdministrator {
    for($attempt=1;$attempt -le 15;$attempt++){
        try{
            $account=@(Get-LocalAccounts | Where-Object { [string]$_.SID -match '-500$' }) | Select-Object -First 1
            if($account){return $account}
        }catch{
            if($attempt -eq 15){throw}
        }
        if($attempt -lt 15){Start-Sleep -Seconds 2}
    }
    $null
}

function Set-LocalAccountPasswordEmpty {
    param([Parameter(Mandatory)][string]$Name)
    $errors=[Collections.Generic.List[string]]::new()
    try{
        # NetUserSetInfo niveau 1003 transmet une vraie chaine vide a la SAM.
        # Il ne depend ni du decoupage des arguments de net.exe, ni du cache ADSI.
        $passwordInfo=[BastosUserInfo1003]::new()
        $passwordInfo.Password=''
        [uint32]$parameterError=0
        $status=[BastosPreLogonNative]::NetUserSetInfo($null,$Name,1003,[ref]$passwordInfo,[ref]$parameterError)
        if($status -ne 0){throw "NetUserSetInfo=$status parameter=$parameterError"}
        Write-PreLogonLog ("Mot de passe vide applique par NetUserSetInfo pour {0}." -f $Name) 'OK'
        return
    }catch{
        [void]$errors.Add(('NetUserSetInfo : {0}' -f $_.Exception.Message))
    }
    try{
        # Premier filet de compatibilite pour les environnements ou NetAPI est
        # temporairement indisponible pendant specialize.
        $net=Join-Path $env:SystemRoot 'System32\net.exe'
        $arguments='user "{0}" "" /active:yes' -f $Name
        $process=Start-Process -FilePath $net -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
        if($process.ExitCode -ne 0){throw "net.exe $($process.ExitCode)"}
        Write-PreLogonLog ("Mot de passe vide applique par net.exe pour {0}." -f $Name) 'OK'
        return
    }catch{
        [void]$errors.Add(('net.exe : {0}' -f $_.Exception.Message))
    }
    try{
        $account=[ADSI]('WinNT://./{0},user' -f $Name)
        $account.SetPassword('')
        $account.SetInfo()
        Write-PreLogonLog ("Mot de passe vide applique par ADSI pour {0}." -f $Name) 'OK'
        return
    }catch{
        [void]$errors.Add(('ADSI : {0}' -f $_.Exception.Message))
    }
    throw ('Impossible de vider le mot de passe du compte {0}. {1}' -f $Name,($errors -join ' | '))
}

function Add-LocalAdministratorsMembership {
    param([Parameter(Mandatory)][string]$Name)
    $administrators=Get-CimInstance -ClassName Win32_Group -Filter 'LocalAccount=True' | Where-Object { $_.SID -eq 'S-1-5-32-544' } | Select-Object -First 1
    if(-not $administrators){throw 'Le groupe Administrators local est introuvable.'}
    $group=[ADSI]('WinNT://./{0},group' -f $administrators.Name)
    $memberPath='WinNT://./{0},user' -f $Name
    try{$group.Add($memberPath)}catch{
        if($_.Exception.Message -notmatch '(?i)already|deja|déjà|membre'){throw}
    }
}

function Set-LocalAccountFullName {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$FullName)
    $account=[ADSI]('WinNT://./{0},user' -f $Name)
    $account.Put('FullName',$FullName)
    $account.SetInfo()
}

function Disable-LocalAccountByName {
    param([Parameter(Mandatory)][string]$Name)
    & "$env:SystemRoot\System32\net.exe" user $Name /active:no | Out-Null
    if($LASTEXITCODE -ne 0){throw "Impossible de desactiver le compte local $Name (net.exe $LASTEXITCODE)."}
}

function Disable-BuiltInAdministrator {
    $builtIn=Get-BuiltInAdministrator
    if(-not $builtIn){return}
    if([string]$builtIn.Name -ieq 'BastOS'){
        throw 'Le compte BastOS ne doit jamais etre le compte integre SID-500.'
    }
    if(-not [bool]$builtIn.Disabled){
        Disable-LocalAccountByName -Name ([string]$builtIn.Name)
        Write-PreLogonLog ("Compte integre SID-500 desactive : {0}." -f $builtIn.Name) 'OK'
    }
}

function Enable-LocalAccountByName {
    param([Parameter(Mandatory)][string]$Name)
    & "$env:SystemRoot\System32\net.exe" user $Name /active:yes | Out-Null
    if($LASTEXITCODE -ne 0){throw "Impossible d activer le compte local $Name (net.exe $LASTEXITCODE)."}
}

function Test-InteractiveBlankPassword {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string[]]$Domains)
    $attempts=@()
    foreach($domain in @($Domains | Select-Object -Unique)){
        $token=[IntPtr]::Zero
        $success=[BastosPreLogonNative]::LogonUser($Name,$domain,'',2,0,[ref]$token)
        $errorCode=if($success){0}else{[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
        if($token -ne [IntPtr]::Zero){[void][BastosPreLogonNative]::CloseHandle($token)}
        $attempts+=,[pscustomobject]@{Domain=$domain;Success=$success;Win32Error=$errorCode}
        if($success){
            return [pscustomobject]@{Success=$true;Domain=$domain;Attempts=$attempts}
        }
    }
    [pscustomobject]@{Success=$false;Domain='';Attempts=$attempts}
}

function Remove-DefaultUserZero {
    $computer=[ADSI]'WinNT://.,computer'
    foreach($account in @(Get-LocalAccounts | Where-Object { [string]$_.Name -ieq 'defaultuser0' })){
        $computer.Delete('user',[string]$account.Name)
        Write-PreLogonLog 'Le compte transitoire defaultuser0 a ete supprime.' 'OK'
    }
}

function Write-LocalPreLogonState {
    param(
        [Parameter(Mandatory)][string]$AccountName,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$AutoLogonDomain,
        [Parameter(Mandatory)][object[]]$ProbeAttempts
    )
    $state=[ordered]@{
        Schema=2;Stage='PreLogonPrepared';Success=$true;AccountName=$AccountName;ComputerName=$ComputerName
        PasswordEmpty=$true;PasswordRequired=$false;PasswordVerified=$true;AutoLogonDomain=$AutoLogonDomain
        ProbeAttempts=$ProbeAttempts;PreparedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'PreLogon-State.json'),($state|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}

function Write-RecoveryPreLogonState {
    param(
        [Parameter(Mandatory)][string]$AccountName,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$AutoLogonDomain,
        [Parameter(Mandatory)][object[]]$ProbeAttempts
    )
    try{
        $recovery=Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq 'BASTOS_RECOVERY' -and $_.DriveLetter } | Select-Object -First 1
        if(-not $recovery){return}
        $root=('{0}:\' -f $recovery.DriveLetter)
        $attemptMarker=Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'
        if(-not(Test-Path -LiteralPath $attemptMarker -PathType Leaf)){return}
        $attemptName=(Get-Content -LiteralPath $attemptMarker -Raw -Encoding UTF8).Trim()
        if($attemptName -notmatch '^Attempt-[0-9a-f]{32}$'){return}
        $attempt=Join-Path (Join-Path $root 'BASTOS-Diagnostics\Attempts') $attemptName
        if(-not(Test-Path -LiteralPath $attempt)){New-Item -ItemType Directory -Path $attempt -Force|Out-Null}
        $state=[ordered]@{
            Schema=1;AttemptId=$attemptName;Stage='PreLogonPrepared';Success=$true;AccountName=$AccountName;ComputerName=$ComputerName
            PasswordEmpty=$true;PasswordRequired=$false;PasswordVerified=$true;AutoLogonDomain=$AutoLogonDomain
            ProbeAttempts=$ProbeAttempts;PreparedUtc=[DateTime]::UtcNow.ToString('o');UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        }
        $preLogonStatePath=Join-Path $attempt 'PreLogon-State.json'
        [IO.File]::WriteAllText($preLogonStatePath,($state|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        $attemptStatePath=Join-Path $attempt 'State.json'
        $attemptState=[ordered]@{Schema=1;AttemptId=$attemptName;Stage='PreLogonPrepared';Success=$true;UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
        if(Test-Path -LiteralPath $attemptStatePath -PathType Leaf){
            try{
                $previous=Get-Content -LiteralPath $attemptStatePath -Raw -Encoding UTF8|ConvertFrom-Json
                foreach($property in $previous.PSObject.Properties){$attemptState[$property.Name]=$property.Value}
            }catch{$attemptState.PreviousStateReadError=$_.Exception.Message}
        }
        $attemptState.Stage='PreLogonPrepared';$attemptState.Success=$true;$attemptState.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        $attemptState.PasswordEmpty=$true;$attemptState.PasswordVerified=$true;$attemptState.AutoLogonDomain=$AutoLogonDomain
        [IO.File]::WriteAllText(($attemptStatePath+'.tmp'),($attemptState|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath ($attemptStatePath+'.tmp') -Destination $attemptStatePath -Force
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-LAST-ATTEMPT.json'),($attemptState|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        $lastAttemptText=@(
            "AttemptId=$attemptName",'Stage=PreLogonPrepared','Result=SUCCESS',"AccountName=$AccountName",
            'PasswordEmpty=true','PasswordVerified=true',"AutoLogonDomain=$AutoLogonDomain",('TimestampUtc='+[DateTime]::UtcNow.ToString('o'))
        )
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-LAST-ATTEMPT.txt'),$lastAttemptText,[Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath (Join-Path $root 'BASTOS-LAST-ERROR.txt'),(Join-Path $root 'BASTOS-LAST-ERROR.json') -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath (Join-Path $attempt 'Recovery-Timeline.log') -Value ('{0} PreLogonPrepared' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss,ff')) -Encoding UTF8
    }catch{
        Write-PreLogonLog ("Diagnostic Recovery pre-connexion indisponible : {0}" -f $_.Exception.Message) 'WARNING'
    }
}

function Write-RecoveryPreLogonFailure {
    param([Parameter(Mandatory)][string]$Message)
    try{
        $recovery=Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq 'BASTOS_RECOVERY' -and $_.DriveLetter } | Select-Object -First 1
        if(-not $recovery){return}
        $root=('{0}:\' -f $recovery.DriveLetter)
        $attemptMarker=Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'
        if(-not(Test-Path -LiteralPath $attemptMarker -PathType Leaf)){return}
        $attemptName=(Get-Content -LiteralPath $attemptMarker -Raw -Encoding UTF8).Trim()
        if($attemptName -notmatch '^Attempt-[0-9a-f]{32}$'){return}
        $attempt=Join-Path (Join-Path $root 'BASTOS-Diagnostics\Attempts') $attemptName
        if(-not(Test-Path -LiteralPath $attempt)){New-Item -ItemType Directory -Path $attempt -Force|Out-Null}
        $timestamp=Get-Date -Format 'dd/MM/yyyy HH:mm:ss,ff'
        Add-Content -LiteralPath (Join-Path $attempt 'PreLogon-Failure.log') -Value ("$timestamp $Message") -Encoding UTF8
        Add-Content -LiteralPath (Join-Path $attempt 'Recovery-Timeline.log') -Value ("$timestamp PreLogonFailed") -Encoding UTF8
        $attemptStatePath=Join-Path $attempt 'State.json'
        $attemptState=[ordered]@{Schema=1;AttemptId=$attemptName;Stage='PreLogonFailed';Success=$false;Message=$Message;UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
        if(Test-Path -LiteralPath $attemptStatePath -PathType Leaf){
            try{
                $previous=Get-Content -LiteralPath $attemptStatePath -Raw -Encoding UTF8|ConvertFrom-Json
                foreach($property in $previous.PSObject.Properties){$attemptState[$property.Name]=$property.Value}
            }catch{$attemptState.PreviousStateReadError=$_.Exception.Message}
        }
        $attemptState.Stage='PreLogonFailed';$attemptState.Success=$false;$attemptState.Message=$Message;$attemptState.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText(($attemptStatePath+'.tmp'),($attemptState|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath ($attemptStatePath+'.tmp') -Destination $attemptStatePath -Force
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-LAST-ATTEMPT.json'),($attemptState|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        $lastError=[ordered]@{Schema=1;AttemptId=$attemptName;Stage='PreLogonFailed';Success=$false;Message=$Message;UpdatedUtc=[DateTime]::UtcNow.ToString('o');Diagnostic=$attempt}
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-LAST-ERROR.json'),($lastError|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-LAST-ERROR.txt'),@("AttemptId=$attemptName",'Stage=PreLogonFailed','Result=FAILED',"Message=$Message","Timestamp=$timestamp","Diagnostic=$attempt"),[Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path $root 'BASTOS-LAST-ERROR.txt') -Destination (Join-Path $attempt 'Last-Error.txt') -Force
    }catch{}
}

function Initialize-BastosFirstStartPins {
    $layoutPath=Join-Path $PSScriptRoot 'LayoutModification.json'
    if(-not(Test-Path -LiteralPath $layoutPath -PathType Leaf)){throw "Disposition du menu Demarrer absente : $layoutPath"}
    $layout=Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not [bool]$layout.applyOnce -or @($layout.pinnedList).Count -eq 0){throw 'La disposition du menu Demarrer doit etre applyOnce et contenir les epingles BASTOS.'}

    $launcher=Join-Path $PSScriptRoot 'Bastos.Native\BASTOS-Native.exe'
    if(-not(Test-Path -LiteralPath $launcher -PathType Leaf)){throw "Lanceur BASTOS absent avant la premiere connexion : $launcher"}
    $commonPrograms=Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    if(-not(Test-Path -LiteralPath $commonPrograms)){New-Item -ItemType Directory -Path $commonPrograms -Force|Out-Null}
    $shortcutPath=Join-Path $commonPrograms 'BASTOS.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath=$launcher
    $shortcut.WorkingDirectory=$PSScriptRoot
    $shortcut.Description='BASTOS - maintenance, optimisations et pilotes officiels'
    $iconPath=Join-Path $PSScriptRoot 'Assets\Bastos-App.ico'
    if(Test-Path -LiteralPath $iconPath -PathType Leaf){$shortcut.IconLocation="$iconPath,0"}
    $shortcut.Save()

    $policyPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if(-not(Test-Path -LiteralPath $policyPath)){New-Item -Path $policyPath|Out-Null}
    $provider='B5292708-1619-419B-9923-E5D9F3925E71'
    $currentPath='HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
    $providerPath="HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\$provider\default\Device\Start"
    $winner=(Get-ItemProperty -LiteralPath $currentPath -Name ConfigureStartPins_WinningProvider -ErrorAction SilentlyContinue).ConfigureStartPins_WinningProvider
    if($winner -and $winner -ne $provider){throw "Une autre gestion du menu Demarrer est active : $winner"}
    if(-not $winner -or $winner -eq $provider){
        foreach($name in @('ConfigureStartPins','ConfigureStartPins_ProviderSet','ConfigureStartPins_WinningProvider')){
            Remove-ItemProperty -LiteralPath $currentPath -Name $name -Force -ErrorAction SilentlyContinue
        }
        if(Test-Path -LiteralPath $providerPath){Remove-Item -LiteralPath $providerPath -Recurse -Force}
    }
    New-ItemProperty -LiteralPath $policyPath -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force|Out-Null
    New-ItemProperty -LiteralPath $policyPath -Name ConfigureStartPinsJSON -PropertyType ExpandString -Value $layoutPath -Force|Out-Null
    foreach($name in @('HideRecentlyAddedApps','HideRecommendedPersonalizedSites')){
        Remove-ItemProperty -LiteralPath $policyPath -Name $name -Force -ErrorAction SilentlyContinue
    }
    New-ItemProperty -LiteralPath $policyPath -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force|Out-Null
    Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoStartMenuMorePrograms -Force -ErrorAction SilentlyContinue
    Write-PreLogonLog 'Menu Demarrer prepare avant le premier profil : trois epingles, recommandations masquees, Toutes les applications visible et personnalisation autorisee.' 'OK'
}

try {
    if(-not(Test-Path -LiteralPath $AccountMarkerPath -PathType Leaf)){throw "Marqueur de compte absent : $AccountMarkerPath"}
    $accountName=(Get-Content -LiteralPath $AccountMarkerPath -Raw -Encoding UTF8).Trim()
    $standardName='BastOS'
    $standardFullName='BastOS'
    if($accountName -cne $standardName){throw "Le marqueur de compte doit etre strictement $standardName."}
    $computerName=([string]$env:COMPUTERNAME).Trim()
    if([string]::IsNullOrWhiteSpace($computerName)){throw 'Le nom local de la machine est indisponible.'}

    Write-PreLogonLog ("Validation du compte local BastOS sur {0}." -f $computerName)
    $localAccount=Get-LocalAccountByName -Name $standardName
    if(-not $localAccount){throw 'Le compte local BastOS cree par oobeSystem est introuvable.'}
    if([string]$localAccount.SID -match '-500$'){throw 'BastOS pointe a tort vers le compte integre SID-500.'}
    $accountName=$standardName
    Set-LocalAccountPasswordEmpty -Name $accountName
    Set-LocalAccountFullName -Name $accountName -FullName $standardFullName
    Enable-LocalAccountByName -Name $accountName
    Add-LocalAdministratorsMembership -Name $accountName
    Disable-BuiltInAdministrator

    $passwordState=Get-LocalAccountByName -Name $accountName
    if(-not $passwordState){throw 'Le compte BastOS est introuvable apres la mise a jour du mot de passe.'}
    if($passwordState.PSObject.Properties.Name -contains 'PasswordRequired' -and [bool]$passwordState.PasswordRequired){
        throw 'Windows indique encore qu un mot de passe est requis pour BastOS.'
    }
    # Le vrai nom de la machine est prioritaire. Les anciennes configurations
    # Domain=. ont produit 0x8007054B sur cette machine.
    $passwordProbe=Test-InteractiveBlankPassword -Name $accountName -Domains @($computerName, '.')
    if(-not $passwordProbe.Success){
        $probeDetails=(@($passwordProbe.Attempts|ForEach-Object{'{0}={1}' -f $_.Domain,$_.Win32Error}) -join ', ')
        throw "La connexion interactive locale sans mot de passe a echoue ($probeDetails)."
    }
    $autoLogonDomain=[string]$passwordProbe.Domain
    Write-PreLogonLog ("Connexion interactive sans mot de passe verifiee pour {0} avec le domaine local {1}." -f $accountName,$autoLogonDomain) 'OK'

    Remove-DefaultUserZero
    $accounts=Get-LocalAccounts
    foreach($duplicate in @($accounts | Where-Object {
        [string]$_.Name -ine $accountName -and [string]$_.FullName -ieq $accountName
    })){
        Disable-LocalAccountByName -Name ([string]$duplicate.Name)
        Write-PreLogonLog ("Identite d affichage dupliquee desactivee : {0}." -f $duplicate.Name) 'WARNING'
    }
    $winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    New-Item -Path $winlogon -Force|Out-Null
    New-ItemProperty -Path $winlogon -Name AutoAdminLogon -PropertyType String -Value '1' -Force|Out-Null
    New-ItemProperty -Path $winlogon -Name DefaultUserName -PropertyType String -Value $accountName -Force|Out-Null
    New-ItemProperty -Path $winlogon -Name DefaultDomainName -PropertyType String -Value $autoLogonDomain -Force|Out-Null
    New-ItemProperty -Path $winlogon -Name DefaultPassword -PropertyType String -Value '' -Force|Out-Null
    New-ItemProperty -Path $winlogon -Name AutoLogonCount -PropertyType DWord -Value 1 -Force|Out-Null
    Remove-ItemProperty -Path $winlogon -Name ForceAutoLogon -Force -ErrorAction SilentlyContinue

    $verified=Get-ItemProperty -LiteralPath $winlogon
    $verifiedDefaultPassword=if($verified.PSObject.Properties.Name -contains 'DefaultPassword'){[string]$verified.DefaultPassword}else{$null}
    if($verified.AutoAdminLogon -ne '1' -or $verified.DefaultUserName -ne $accountName -or
       $verified.DefaultDomainName -ne $autoLogonDomain -or
       $verifiedDefaultPassword -ne ''){
        throw 'La configuration AutoLogon locale n a pas pu etre verifiee.'
    }
    $finalAccount=Get-LocalAccountByName -Name $accountName
    if(-not $finalAccount -or [bool]$finalAccount.Disabled -or [string]$finalAccount.SID -match '-500$' -or [string]$finalAccount.FullName -cne $standardFullName -or
       ($finalAccount.PSObject.Properties.Name -contains 'PasswordRequired' -and [bool]$finalAccount.PasswordRequired)){
        throw 'Le compte local BastOS final est absent, desactive ou confondu avec SID-500.'
    }

    Initialize-BastosFirstStartPins
    Write-LocalPreLogonState -AccountName $accountName -ComputerName $computerName -AutoLogonDomain $autoLogonDomain -ProbeAttempts @($passwordProbe.Attempts)
    Write-RecoveryPreLogonState -AccountName $accountName -ComputerName $computerName -AutoLogonDomain $autoLogonDomain -ProbeAttempts @($passwordProbe.Attempts)
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'PreLogonPrepared.ok'),([DateTime]::UtcNow.ToString('o')),[Text.UTF8Encoding]::new($false))
    Write-PreLogonLog 'Compte local BastOS pret, mot de passe vide teste et ouverture locale explicite configuree.' 'OK'
    exit 0
} catch {
    try{
        $failedWinlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        if(Test-Path -LiteralPath $failedWinlogon){
            New-ItemProperty -Path $failedWinlogon -Name AutoAdminLogon -PropertyType String -Value '0' -Force|Out-Null
            Remove-ItemProperty -Path $failedWinlogon -Name AutoLogonCount,DefaultPassword,DefaultDomainName,DefaultUserName,ForceAutoLogon -Force -ErrorAction SilentlyContinue
        }
    }catch{}
    Write-PreLogonLog $_.Exception.Message 'ERROR'
    Write-RecoveryPreLogonFailure -Message $_.Exception.Message
    Write-Error $_
    exit 31
}
