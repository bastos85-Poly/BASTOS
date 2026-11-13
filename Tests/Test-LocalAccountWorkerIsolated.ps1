param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$temp=Join-Path $env:TEMP ('Bastos-SAM-Mock-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp|Out-Null
$count=0
function Check($ok,$message){if(-not $ok){throw $message};$script:count++}
try {
    $worker=Get-Content (Join-Path $SourceRoot 'InstallerScripts\Initialize-BASTOS-LocalAccount.ps1') -Raw
    # Instrument a COPY of the worker. All native calls and ADSI casts are
    # replaced by in-memory fake types; the production guard is tested separately.
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$tokens,[ref]$errors)
    $native=$ast.Find({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith("if(-not ('BastosLocalAccountNative'")},$true)
    Check ($null -ne $native) 'Native declaration found for fixture replacement'
    $worker=$worker.Remove($native.Extent.StartOffset,$native.Extent.EndOffset-$native.Extent.StartOffset)
    $worker=$worker.Replace('$identity=[Security.Principal.WindowsIdentity]::GetCurrent()',"`$identity=[pscustomobject]@{User=[pscustomobject]@{Value='S-1-5-18'}}")
    $worker=$worker.Replace('[ADSI]','[BastosFakeAdsi]')
    Check ($worker -notmatch 'DllImport|\[ADSI\]|WindowsIdentity\]::GetCurrent') 'No real native API or ADSI available in fixture'
    $fixture=Join-Path $temp 'FixtureWorker.ps1';[IO.File]::WriteAllText($fixture,$worker,[Text.UTF8Encoding]::new($true))
    $harness=Join-Path $temp 'Harness.ps1'
    @'
param([string]$Root,[string]$Scenario)
$ErrorActionPreference='Stop'
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct BastosLocalUser1 {public string Name;public string Password;public uint Privilege;public uint Flags;public string Comment;}
public struct BastosLocalPassword {public string Password;}
public class BastosFakeAdsi {
 public static int Writes; public static implicit operator BastosFakeAdsi(string value){return new BastosFakeAdsi();}
 public void Put(string key,object value){Writes++;} public void SetInfo(){Writes++;}
 public bool IsMember(string value){return true;} public void Add(string value){Writes++;}
}
public static class BastosLocalAccountNative {
 public static bool Exists;public static int Adds;public static int Sets;public static int Probes;public static int Status;public static bool Probe=true;public static bool Restricted;public static bool WrongRestricted;public static bool PasswordRequired;
 [DllImport("kernel32.dll",EntryPoint="SetLastError",SetLastError=true)]public static extern void SetThreadError(uint code);
 public static int NetUserAdd(string s,int l,ref BastosLocalUser1 i,out uint p){p=0;Adds++;if(i.Password!="" || i.Privilege!=1 || i.Flags!=0x10221)throw new Exception("Wrong account inputs");if(Status==0)Exists=true;return Status;}
 public static int NetUserSetInfo(string s,string n,int l,ref BastosLocalPassword i,out uint p){p=0;Sets++;if(i.Password!="" || l!=1003)throw new Exception("Wrong password inputs");return Status;}
 public static bool LogonUser(string n,string d,string p,int t,int v,out IntPtr token){Probes++;token=IntPtr.Zero;if(t!=2)throw new Exception("Wrong logon type");if(Restricted){if(p!="" && !p.StartsWith("NeverSet-BASTOS-"))throw new Exception("Unexpected credential");SetThreadError((uint)(p=="" || WrongRestricted ?1327:1326));return false;}if(p!="")throw new Exception("Unexpected credential");if(!Probe)SetThreadError(1326);return Probe;}
 public static bool CloseHandle(IntPtr token){return true;}
}
"@
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{SystemSetupInProgress=1}}
function Get-CimInstance {
 param($ClassName,$Filter,$ErrorAction)
 switch($ClassName){
  'Win32_UserAccount' {if([BastosLocalAccountNative]::Exists){[pscustomobject]@{Name='BastOS';SID='S-1-5-21-1-2-3-1001';Disabled=$false;Lockout=$false;PasswordRequired=[BastosLocalAccountNative]::PasswordRequired}}}
  'Win32_Group' {[pscustomobject]@{Name='Administrators'}}
  'Win32_ComputerSystem' {[pscustomobject]@{Name='TEST-PC'}}
  default {throw 'Unexpected CIM call'}
 }
}
$profilePath=Join-Path $Root 'Installation-Expected.json'
$logRoot=Join-Path $Root 'Logs';New-Item -ItemType Directory $logRoot -Force|Out-Null
$receipt=Join-Path $logRoot 'LocalAccount-State.json'
switch($Scenario){
 'policy' {[BastosLocalAccountNative]::Status=2245}
 'probe-failure' {[BastosLocalAccountNative]::Probe=$false}
 'restricted-blank' {[BastosLocalAccountNative]::Restricted=$true}
 'restriction-before-password' {[BastosLocalAccountNative]::Restricted=$true;[BastosLocalAccountNative]::WrongRestricted=$true}
 'restricted-password-required' {[BastosLocalAccountNative]::Restricted=$true;[BastosLocalAccountNative]::PasswordRequired=$true}
 'preexisting' {[BastosLocalAccountNative]::Exists=$true}
 'resume' {[BastosLocalAccountNative]::Exists=$true;@{Stage='Created';ProfileSha256=(Get-FileHash $profilePath).Hash;Sid='S-1-5-21-1-2-3-1001'}|ConvertTo-Json|Set-Content $receipt}
 'verify' {[BastosLocalAccountNative]::Exists=$true;@{Stage='Verified';ProfileSha256=(Get-FileHash $profilePath).Hash;Sid='S-1-5-21-1-2-3-1001'}|ConvertTo-Json|Set-Content $receipt}
 'verify-missing' {[BastosLocalAccountNative]::Exists=$true}
 'profile-changed' {[BastosLocalAccountNative]::Exists=$true;@{Stage='Created';ProfileSha256='wrong';Sid='S-1-5-21-1-2-3-1001'}|ConvertTo-Json|Set-Content $receipt}
 'bad-mode' {$profile=Get-Content $profilePath -Raw|ConvertFrom-Json;$profile.PasswordMode='Password';$profile|ConvertTo-Json|Set-Content $profilePath}
 'missing-profile' {Remove-Item -LiteralPath $profilePath}
}
$parameters=@{ProfilePath=$profilePath}
if($Scenario -like 'verify*'){$parameters.VerifyOnly=$true}
try { $ErrorActionPreference='Continue'; & (Join-Path $Root 'FixtureWorker.ps1') @parameters; $workerExit=$LASTEXITCODE } finally {
 @{Adds=[BastosLocalAccountNative]::Adds;Sets=[BastosLocalAccountNative]::Sets;Probes=[BastosLocalAccountNative]::Probes;AdsiWrites=[BastosFakeAdsi]::Writes}|ConvertTo-Json|Set-Content (Join-Path $Root 'Calls.json')
}
exit $workerExit
'@ | Set-Content $harness -Encoding UTF8
    foreach($scenario in @('success','resume','verify','restricted-blank','restriction-before-password','restricted-password-required','policy','probe-failure','preexisting','verify-missing','profile-changed','bad-mode','missing-profile')){
        $dir=Join-Path $temp $scenario;New-Item -ItemType Directory $dir|Out-Null
        Copy-Item $fixture (Join-Path $dir 'FixtureWorker.ps1')
        @{UserName='BastOS';AccountProvisioning='SpecializePasswordlessV1';PasswordMode='Empty'}|ConvertTo-Json|Set-Content (Join-Path $dir 'Installation-Expected.json')
        $stdout=Join-Path $dir 'out.log';$stderr=Join-Path $dir 'error.log'
        $args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Root "{1}" -Scenario "{2}"' -f $harness,$dir,$scenario
        $process=Start-Process powershell.exe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $success=$scenario -in @('success','resume','verify','restricted-blank')
        Check ($process.ExitCode -eq $(if($success){0}else{31})) ('Exit code: '+$scenario+'; '+(Get-Content $stderr -Raw))
        $calls=Get-Content (Join-Path $dir 'Calls.json') -Raw|ConvertFrom-Json
        if($scenario -in @('preexisting','verify-missing','profile-changed','bad-mode','missing-profile','verify')){Check ($calls.Adds -eq 0 -and $calls.Sets -eq 0 -and $calls.AdsiWrites -eq 0) ('No account writes: '+$scenario)}
        if($success){$state=Get-Content (Join-Path $dir 'Logs\LocalAccount-State.json') -Raw|ConvertFrom-Json;Check ($state.Stage -eq 'Verified' -and $state.PasswordVerified) ('Verified receipt: '+$scenario)}
        if($scenario -eq 'resume'){Check ($calls.Adds -eq 0 -and $calls.Sets -eq 1) 'Interrupted provisioning resumes only its own account'}
        if($scenario -eq 'probe-failure'){Check ($calls.Probes -eq 2) 'Both local domains tried; no false success'}
        if($scenario -eq 'restricted-blank'){Check ($state.ProofMethod -eq 'BlankRestriction1327WrongCredential1326' -and -not $state.InteractiveApiAccepted -and $state.WrongPasswordRejected) 'Policy restriction is distinguished without claiming API logon success'}
    }
    Write-Output "PASS : $count isolated SAM checks; all Windows account APIs replaced by fakes."
} finally {
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup refused'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
