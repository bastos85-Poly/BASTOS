$ErrorActionPreference='Stop'
try{
    $expected=Get-Content C:\VM-Lab\Expected.json -Raw|ConvertFrom-Json
    $computer=Get-CimInstance Win32_ComputerSystem
    if($computer.Manufacturer -ne 'Microsoft Corporation' -or $computer.Model -ne 'Virtual Machine' -or
       (Get-Content D:\BASTOS-VM-KEEP.txt -Raw) -ne $expected.LabId){throw 'Sonde refusee hors VM de laboratoire.'}
    $deadline=[DateTime]::UtcNow.AddMinutes(8)
    while(-not(Test-Path C:\ProgramData\BASTOS-ISO\Logs\Rufus-FirstLogon.ok) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 3}
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LabLocalLogon {
 [DllImport("advapi32.dll",SetLastError=true,CharSet=CharSet.Unicode)]
 public static extern bool LogonUser(string user,string domain,string password,int type,int provider,out IntPtr token);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
    $token=[IntPtr]::Zero
    $blankAccepted=[LabLocalLogon]::LogonUser('BastosLab',$env:COMPUTERNAME,'',2,0,[ref]$token)
    $logonError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if($token -ne [IntPtr]::Zero){[void][LabLocalLogon]::CloseHandle($token)}
    $wrongToken=[IntPtr]::Zero
    $wrongAccepted=[LabLocalLogon]::LogonUser('BastosLab',$env:COMPUTERNAME,('Never-configured-'+[guid]::NewGuid().ToString('N')),2,0,[ref]$wrongToken)
    $wrongError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if($wrongToken -ne [IntPtr]::Zero){[void][LabLocalLogon]::CloseHandle($wrongToken)}
    $os=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $account=Get-LocalUser BastosLab
    $keyboardRegistry=(Get-ItemProperty 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue).'1'
    $c=Get-Partition -DriveLetter C;$d=Get-Partition -DriveLetter D
    $efi=@(Get-Partition|Where-Object GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}')
    $checks=[ordered]@{
        CandidateBinary=((Get-FileHash D:\Application\Bastos.Native\BASTOS-Native.exe).Hash -eq $expected.CandidateSha256)
        WindowsPro=($os.EditionID -eq 'Professional')
        ComputerName=($env:COMPUTERNAME -eq 'BASTOS-VMNEW')
        LocalUser=($env:USERNAME -eq 'BastosLab' -and (Get-LocalUser BastosLab).SID.Value -notmatch '-500$')
        Passwordless=([bool]$blankAccepted -or (-not $account.PasswordRequired -and $logonError -eq 1327 -and -not $wrongAccepted -and $wrongError -eq 1326))
        French=((Get-Culture).Name -eq 'fr-FR' -and (Get-WinSystemLocale).Name -eq 'fr-FR')
        Azerty=($keyboardRegistry -eq '0000040C' -or @(Get-WinUserLanguageList|ForEach-Object InputMethodTips) -contains '040C:0000040C')
        DesktopObserved=([bool]$expected.DesktopObserved -and @(Get-Process explorer -ErrorAction SilentlyContinue).Count -gt 0)
        SingleVirtualDisk=(@(Get-Disk).Count -eq 1 -and $c.DiskNumber -eq $d.DiskNumber)
        RecoveryGuid=([guid]$d.Guid -eq [guid]$expected.RecoveryGuid)
        WindowsRecreated=([guid]$c.Guid -ne [guid]$expected.OldWindowsGuid)
        EfiPolicy=($efi.Count -eq 1 -and (([guid]$efi[0].Guid -eq [guid]$expected.OldEfiGuid) -eq [bool]$expected.KeepEfi))
    }
    if($expected.PSObject.Properties['RequireFirstLogon'] -and $expected.RequireFirstLogon){
        $checks['FirstLogonComplete']=(Test-Path C:\ProgramData\BASTOS-ISO\Logs\Rufus-FirstLogon.ok)
        $checks['DesktopShortcut']=(Test-Path (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'BASTOS.lnk'))
    }
    $result=[ordered]@{CheckedUtc=[DateTime]::UtcNow.ToString('o');Passed=(@($checks.Values|Where-Object {$_ -ne $true}).Count -eq 0);Checks=$checks;LocalLogonError=$(if($blankAccepted){0}else{$logonError});WrongPasswordError=$wrongError;PasswordRequired=$account.PasswordRequired;PasswordLastSet=$account.PasswordLastSet;Edition=$os.EditionID;ComputerName=$env:COMPUTERNAME;User=$env:USERNAME;Culture=(Get-Culture).Name;KeyboardRegistry=$keyboardRegistry;Keyboard=@(Get-WinUserLanguageList|ForEach-Object InputMethodTips);Explorer=@(Get-Process explorer -ErrorAction SilentlyContinue).Count;DesktopShortcut=(Test-Path (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'BASTOS.lnk'));RufusFirstLogonComplete=(Test-Path C:\ProgramData\BASTOS-ISO\Logs\Rufus-FirstLogon.ok);Partitions=@(Get-Partition|Select-Object PartitionNumber,Guid,GptType,DriveLetter,Size)}
}catch{$result=[ordered]@{Passed=$false;Error=$_.Exception.Message;CheckedUtc=[DateTime]::UtcNow.ToString('o')}}
$result.RunId=$expected.RunId
[IO.File]::WriteAllText('D:\VM-Test-Results\PostInstallProbe.json',($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$startupLink=Join-Path ([Environment]::GetFolderPath('Startup')) 'BASTOS-VmLabProbe.lnk'
if([IO.File]::Exists($startupLink)){[IO.File]::Delete($startupLink)}

$common=Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'BASTOS-VmLabProbe.lnk'
try{if([IO.File]::Exists($common)){[IO.File]::Delete($common)}}catch{}
$pc=Get-CimInstance Win32_ComputerSystem
if($pc.Model -eq 'Virtual Machine' -and $pc.Manufacturer -eq 'Microsoft Corporation' -and $expected.LabId -match '^[a-fA-F0-9]{32}$' -and (Get-Content D:\BASTOS-VM-KEEP.txt -Raw) -eq $expected.LabId){& "$env:SystemRoot\System32\shutdown.exe" /s /t 3 /f}
