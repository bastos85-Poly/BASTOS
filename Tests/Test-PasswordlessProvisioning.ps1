param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$count=0
function Check($ok,[string]$message){if(-not $ok){throw $message};$script:count++}
function Refuses([scriptblock]$action,[string]$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $message}
$scripts=Join-Path $SourceRoot 'InstallerScripts'
Import-Module (Join-Path $scripts 'Bastos.Rufus.psm1') -Force
$tokens=$null;$errors=$null
$recoveryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts 'Initialize-BASTOS-Recovery.ps1'),[ref]$tokens,[ref]$errors)
$recoveryFunction=$recoveryAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-RecoveryAnswerFile'},$true)
if(-not $recoveryFunction){throw 'Recovery XML generator missing'}
# Load only the pure XML function, never the disk/boot worker entry point.
. ([scriptblock]::Create($recoveryFunction.Extent.Text))
$temp=Join-Path $env:TEMP ('Bastos-Passwordless-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try {
    $tokens=$null;$errors=$null
    $winreAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts 'Integrate-WinRE-Into-BASTOS.ps1'),[ref]$tokens,[ref]$errors)
    $winreFunction=$winreAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-BastosWinREEnabled'},$true)
    . ([scriptblock]::Create($winreFunction.Extent.Text))
    Check (Test-BastosWinREEnabled 'Windows RE status: Enabled') 'WinRE enabled in English'
    Check (Test-BastosWinREEnabled 'Etat Windows RE : Activé') 'WinRE enabled in French'
    Check (-not (Test-BastosWinREEnabled 'Windows RE status: Disabled')) 'Disabled WinRE never accepted'
    Check (-not (Test-BastosWinREEnabled 'Etat Windows RE : Désactivé')) 'French disabled WinRE never accepted'
    Check (-not (Test-BastosWinREEnabled 'Unrelated service: Enabled')) 'Unrelated enabled status never accepted'
    $iso=Join-Path $temp 'fixture.iso';[IO.File]::WriteAllText($iso,'Generation XML only; not an installation image')
    foreach($user in @('BastOS','Alice Test')){
        foreach($auto in @($true,$false)){
            $dir=Join-Path $temp ($user.Replace(' ','')+'-'+$auto);New-Item -ItemType Directory $dir|Out-Null
            $options=[pscustomobject]@{Schema=1;UserName=$user;ComputerName='TEST-PC';WindowsLocale='fr-FR';WindowsUILanguage='fr-FR';KeyboardLayout='040C:0000040C';KeepOnlyRecoveryPartition=$true;BypassHardwareChecks=$false;DisableTelemetry=$false;DisableConsumerContent=$false;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$false;RecoveryPartitionGuid='';WindowsDiskIdentity='';AutoLogonEnabled=$auto}
            $optionsPath=Join-Path $dir 'Options.json';$options|ConvertTo-Json|Set-Content $optionsPath -Encoding UTF8
            $answerPath=Join-Path $dir 'answer.xml'
            & (Join-Path $scripts 'New-BASTOS-Official-Unattend.ps1') -OfficialIsoPath $iso -OutputPath $answerPath -WindowsLocale fr-FR -KeyboardLayout '040C:0000040C' -OptionsPath $optionsPath|Out-Null
            [xml]$answer=Get-Content $answerPath -Raw
            $payload=Join-Path $dir 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
            $profile=Get-Content (Join-Path $payload 'Installation-Expected.json') -Raw|ConvertFrom-Json
            Check (Test-BastosRufusAccountFlow $answer $profile) "Generated XML and profile: $user / AutoLogon=$auto"
            Check ($profile.UserName -ceq $user -and $profile.ComputerName -ceq 'TEST-PC') 'User choices preserved'
            Check ((Get-FileHash (Join-Path $payload 'Initialize-BASTOS-LocalAccount.ps1')).Hash -eq $profile.AccountWorkerSha256) 'Worker included and hashed'
            $first=Get-Content (Join-Path $payload 'Rufus-FirstLogon.ps1') -Raw
            Check ($first -notmatch 'net.exe user|SetPassword|NetUserSetInfo|New-LocalUser|Set-LocalUser') 'No account mutation after sign-in'
            Check ($first.IndexOf('DefaultPassword') -lt $first.IndexOf('Invoke-BastosInstallationOptions')) 'AutoLogon cleanup before optional software'
            Set-BastosRufusAccountFlow $answer $options (Join-Path $payload 'Rufus-FirstLogon.ps1')
            $profile=Get-Content (Join-Path $payload 'Installation-Expected.json') -Raw|ConvertFrom-Json
            Check (Test-BastosRufusAccountFlow $answer $profile) 'Repeated generation has one account writer'
            $script:RufusOptions=$options
            foreach($edition in @('Core','Professional','EnterpriseS','IoTEnterpriseS')){
                foreach($round in 1,2){
                    New-RecoveryAnswerFile -SourcePath $answerPath -DestinationPath $answerPath -ProImageIndex 1 -EditionId $edition -ImageUILanguage fr-FR -PostInstallMode WindowsOnly -MachineWorkerPath (Join-Path $scripts 'Invoke-BASTOS-Specialize.ps1')
                    [xml]$recoveryAnswer=Get-Content $answerPath -Raw
                    $recoveryProfile=Get-Content (Join-Path $payload 'Installation-Expected.json') -Raw|ConvertFrom-Json
                    Check (Test-BastosRufusAccountFlow $recoveryAnswer $recoveryProfile) "Recovery generation $edition, round $round, AutoLogon=$auto"
                    Check ($recoveryProfile.UserName -ceq $user -and $recoveryProfile.ComputerName -ceq 'TEST-PC') 'Recovery preserves selected names'
                }
            }
            $ns=[Xml.XmlNamespaceManager]::new($answer.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
            $command=$answer.SelectSingleNode('//u:RunSynchronousCommand[u:Description="BASTOS local account before OOBE"]/u:Path',$ns)
            $old=$command.InnerText;$command.InnerText='missing.ps1'
            Refuses {Test-BastosRufusAccountFlow $answer $profile} 'Wrong specialize command rejected'
            $command.InnerText=$old
            $oldName=$profile.ComputerName;$profile.ComputerName='OTHER-PC'
            Refuses {Test-BastosRufusAccountFlow $answer $profile} 'Mismatched machine rejected'
            $profile.ComputerName=$oldName
            $options|Add-Member -NotePropertyName Password -NotePropertyValue 'fixture-secret'
            Refuses {Set-BastosRufusAccountFlow $answer $options (Join-Path $payload 'Rufus-FirstLogon.ps1')} 'Unsupported password rejected instead of silently erased'
            $options.PSObject.Properties.Remove('Password')
            $options.UserName='SYSTEM'
            Refuses {Set-BastosRufusAccountFlow $answer $options (Join-Path $payload 'Rufus-FirstLogon.ps1')} 'Reserved account rejected'
        }
    }
    $worker=Join-Path $scripts 'Initialize-BASTOS-LocalAccount.ps1'
    $workerText=Get-Content $worker -Raw
    # Compile the genuine P/Invoke declarations without calling the OS APIs.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'Worker PowerShell syntax'
    $interop=$ast.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('public static class BastosLocalAccountNative')},$true)|Select-Object -First 1
    Add-Type -TypeDefinition $interop.Value
    Check ([Runtime.InteropServices.Marshal]::SizeOf([type][BastosLocalUser1]) -eq 56) 'USER_INFO_1 x64 ABI layout'
    $password=[BastosLocalPassword]::new();$password.Password=''
    Check ($null -ne $password.Password -and $password.Password.Length -eq 0) 'Empty password is an allocated empty string'
    # Run the genuine guard: this must refuse to provision on the host.
    $savedPreference=$ErrorActionPreference
    try {$ErrorActionPreference='Continue'; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker -ProfilePath (Join-Path $temp 'missing.json') *> (Join-Path $temp 'guard.log');$guardExit=$LASTEXITCODE} finally {$ErrorActionPreference=$savedPreference}
    Check ($guardExit -eq 31) 'Host execution refused before any SAM write'
    Check ((Get-Content (Join-Path $temp 'guard.log') -Raw) -match 'SYSTEM') 'Refusal comes from the SYSTEM guard'
    # Match the real specialize/SetupComplete invocation, without ProfilePath.
    # Windows PowerShell 5.1 has not initialized PSScriptRoot in param defaults.
    try {$ErrorActionPreference='Continue'; & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker *> (Join-Path $temp 'default-guard.log');$defaultExit=$LASTEXITCODE} finally {$ErrorActionPreference=$savedPreference}
    Check ($defaultExit -eq 31) 'Real -File invocation with omitted profile reaches the safety guard'
    $defaultOutput=Get-Content (Join-Path $temp 'default-guard.log') -Raw
    Check ($defaultOutput -match 'SYSTEM' -and $defaultOutput -notmatch 'Join-Path') 'No parameter-binding failure before script logging'
    foreach($file in @(Get-ChildItem $scripts -File|Where-Object Extension -in '.ps1','.psm1')){
        $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
        Check ($errors.Count -eq 0) ('Syntax: '+$file.Name)
    }
    Refuses {[xml]'<unattend><broken></unattend>'} 'Malformed XML rejected'
    Write-Output "PASS : $count provisioning checks; XML generation, ABI, guards; no real account created."
} finally {
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup outside TEMP refused'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
