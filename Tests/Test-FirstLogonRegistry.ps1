param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.InstallationOptions.psm1') -Force -PassThru
$fixture='Software\BASTOS\Tests\FirstLogon-'+[guid]::NewGuid().ToString('N')
$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
$count=0
function Check($ok,$name){if(-not $ok){throw $name};$script:count++}
try {
    $key=$base.CreateSubKey($fixture)
    $key.SetValue('Existing','preserved')
    $child=$key.CreateSubKey('Child');$child.SetValue('ExistingChild',42);$child.Dispose();$key.Dispose()
    foreach($round in 1,2){
        foreach($setting in @(
            @{Path=('HKCU:\'+$fixture);Name='First';Value=1},
            @{Path=('HKCU:\'+$fixture);Name='Second';Value=2},
            @{Path=('HKCU:\'+$fixture);Name='Text';Value='not-a-number';Type='String'},
            @{Path=('HKCU:\'+$fixture);Name='Binary';Value=[byte[]](0,127,255);Type='Binary'},
            [pscustomobject]@{Path=('HKCU:\'+$fixture);Name='Layout';Value='%ProgramData%\BASTOS-ISO\StartPins.json';Type='ExpandString'}
        )){& $module {param($setting) Set-BastosInstallationRegistrySetting $setting} $setting}
        $key=$base.OpenSubKey($fixture)
        try {
            Check ($key.GetValue('Existing') -eq 'preserved') "Existing value preserved, round $round"
            Check ($key.GetValue('First') -eq 1 -and $key.GetValue('Second') -eq 2) "Consecutive writes preserved, round $round"
            Check ($key.GetValueKind('First') -eq 'DWord') "Default DWORD type, round $round"
            Check ($key.GetValue('Text') -eq 'not-a-number' -and $key.GetValueKind('Text') -eq 'String') "Hashtable string type, round $round"
            Check ($key.GetValueKind('Binary') -eq 'Binary' -and ($key.GetValue('Binary') -join ',') -eq '0,127,255') "Binary layout preserved, round $round"
            Check ($key.GetValueKind('Layout') -eq 'ExpandString' -and $key.GetValue('Layout',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ceq '%ProgramData%\BASTOS-ISO\StartPins.json') "Unexpanded layout preserved, round $round"
            $child=$key.OpenSubKey('Child');try{Check ($child.GetValue('ExistingChild') -eq 42) "Child preserved, round $round"}finally{$child.Dispose()}
        } finally {$key.Dispose()}
    }
    $failed=$false;try{& $module {Set-BastosInstallationRegistrySetting @{Path='C:\Windows';Name='Invalid';Value=1}}}catch{$failed=$true}
    Check $failed 'Non-registry paths rejected'
    & $module {Initialize-BastosStartPolicyType}
    $type=[BastosClean.StartPolicy].Assembly.GetType('BastosClean.ILocalGpo')
    Check ($type.GUID -eq [guid]'EA502723-A23D-11D1-A7D3-0000F87571E3') 'Windows GPO interface identity'
    $instance=[Activator]::CreateInstance([type]::GetTypeFromCLSID([guid]'EA502722-A23D-11D1-A7D3-0000F87571E3',$true))
    try {Check ($type.IsInstanceOfType($instance)) 'Registered Windows GPO class exposes expected interface'} finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($instance)}
    $settingsRoot=Join-Path $env:TEMP ('Bastos-WidgetPolicy-'+[guid]::NewGuid().ToString('N'))
    $oldSystemRoot=$env:SystemRoot
    try {
        New-Item -ItemType Directory -Path (Join-Path $settingsRoot 'PolicyDefinitions') -Force|Out-Null
        $env:SystemRoot=$settingsRoot
        $flags=@{DisableTelemetry=$false;DisableConsumerContent=$false;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$true}
        $profile=[pscustomobject]@{Options=[pscustomobject]$flags}
        foreach($enabled in 0,1){
            [IO.File]::WriteAllText((Join-Path $settingsRoot 'PolicyDefinitions\NewsAndInterests.admx'),('<policyDefinitions><policies><policy name="DisableWidgetsBoard"><enabledValue><decimal value="'+$enabled+'"/></enabledValue></policy></policies></policyDefinitions>'))
            $settings=@(Get-BastosRequestedRegistrySettings $profile)
            Check (@($settings|Where-Object {$_.Name -eq 'DisableWidgetsBoard' -and $_.Value -eq $enabled}).Count -eq 1) "Widget policy follows actual enabled ADMX value $enabled"
            Check (@($settings|Where-Object {$_.Name -eq 'AllowNewsAndInterests' -and $_.Value -eq 0}).Count -eq 1) 'Established Widgets policy retained alongside preview policy'
            Check (@($settings|Where-Object Name -eq 'TaskbarDa').Count -eq 0) 'Widget policy does not require protected user preference'
        }
    } finally {
        $env:SystemRoot=$oldSystemRoot
        $allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
        if(-not [IO.Path]::GetFullPath($settingsRoot).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid temporary fixture path'}
        Remove-Item -LiteralPath $settingsRoot -Recurse -Force
    }
    & $module {
        function script:Get-AppxProvisionedPackage {[CmdletBinding()]param([switch]$Online) throw 'DISM unavailable'}
        function script:Get-BastosProvisionedPackagesViaWindowsApi { [pscustomobject]@{DisplayName='Microsoft.Windows.DevHome';PackageName='DevHome_fixture';PackageFamilyName='DevHome_family';Backend='WindowsApi'} }
        function script:Invoke-BastosDeprovisionByFamily {param($Family) $script:RemovedFamily=$Family}
    }
    $packages=@(& $module {Get-BastosOnlineProvisionedPackages})
    Check ($packages.Count -eq 1 -and $packages[0].DisplayName -eq 'Microsoft.Windows.DevHome') 'Windows API fallback retains exact provisioned identity'
    & $module {param($p) Remove-BastosOnlineProvisionedPackage $p} $packages[0]
    Check ((& $module {$script:RemovedFamily}) -eq 'DevHome_family') 'Windows API removal uses selected package family'
    & $module {function script:Get-BastosProvisionedPackagesViaWindowsApi {throw 'API unavailable'}}
    $failed=$false;try{& $module {Get-BastosOnlineProvisionedPackages}}catch{$failed=$true}
    Check $failed 'Two failed inventory methods cannot report empty success'
    & $module {function script:Invoke-BastosDeprovisionByFamily {param($Family) throw 'Removal failed'}}
    $failed=$false;try{& $module {param($p) Remove-BastosOnlineProvisionedPackage $p} $packages[0]}catch{$failed=$true}
    Check $failed 'Deprovision failure propagated'
} finally {
    if($fixture -notmatch '^Software\\BASTOS\\Tests\\FirstLogon-[0-9a-f]{32}$'){throw 'Invalid fixture cleanup path'}
    $base.DeleteSubKeyTree($fixture,$false);$base.Dispose()
}
Write-Output "PASS : $count real registry and COM checks; only disposable HKCU fixture modified."
