[CmdletBinding()]
param(
    [string]$ProfilePath = '',
    [switch]$VerifyOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if(-not $ProfilePath){$ProfilePath=Join-Path $PSScriptRoot 'Installation-Expected.json'}
$logRoot=Join-Path $PSScriptRoot 'Logs'
$receiptPath=Join-Path $logRoot 'LocalAccount-State.json'
function Write-AccountLog([string]$Message) {
    Add-Content -LiteralPath (Join-Path $logRoot 'LocalAccount.log') -Value ('{0:o} {1}' -f [DateTime]::UtcNow,$Message) -Encoding UTF8
}
try {
    # Never use this provisioning worker as a repair command on an existing PC.
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($identity.User.Value -ne 'S-1-5-18'){throw 'Execution reservee au compte SYSTEM pendant Windows Setup.'}
    $setup=Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction Stop
    if(-not $VerifyOnly -and [int]$setup.SystemSetupInProgress -ne 1){throw 'Windows Setup inactif : aucune modification de compte autorisee.'}
    New-Item -ItemType Directory -Path $logRoot -Force|Out-Null
    if(-not(Test-Path -LiteralPath $ProfilePath -PathType Leaf)){throw 'Profil de compte absent.'}
    $profile=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8|ConvertFrom-Json
    $name=[string]$profile.UserName
    if($name.Length -lt 1 -or $name.Length -gt 20 -or $name -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]*$' -or $name.EndsWith('.') -or
       $name -match '^(?i:Administrator|Administrateur|Guest|Invite|Invité|DefaultAccount|defaultuser0|WDAGUtilityAccount|HelpAssistant|KRBTGT|Local|NONE|SYSTEM)$') {throw 'Nom du compte invalide ou reserve.'}
    if($profile.AccountProvisioning -ne 'SpecializePasswordlessV1' -or $profile.PasswordMode -ne 'Empty'){throw 'Mode de compte incompatible : aucun mot de passe ne sera modifie.'}
    $profileHash=(Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    $computerName=[string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Name
    if([string]::IsNullOrWhiteSpace($computerName)){throw 'Identite locale indisponible.'}
    if(-not ('BastosLocalAccountNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct BastosLocalUser1 {
  public string Name; public string Password; public uint PasswordAge; public uint Privilege;
  public string Home; public string Comment; public uint Flags; public string Script;
}
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct BastosLocalPassword { public string Password; }
public static class BastosLocalAccountNative {
  [DllImport("netapi32.dll", CharSet=CharSet.Unicode)]
  public static extern int NetUserAdd(string server, int level, ref BastosLocalUser1 info, out uint error);
  [DllImport("netapi32.dll", CharSet=CharSet.Unicode)]
  public static extern int NetUserSetInfo(string server, string name, int level, ref BastosLocalPassword info, out uint error);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool LogonUser(string name,string domain,string password,int type,int provider,out IntPtr token);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
    }
    function Find-Account {
        @(Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop|Where-Object Name -IEQ $name)|Select-Object -First 1
    }
    $account=Find-Account
    $receipt=$null
    if(Test-Path -LiteralPath $receiptPath){$receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json}
    if($VerifyOnly) {
        if(-not $account -or -not $receipt -or $receipt.ProfileSha256 -ne $profileHash -or $receipt.Sid -ne [string]$account.SID -or $receipt.Stage -ne 'Verified'){throw 'Preuve de creation du compte absente ou divergente.'}
    } else {
        if($account -and (-not $receipt -or $receipt.ProfileSha256 -ne $profileHash -or $receipt.Sid -ne [string]$account.SID)) {
            throw 'Compte preexistant sans preuve de creation BASTOS : operation refusee.'
        }
        if(-not $account) {
            if($receipt){throw 'Compte disparu apres creation : operation refusee.'}
            $info=[BastosLocalUser1]::new();$info.Name=$name;$info.Password='';$info.Privilege=1
            # UF_SCRIPT | UF_NORMAL_ACCOUNT | UF_DONT_EXPIRE_PASSWD | UF_PASSWD_NOTREQD.
            $info.Flags=0x10221;$info.Comment='Compte local BASTOS sans mot de passe'
            [uint32]$parameterError=0
            $status=[BastosLocalAccountNative]::NetUserAdd($null,1,[ref]$info,[ref]$parameterError)
            if($status -ne 0){throw "Creation du compte refusee (NetUserAdd=$status, parametre=$parameterError)."}
            $account=Find-Account
            if(-not $account){throw 'Compte cree mais introuvable.'}
            # A crash before this receipt deliberately fails closed on retry.
            $created=[ordered]@{Schema=1;Stage='Created';ProfileSha256=$profileHash;UserName=$name;Sid=[string]$account.SID}
            [IO.File]::WriteAllText($receiptPath,($created|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
        if([string]$account.SID -match '-500$'){throw 'Le compte integre administrateur ne doit pas etre utilise.'}
        $password=[BastosLocalPassword]::new();$password.Password='';[uint32]$parameterError=0
        $status=[BastosLocalAccountNative]::NetUserSetInfo($null,$name,1003,[ref]$password,[ref]$parameterError)
        if($status -ne 0){throw "Mot de passe vide refuse (NetUserSetInfo=$status, parametre=$parameterError)."}
        $user=[ADSI]('WinNT://./{0},user' -f $name)
        $user.Put('FullName',$name);$user.Put('PasswordExpired',0);$user.SetInfo()
        $admin=Get-CimInstance Win32_Group -Filter "LocalAccount=True AND SID='S-1-5-32-544'" -ErrorAction Stop
        if(-not $admin){throw 'Groupe administrateurs introuvable.'}
        $group=[ADSI]('WinNT://./{0},group' -f $admin.Name)
        $member='WinNT://'+$computerName+'/'+$name
        if(-not $group.IsMember($member)){$group.Add($member)}
    }
    $account=Find-Account
    if(-not $account -or [bool]$account.Disabled -or [bool]$account.Lockout -or [string]$account.SID -match '-500$'){throw 'Compte absent, desactive, verrouille ou integre.'}
    $ok=$false;$code=0
    foreach($domain in @($computerName,'.')){
        $token=[IntPtr]::Zero
        $ok=[BastosLocalAccountNative]::LogonUser($name,$domain,'',2,0,[ref]$token)
        $code=if($ok){0}else{[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
        if($token -ne [IntPtr]::Zero){[void][BastosLocalAccountNative]::CloseHandle($token)}
        if($ok){break}
    }
    $proofMethod='InteractiveLogon'
    $wrongPasswordRejected=$null
    if(-not $ok){
        # Windows may enforce the blank-password restriction for a LogonUser
        # caller while still allowing the real local console session. Do not
        # disable that policy. Require a different result for a wrong credential.
        if($code -ne 1327 -or [bool]$account.PasswordRequired){throw "Connexion interactive sans mot de passe refusee (Win32=$code)."}
        $wrongToken=[IntPtr]::Zero
        $wrong=[BastosLocalAccountNative]::LogonUser($name,$computerName,('NeverSet-BASTOS-'+[guid]::NewGuid().ToString('N')),2,0,[ref]$wrongToken)
        $wrongCode=if($wrong){0}else{[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
        if($wrongToken -ne [IntPtr]::Zero){[void][BastosLocalAccountNative]::CloseHandle($wrongToken)}
        $wrongPasswordRejected=(-not $wrong -and $wrongCode -eq 1326)
        if(-not $wrongPasswordRejected){throw "Restriction sans preuve suffisante du mot de passe vide (vide=$code, errone=$wrongCode)."}
        $proofMethod='BlankRestriction1327WrongCredential1326'
        Write-AccountLog 'Mot de passe vide distingue d un identifiant errone ; restriction API Windows 1327 conservee. La session console reste a valider.'
    }
    $state=[ordered]@{Schema=1;Stage='Verified';ProfileSha256=$profileHash;UserName=$name;Sid=[string]$account.SID;PasswordVerified=$true;ProofMethod=$proofMethod;InteractiveApiAccepted=$ok;BlankApiError=$code;WrongPasswordRejected=$wrongPasswordRejected;VerifiedUtc=[DateTime]::UtcNow.ToString('o')}
    $temporary=$receiptPath+'.tmp'
    [IO.File]::WriteAllText($temporary,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $receiptPath -Force
    Write-AccountLog ('Compte local verifie ; methode='+$proofMethod+'; VerifyOnly='+[bool]$VerifyOnly)
    exit 0
} catch {
    try {Write-AccountLog ('ECHEC : '+$_.Exception.Message)} catch {}
    Write-Error $_ -ErrorAction Continue
    exit 31
}
