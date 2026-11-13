Set-StrictMode -Version Latest

function Test-BastosExactRufusExperience($Profile) {
    if(-not $Profile.Options.PSObject.Properties['RufusExperienceVersion']){return $false}
    $version=[string]$Profile.Options.RufusExperienceVersion
    if($version -and $version -ne '4.15'){throw 'Version experience Rufus non prise en charge.'}
    if($version -eq '4.15'){
        foreach($option in @('RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){
            if($Profile.Options.$option){throw 'Options supplementaires incompatibles avec le mode Rufus strict.'}
        }
        return $true
    }
    return $false
}
function Test-BastosRufusQolRequested($Profile) {
    if(-not $Profile.Options.PSObject.Properties['RufusQolVersion']){return $false}
    $version=[string]$Profile.Options.RufusQolVersion
    if($version -and $version -ne '4.15'){throw 'Version QoL Rufus non prise en charge.'}
    return $Profile.Options.DisableConsumerContent -and $version -eq '4.15'
}
function Test-BastosCleanInstallation($Profile) {
    if(-not $Profile.Options.PSObject.Properties['CleanBastosVersion']){return $false}
    $version=[string]$Profile.Options.CleanBastosVersion
    if($version -and $version -ne '1'){throw 'Version profil propre BASTOS inconnue.'}
    if($version -eq '1' -and (Test-BastosExactRufusExperience $Profile)){throw 'Profils BASTOS propre et Rufus incompatibles.'}
    return $version -eq '1'
}
function Get-BastosMinimalAppNames {
    # Exact package identities only. Never remove frameworks, shell, Store,
    # App Installer, Security UI, codecs, Gaming Services or Xbox identity APIs.
    @('Microsoft.BingNews','Microsoft.News','Microsoft.BingWeather','Microsoft.BingFinance','Microsoft.BingSports',
      'Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.549981C3F5F10',
      'Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote','Microsoft.OutlookForWindows','MicrosoftTeams','MSTeams',
      'Microsoft.windowscommunicationsapps','Microsoft.People','Microsoft.SkypeApp',
      'Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.WindowsFeedbackHub','Microsoft.MicrosoftSolitaireCollection',
      'Clipchamp.Clipchamp','Microsoft.PowerAutomateDesktop','Microsoft.Todos','Microsoft.WindowsMaps',
      'Microsoft.MixedReality.Portal','Microsoft.Windows.DevHome','MicrosoftCorporationII.MicrosoftFamily',
      'Microsoft.Microsoft3DViewer','Microsoft.Print3D','Microsoft.ZuneMusic','Microsoft.ZuneVideo',
      'Microsoft.Windows.Photos','Microsoft.MSPaint','Microsoft.Paint','Microsoft.WindowsCamera','Microsoft.WindowsSoundRecorder',
      'Microsoft.GamingApp','Microsoft.XboxApp','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay',
      'SpotifyAB.SpotifyMusic','king.com.CandyCrushSaga','king.com.CandyCrushSodaSaga','Netflix','Disney.37853FC22B2CE',
      'Facebook.Facebook','Facebook.Instagram','BytedancePte.Ltd.TikTok','AmazonVideo.PrimeVideo')
}
function Get-BastosCleanPinsJson {
    [ordered]@{applyOnce=$true;pinnedList=@(
        @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'},
        @{desktopAppId='Microsoft.Windows.Explorer'},
        @{desktopAppLink='%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\BASTOS.lnk'}
    )}|ConvertTo-Json -Depth 5 -Compress
}
function Get-BastosCleanTasks {
    @(
        @{Path='\Microsoft\Windows\Customer Experience Improvement Program\';Name='Consolidator'},
        @{Path='\Microsoft\Windows\Customer Experience Improvement Program\';Name='KernelCeipTask'},
        @{Path='\Microsoft\Windows\Customer Experience Improvement Program\';Name='UsbCeip'},
        @{Path='\Microsoft\Windows\Feedback\Siuf\';Name='DmClient'},
        @{Path='\Microsoft\Windows\Feedback\Siuf\';Name='DmClientOnScenarioDownload'}
    )
}
function Get-BastosCleanRegistrySettings {
    $entries=@(
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo','DisabledByGroupPolicy',1),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','DoNotShowFeedbackNotifications',1),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','LimitDiagnosticLogCollection',1),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','LimitDumpCollection',1),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','EnableActivityFeed',0),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','PublishUserActivities',0),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','UploadUserActivities',0),
        @('DisableTelemetry','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAIDataAnalysis',1),
        @('DisableConsumerContent','HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent','DisableWindowsSpotlightFeatures',1),
        @('DisableConsumerContent','HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer','DisableSearchBoxSuggestions',1),
        @('DisableConsumerContent','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer','HideRecommendedSection',1),
        @('DisableConsumerContent','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer','HideRecentlyAddedApps',1),
        @('DisableConsumerContent','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer','HideRecommendedPersonalizedSites',1),
        @('DisableConsumerContent','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer','ConfigureStartPins',1)
    )
    foreach($e in $entries){[pscustomobject]@{Option=$e[0];Path=$e[1];Name=$e[2];Value=$e[3];Type='DWord'}}
    [pscustomobject]@{Option='DisableConsumerContent';Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer';Name='ConfigureStartPinsJSON';Value=(Join-Path $env:ProgramData 'BASTOS-ISO\StartPins.json');Type='ExpandString'}
}
function Get-BastosStartPolicyTypeSource {
@'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
namespace BastosClean {
 [ComImport, Guid("EA502723-A23D-11D1-A7D3-0000F87571E3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface ILocalGpo {
  [PreserveSig] int New([MarshalAs(UnmanagedType.LPWStr)]string domain,[MarshalAs(UnmanagedType.LPWStr)]string display,uint flags);
  [PreserveSig] int OpenDSGPO([MarshalAs(UnmanagedType.LPWStr)]string path,uint flags);
  [PreserveSig] int OpenLocalMachineGPO(uint flags);
  [PreserveSig] int OpenRemoteMachineGPO([MarshalAs(UnmanagedType.LPWStr)]string machine,uint flags);
  [PreserveSig] int Save([MarshalAs(UnmanagedType.Bool)]bool machine,[MarshalAs(UnmanagedType.Bool)]bool add,ref Guid extension,ref Guid application);
  [PreserveSig] int Delete();
  [PreserveSig] int GetName([MarshalAs(UnmanagedType.LPWStr)]StringBuilder name,int max);
  [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)]StringBuilder name,int max);
  [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)]string name);
  [PreserveSig] int GetPath([MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int max);
  [PreserveSig] int GetDSPath(uint section,[MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int max);
  [PreserveSig] int GetFileSysPath(uint section,[MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int max);
  [PreserveSig] int GetRegistryKey(uint section,out IntPtr key);
 }
 public static class StartPolicy {
  static object Open(bool readOnly,out ILocalGpo gpo) {
   object instance=Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("EA502722-A23D-11D1-A7D3-0000F87571E3"),true));
   gpo=(ILocalGpo)instance;
   try { Marshal.ThrowExceptionForHR(gpo.OpenLocalMachineGPO(readOnly?3u:1u)); return instance; }
   catch { Marshal.FinalReleaseComObject(instance); throw; }
  }
  public static void Apply(string path) {
   ILocalGpo gpo; object instance=Open(false,out gpo);
   try {
    IntPtr handle; Marshal.ThrowExceptionForHR(gpo.GetRegistryKey(2,out handle));
    using(var safe=new SafeRegistryHandle(handle,true))
    using(var root=RegistryKey.FromHandle(safe))
    using(var key=root.CreateSubKey(@"Software\Policies\Microsoft\Windows\Explorer")) {
     key.SetValue("ConfigureStartPins",1,RegistryValueKind.DWord);
     key.SetValue("ConfigureStartPinsJSON",path,RegistryValueKind.ExpandString);
    }
    Guid extension=new Guid("35378EAC-683F-11D2-A89A-00C04FBBCFA2");
    Guid application=new Guid("960EC3BC-F098-4438-86F0-17A9A9AD42F2");
    Marshal.ThrowExceptionForHR(gpo.Save(true,true,ref extension,ref application));
   } finally { Marshal.FinalReleaseComObject(instance); }
  }
  public static bool IsConfigured(string path) {
   ILocalGpo gpo; object instance=Open(true,out gpo);
   try {
    IntPtr handle; Marshal.ThrowExceptionForHR(gpo.GetRegistryKey(2,out handle));
    using(var safe=new SafeRegistryHandle(handle,true))
    using(var root=RegistryKey.FromHandle(safe))
    using(var key=root.OpenSubKey(@"Software\Policies\Microsoft\Windows\Explorer")) {
     return key!=null && Convert.ToInt32(key.GetValue("ConfigureStartPins",0))==1 &&
      string.Equals(Convert.ToString(key.GetValue("ConfigureStartPinsJSON","")),path,StringComparison.OrdinalIgnoreCase);
    }
   } finally { Marshal.FinalReleaseComObject(instance); }
  }
 }
}
'@
}
function Initialize-BastosStartPolicyType {
    if(-not ('BastosClean.StartPolicy' -as [type])){Add-Type -TypeDefinition (Get-BastosStartPolicyTypeSource) -ErrorAction Stop}
}
function Set-BastosCleanStartPolicy([string]$File) {
    Initialize-BastosStartPolicyType
    [BastosClean.StartPolicy]::Apply($File)
    & (Join-Path $env:SystemRoot 'System32\gpupdate.exe') /target:computer /force /wait:30 | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Actualisation de la strategie Demarrer non confirmee.'}
}
function Test-BastosCleanStartPolicy([string]$File) {
    Initialize-BastosStartPolicyType
    return [BastosClean.StartPolicy]::IsConfigured($File)
}
function Get-BastosCleanServiceNames { @('DiagTrack','RetailDemo','MapsBroker') }
function Invoke-BastosCleanServices {
    $file=Join-Path $env:ProgramData 'BASTOS-ISO\Services-Before.json'
    $states=@(foreach($name in Get-BastosCleanServiceNames){
        $service=Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if($service){
            $key=Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -ErrorAction Stop
            [pscustomobject]@{Name=$name;StartMode=[string]$service.StartMode;WasRunning=($service.State -eq 'Running');DelayedAutoStart=([int]$key.Start -eq 2 -and $key.PSObject.Properties['DelayedAutoStart'] -and [int]$key.DelayedAutoStart -eq 1)}
        }
    })
    if(-not(Test-Path -LiteralPath $file)){
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force|Out-Null
        [IO.File]::WriteAllText($file,([pscustomobject]@{Schema=1;Services=$states}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    }
    foreach($state in $states){
        # No -Force: never stop dependent services implicitly.
        Set-Service -Name $state.Name -StartupType Disabled -ErrorAction Stop
        Stop-Service -Name $state.Name -ErrorAction Stop
    }
    $mismatches=@(Get-BastosCleanServiceMismatches)
    if($mismatches.Count){throw ('Services non confirmes : '+($mismatches -join ', '))}
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $file) 'Services-Applied.json'),([pscustomobject]@{Schema=1;CheckedUtc=[DateTime]::UtcNow.ToString('o');Disabled=@($states|ForEach-Object Name);Absent=@(Get-BastosCleanServiceNames|Where-Object {$_ -notin @($states|ForEach-Object Name)})}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
function Get-BastosCleanServiceMismatches {
    foreach($name in Get-BastosCleanServiceNames){
        $service=Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if($service -and ($service.StartMode -ne 'Disabled' -or $service.State -ne 'Stopped')){$name}
    }
}
function Restore-BastosCleanServices {
    $file=Join-Path $env:ProgramData 'BASTOS-ISO\Services-Before.json'
    $backup=Get-Content -LiteralPath $file -Raw -ErrorAction Stop|ConvertFrom-Json
    if($backup.Schema -ne 1){throw 'Sauvegarde de services inconnue.'}
    foreach($entry in $backup.Services){
        if($entry.Name -notin @(Get-BastosCleanServiceNames) -or $entry.StartMode -notin @('Auto','Manual','Disabled')){throw 'Sauvegarde de services invalide.'}
    }
    foreach($entry in $backup.Services){
        if(-not(Get-Service -Name $entry.Name -ErrorAction SilentlyContinue)){continue}
        $mode=switch($entry.StartMode){Auto{'Automatic'} Manual{'Manual'} Disabled{'Disabled'}}
        Set-Service -Name $entry.Name -StartupType $mode -ErrorAction Stop
        Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($entry.Name)" -Name DelayedAutoStart -Value ([int][bool]$entry.DelayedAutoStart) -ErrorAction Stop
        if($entry.WasRunning -and $mode -ne 'Disabled'){Start-Service -Name $entry.Name -ErrorAction Stop}
    }
}
function Invoke-BastosCleanUserConfiguration {
    $file=Join-Path $env:ProgramData 'BASTOS-ISO\StartPins.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force|Out-Null
    [IO.File]::WriteAllText($file,(Get-BastosCleanPinsJson),[Text.UTF8Encoding]::new($false))
    Set-BastosCleanStartPolicy -File $file
    Invoke-BastosCleanServices
    $tasks=@(Get-ScheduledTask -ErrorAction Stop)
    foreach($target in Get-BastosCleanTasks){
        foreach($task in @($tasks|Where-Object {$_.TaskPath -eq $target.Path -and $_.TaskName -eq $target.Name})){
            Disable-ScheduledTask -InputObject $task -ErrorAction Stop|Out-Null
        }
    }
}
function Get-BastosCleanEvidence {
    $result=@{CleanPrivacyError='';CleanPrivacyMismatches=@();CleanLayoutError=''}
    try{
        $result.CleanPrivacyMismatches+=@(Get-BastosCleanServiceMismatches)
        $tasks=@(Get-ScheduledTask -ErrorAction Stop)
        foreach($target in Get-BastosCleanTasks){foreach($task in @($tasks|Where-Object {$_.TaskPath -eq $target.Path -and $_.TaskName -eq $target.Name})){
            if([string]$task.State -ne 'Disabled'){$result.CleanPrivacyMismatches+=($target.Path+$target.Name)}
        }}
    }catch{$result.CleanPrivacyError=$_.Exception.Message}
    try{
        $file=Join-Path $env:ProgramData 'BASTOS-ISO\StartPins.json'
        if([IO.File]::ReadAllText($file) -cne (Get-BastosCleanPinsJson)){throw 'Configuration des trois epingles divergente.'}
        if(-not(Test-BastosCleanStartPolicy -File $file)){throw 'Strategie locale Demarrer non enregistree.'}
        if(-not(Test-Path -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\BASTOS.lnk') -PathType Leaf)){throw 'Raccourci Demarrer BASTOS absent.'}
    }catch{$result.CleanLayoutError=$_.Exception.Message}
    return $result
}
function Invoke-BastosOfflineMinimalApps {
    param([Parameter(Mandatory)][string]$ImagePath)
    $names=@(Get-BastosMinimalAppNames)
    $admx=Join-Path $ImagePath 'Windows\PolicyDefinitions\StartMenu.admx'
    if(-not(Test-Path -LiteralPath $admx) -or -not [IO.File]::ReadAllText($admx).Contains('ConfigureStartPinsJSON')){throw 'Image Windows trop ancienne pour configurer les trois epingles. Utilisez une ISO Windows 11 recente.'}
    $removed=@(Get-AppxProvisionedPackage -Path $ImagePath -ErrorAction Stop|Where-Object {$_.DisplayName -in $names})
    foreach($package in $removed){Remove-AppxProvisionedPackage -Path $ImagePath -PackageName $package.PackageName -ErrorAction Stop|Out-Null}
    $remaining=@(Get-AppxProvisionedPackage -Path $ImagePath -ErrorAction Stop|Where-Object {$_.DisplayName -in $names})
    if($remaining.Count){throw 'Applications ciblees encore provisionnees dans l image.'}
    [pscustomobject]@{Schema=1;Profile='minimal-2';Removed=@($removed|ForEach-Object DisplayName);RemainingTargets=@();CheckedUtc=[DateTime]::UtcNow.ToString('o')}
}
function Get-BastosTelemetryLevel([string]$EditionId) { if($EditionId -match 'Enterprise|Education|IoT'){return 0};return 1 }

function Get-BastosCleanupDefinitions {
    @(
        @{Id='privacy';Option='DisableTelemetry';Name='Collecte facultative et confidentialite'}
        @{Id='suggestions';Option='DisableConsumerContent';Name='Suggestions et ameliorations QoL demandees'}
        @{Id='onedrive';Option='RemoveOneDrive';Name='Suppression de OneDrive'}
        @{Id='teams';Option='RemoveTeams';Name='Suppression de Teams'}
        @{Id='outlook';Option='RemoveOutlook';Name='Suppression du nouvel Outlook'}
        @{Id='copilot';Option='DisableCopilot';Name='Suppression de Copilot'}
        @{Id='widgets';Option='DisableWidgets';Name='Widgets et meteo de la barre des taches'}
    )
}

function Get-BastosRequestedRegistrySettings($Profile) {
    $settings=[Collections.Generic.List[object]]::new()
    function Add([string]$Option,[string]$Path,[string]$Name,[int]$Value){$settings.Add(@{Option=$Option;Path=$Path;Name=$Name;Value=$Value})}
    if($Profile.Options.DisableTelemetry -and -not (Test-BastosExactRufusExperience $Profile)){
        $edition=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).EditionID
        $level=Get-BastosTelemetryLevel $edition
        Add 'DisableTelemetry' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' $level
        Add 'DisableTelemetry' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Add 'DisableTelemetry' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Add 'DisableTelemetry' 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    }
    if($Profile.Options.DisableConsumerContent -and -not (Test-BastosExactRufusExperience $Profile)){
        # User settings apply on Pro too; do not rely solely on the Enterprise-only policy.
        foreach($name in @('ContentDeliveryAllowed','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')){
            Add 'DisableConsumerContent' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $name 0
        }
        Add 'DisableConsumerContent' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    }
    if($Profile.Options.RemoveOneDrive){Add 'RemoveOneDrive' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1}
    if($Profile.Options.DisableCopilot){
        Add 'DisableCopilot' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Add 'DisableCopilot' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    }
    if($Profile.Options.DisableWidgets){
        # Always configure the established policy. An ADMX entry for a preview
        # policy does not prove that the running shell implements it.
        Add 'DisableWidgets' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        $admx=Join-Path $env:SystemRoot 'PolicyDefinitions\NewsAndInterests.admx'
        $newPolicy=(Test-Path -LiteralPath $admx) -and ([IO.File]::ReadAllText($admx).Contains('name="DisableWidgetsBoard"'))
        $policy=if($newPolicy){'DisableWidgetsBoard'}else{'AllowNewsAndInterests'}
        # Read the enabled policy value from this Windows image. Some preview
        # ADMX versions use 0 for the enabled DisableWidgetsBoard policy.
        $value=0
        if($newPolicy){
            [xml]$definition=[IO.File]::ReadAllText($admx)
            $node=$definition.SelectSingleNode('//*[local-name()="policy" and @name="DisableWidgetsBoard"]/*[local-name()="enabledValue"]/*[local-name()="decimal"]')
            if($null -eq $node -or [string]$node.value -notin @('0','1')){throw 'Valeur active de la strategie Widgets inconnue.'}
            $value=[int]$node.value
        }
        if($newPolicy){Add 'DisableWidgets' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' $policy $value}
        # Leave the independently protected per-user TaskbarDa preference alone.
    }
    if(Test-BastosRufusQolRequested $Profile){foreach($setting in Get-BastosRufusQolRegistrySettings){
        # The widget policy above already covers AllowNewsAndInterests. Clean
        # BASTOS omits Windows 10 feeds preferences; Chat uses unattend.
        if((Test-BastosCleanInstallation $Profile) -and $setting.Name -in @('AllowNewsAndInterests','EnableFeeds','ConfigureChatAutoInstall')){continue}
        $settings.Add($setting)
    }}
    if(Test-BastosCleanInstallation $Profile){foreach($setting in Get-BastosCleanRegistrySettings){$settings.Add($setting)}}
    return $settings.ToArray()
}

function Get-BastosOneDriveEntries {
    $paths=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach($path in $paths){
        if(Test-Path -LiteralPath $path){
            foreach($key in Get-ChildItem -LiteralPath $path -ErrorAction Stop){
                $entry=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -match '^Microsoft OneDrive(?:\s.*)?$'){$entry}
            }
        }
    }
}

function Get-BastosProvisionedPackagesViaWindowsApi {
            [void][Windows.Management.Deployment.PackageManager,Windows.Management.Deployment,ContentType=WindowsRuntime]
            $manager=New-Object Windows.Management.Deployment.PackageManager
            $packages=@($manager.FindProvisionedPackages())
            $result=[Collections.Generic.List[object]]::new()
            foreach($package in $packages){
                $id=$package.Id
                if(-not $id.Name -or -not $id.FullName -or -not $id.FamilyName){throw 'Identite provisionnee Windows incomplete.'}
                $result.Add([pscustomobject]@{DisplayName=[string]$id.Name;PackageName=[string]$id.FullName;PackageFamilyName=[string]$id.FamilyName;Backend='WindowsApi'})
            }
            return $result.ToArray()
}
function Get-BastosOnlineProvisionedPackages {
    try {return @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)}
    catch {
        $dismError=$_.Exception.Message
        try {return @(Get-BastosProvisionedPackagesViaWindowsApi)}
        catch {throw ('Inventaire provisionne impossible (DISM : '+$dismError+' ; API Windows : '+$_.Exception.Message+').')}
    }
}
function Invoke-BastosDeprovisionByFamily([string]$Family) {
    if([string]::IsNullOrWhiteSpace($Family)){throw 'Famille Appx absente.'}
    [void][Windows.Management.Deployment.PackageManager,Windows.Management.Deployment,ContentType=WindowsRuntime]
    [void][Windows.Management.Deployment.DeploymentResult,Windows.Management.Deployment,ContentType=WindowsRuntime]
    [void][Windows.Management.Deployment.DeploymentProgress,Windows.Management.Deployment,ContentType=WindowsRuntime]
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $manager=New-Object Windows.Management.Deployment.PackageManager
    $operation=$manager.DeprovisionPackageForAllUsersAsync($Family)
    $method=@([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 2 -and $_.GetParameters().Count -eq 1})
    if($method.Count -ne 1){throw 'Adaptateur asynchrone Windows ambigu.'}
    $task=$method[0].MakeGenericMethod([Windows.Management.Deployment.DeploymentResult],[Windows.Management.Deployment.DeploymentProgress]).Invoke($null,@($operation))
    if(-not $task.Wait(120000)){throw 'Deprovisionnement encore en cours ; fin non confirmee.'}
    $result=$task.GetAwaiter().GetResult()
    if($null -ne $result.ExtendedErrorCode -and $result.ExtendedErrorCode.HResult -lt 0){throw $result.ExtendedErrorCode}
}
function Remove-BastosOnlineProvisionedPackage($Package) {
    if($Package.PSObject.Properties['Backend'] -and $Package.Backend -eq 'WindowsApi'){
        Invoke-BastosDeprovisionByFamily ([string]$Package.PackageFamilyName)
    } else {
        Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -ErrorAction Stop|Out-Null
    }
}

function Get-BastosInstallationEvidence($Profile) {
    $evidence=@{QolOneDriveSetupFiles=@();QolFileError='';Registry=@{};RegistryErrors=@{};Packages=@();Provisioned=@();PackageError='';OneDriveEntries=@();OneDriveFiles=@();OneDriveStartup=@();OneDriveError='';PreferredLanguages=@();LanguageError=''}
    if(Test-BastosCleanInstallation $Profile){$clean=Get-BastosCleanEvidence;foreach($key in $clean.Keys){$evidence[$key]=$clean[$key]}}
    if(Test-BastosExactRufusExperience $Profile){
        $evidence.OobeProtectYourPC='';$evidence.OobeError=''
        try{
            [xml]$oobe=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Rufus-Oobe.xml'))
            $evidence.OobeProtectYourPC=$oobe.SelectSingleNode('//*[local-name()="ProtectYourPC"]').InnerText
        }catch{$evidence.OobeError=$_.Exception.Message}
    }
    try{$evidence.PreferredLanguages=@(foreach($language in (Get-WinUserLanguageList -ErrorAction Stop)){[string]$language.LanguageTag})}catch{$evidence.LanguageError=$_.Exception.Message}
    foreach($setting in Get-BastosRequestedRegistrySettings $Profile){
        $id=$setting.Path+'|'+$setting.Name
        try{
            $key=Get-Item -LiteralPath $setting.Path -ErrorAction Stop
            $evidence.Registry[$id]=$key.GetValue($setting.Name,$null)
        }catch{if($_.CategoryInfo.Category -eq 'ObjectNotFound'){$evidence.Registry[$id]=$null}else{$evidence.RegistryErrors[$id]=$_.Exception.Message}}
    }
    if((Test-BastosRufusQolRequested $Profile) -or $Profile.Options.RemoveTeams -or $Profile.Options.RemoveOutlook -or $Profile.Options.DisableCopilot -or $Profile.Options.RemoveOneDrive){
        try{
            $evidence.Packages=@(Get-AppxPackage -AllUsers -ErrorAction Stop | ForEach-Object Name)
            $evidence.Provisioned=@(Get-BastosOnlineProvisionedPackages | ForEach-Object DisplayName)
        }catch{$evidence.PackageError=$_.Exception.Message}
    }
    if($Profile.Options.RemoveOneDrive){
        try{
            $evidence.OneDriveEntries=@(Get-BastosOneDriveEntries)
            foreach($path in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')){
                if(Test-Path -LiteralPath $path){$key=Get-Item -LiteralPath $path -ErrorAction Stop;foreach($name in @('OneDrive','OneDriveSetup')){if($key.GetValueNames() -contains $name){$evidence.OneDriveStartup+=$path+'|'+$name}}}
            }
            foreach($root in @((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive'),(Join-Path (${env:ProgramFiles(x86)}) 'Microsoft OneDrive'))|Select-Object -Unique){
                $file=Join-Path $root 'OneDrive.exe'
                if(Test-Path -LiteralPath $file){$evidence.OneDriveFiles+=$file}
            }
        }catch{$evidence.OneDriveError=$_.Exception.Message}
    }
    if(Test-BastosRufusQolRequested $Profile){
        try{foreach($directory in @('System32','SysWOW64')){
            $file=Join-Path $env:SystemRoot ($directory+'\OneDriveSetup.exe')
            if(Test-Path -LiteralPath $file -ErrorAction Stop){$evidence.QolOneDriveSetupFiles+=$file}
        }}catch{$evidence.QolFileError=$_.Exception.Message}
    }
    return $evidence
}

function Test-BastosInstallationEvidence($Profile,$Evidence,[object[]]$RegistrySettings) {
    $checks=[Collections.Generic.List[object]]::new()
    $languageOk=$Evidence.PreferredLanguages.Count -eq 1 -and $Evidence.PreferredLanguages[0] -ieq $Profile.UILanguage
    $checks.Add([pscustomobject]@{Id='preferredlanguage';Name='Langue prioritaire des applications';Expected=[string]$Profile.UILanguage;Actual=($Evidence.PreferredLanguages -join ',');Status=$(if($Evidence.LanguageError){'Unavailable'}elseif($languageOk){'Passed'}else{'Mismatch'});Detail='La langue des applications est independante du clavier. '+$Evidence.LanguageError})
    foreach($definition in Get-BastosCleanupDefinitions){
        $selected=$Profile.Options.($definition.Option)
        if($selected -isnot [bool]){throw ('Option du profil absente ou invalide : '+$definition.Option)}
        $status='NotRequested';$expected='NotRequested';$actual='NotRequested';$details=[Collections.Generic.List[string]]::new()
        if($selected){
            $expected='Applied';$actual='Applied';$status='Passed'
            foreach($setting in @($RegistrySettings|Where-Object Option -eq $definition.Option)){
                $id=$setting.Path+'|'+$setting.Name
                if($Evidence.RegistryErrors.ContainsKey($id)){$status='Unavailable';$details.Add($Evidence.RegistryErrors[$id])}
                elseif(-not $Evidence.Registry.ContainsKey($id) -or ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Evidence.Registry[$id] -join ',')))) -ne ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($setting.Value -join ','))))){if($status -ne 'Unavailable'){$status='Mismatch'};$details.Add('Valeur non conforme : '+$setting.Name)}
            }
            $patterns=switch($definition.Option){'DisableConsumerContent'{if(Test-BastosRufusQolRequested $Profile){@('*Outlook*','*Teams*')};if(Test-BastosCleanInstallation $Profile){Get-BastosMinimalAppNames}}'RemoveTeams'{@('MSTeams','MicrosoftTeams')}'RemoveOutlook'{@('Microsoft.OutlookForWindows')}'DisableCopilot'{@('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider')}'RemoveOneDrive'{@('Microsoft.OneDriveSync')};default{@()}}
            if(@($patterns).Count){
                if($Evidence.PackageError){$status='Unavailable';$details.Add('Inventaire tous comptes / futurs comptes indisponible : '+$Evidence.PackageError)}
                elseif(@(@($Evidence.Packages)+@($Evidence.Provisioned)|Where-Object {$candidate=$_;@($patterns|Where-Object {$candidate -like $_}).Count -gt 0}).Count){if($status -ne 'Unavailable'){$status='Mismatch'};$details.Add('Application encore installee ou provisionnee.')}
            }
            if($definition.Option -eq 'RemoveOneDrive'){
                if($Evidence.OneDriveError){$status='Unavailable';$details.Add($Evidence.OneDriveError)}
                elseif($Evidence.OneDriveEntries.Count -gt 0 -or $Evidence.OneDriveFiles.Count -gt 0 -or $Evidence.OneDriveStartup.Count -gt 0){if($status -ne 'Unavailable'){$status='Mismatch'};$details.Add('OneDrive reste enregistre, son executable reste present ou son lancement automatique reste configure.')}
            }
            if($status -ne 'Passed'){$actual=if($status -eq 'Unavailable'){'Unknown'}else{'NotApplied'}}
            if($definition.Option -eq 'DisableTelemetry'){
                if(Test-BastosExactRufusExperience $Profile){
                    $expected='Configured';$actual='Configured'
                    if(-not $Evidence.ContainsKey('OobeProtectYourPC') -or -not $Evidence.ContainsKey('OobeError') -or $Evidence.OobeError){$status='Unavailable';$actual='Unknown'}
                    elseif($Evidence.OobeProtectYourPC -ne '3'){$status='Mismatch';$actual='NotApplied'}
                    $details.Add('Configuration OOBE archivee : ProtectYourPC=3, comme Rufus. Ce controle ne mesure pas la collecte effective de Windows et ne promet pas sa suppression.')
                }else{$details.Add('Donnees facultatives limitees ; Windows Pro conserve les donnees de diagnostic requises.')}
            }
            if($definition.Option -eq 'DisableCopilot'){$details.Add('Application Windows retiree ; les services web et les futures reinstallations par Windows ne sont pas bloques.')}
            if($definition.Option -eq 'DisableWidgets'){
                $expected='Configured'
                if($status -eq 'Passed'){$actual='Configured'}
                $details.Add('Strategies Widgets configurees et relues. Ce controle de registre ne prouve pas la disparition visuelle du bouton meteo ; verifier apres reconnexion.')
            }
            if($definition.Option -eq 'DisableConsumerContent' -and (Test-BastosRufusQolRequested $Profile)){
                if(-not $Evidence.ContainsKey('QolOneDriveSetupFiles') -or -not $Evidence.ContainsKey('QolFileError') -or $Evidence.QolFileError){$status='Unavailable';$actual='Unknown';$details.Add('Verification des installateurs OneDrive indisponible.')}
                elseif($Evidence.QolOneDriveSetupFiles.Count){$status='Mismatch';$actual='NotApplied';$details.Add('Installateur OneDrive encore present.')}
                $details.Add('Socle QoL Rufus : valeurs registre, installateurs OneDrive et paquets Outlook/Teams controles. Le profil propre BASTOS, si choisi, ajoute ses propres suppressions dont News. Effet des strategies selon edition et version Windows.')
            }
            if((Test-BastosCleanInstallation $Profile) -and $definition.Option -eq 'DisableTelemetry'){
                if(-not $Evidence.ContainsKey('CleanPrivacyError') -or -not $Evidence.ContainsKey('CleanPrivacyMismatches') -or $Evidence.CleanPrivacyError){$status='Unavailable';$actual='Unknown';$details.Add('Etat diagnostic et taches de collecte non confirme.')}
                elseif($Evidence.CleanPrivacyMismatches.Count){$status='Mismatch';$actual='NotApplied';$details.Add('Collecte encore active : '+($Evidence.CleanPrivacyMismatches -join ','))}
                $details.Add('Strategies, services DiagTrack/RetailDemo/MapsBroker et taches ciblees controles ; aucune mesure exhaustive du trafic reseau. Les diagnostics requis dependent de l edition Windows.')
            }
            if((Test-BastosCleanInstallation $Profile) -and $definition.Option -eq 'DisableConsumerContent'){
                $expected='Configured'
                if($status -eq 'Passed'){$actual='Configured'}
                if(-not $Evidence.ContainsKey('CleanLayoutError') -or $Evidence.CleanLayoutError){$status='Unavailable';$actual='Unknown';$details.Add('Configuration Demarrer non confirmee.')}
                $details.Add('Profil propre BASTOS : applications ciblees absentes, fichier des trois epingles et strategies controles. Le rendu effectif du menu apres reconnexion reste a verifier visuellement.')
            }
        }
        $checks.Add([pscustomobject]@{Id=$definition.Id;Name=$definition.Name;Expected=$expected;Actual=$actual;Status=$status;Detail=($details -join ' ')})
    }
    return $checks.ToArray()
}

function Get-BastosInstallationOptionChecks($Profile) {
    $settings=@(Get-BastosRequestedRegistrySettings $Profile)
    Test-BastosInstallationEvidence $Profile (Get-BastosInstallationEvidence $Profile) $settings
}

function Invoke-BastosOneDriveUninstall {
    $candidates=[Collections.Generic.List[object]]::new()
    $roots=@((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive'),(Join-Path (${env:ProgramFiles(x86)}) 'Microsoft OneDrive'))|Select-Object -Unique
    foreach($entry in Get-BastosOneDriveEntries){
        $command=if($entry.PSObject.Properties['QuietUninstallString']){[string]$entry.QuietUninstallString}else{[string]$entry.UninstallString}
        if($command -match '^"([^"]+OneDriveSetup\.exe)"(?:\s|$)'){
            $path=[IO.Path]::GetFullPath($Matches[1])
            if(@($roots|Where-Object {$path.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){$candidates.Add(@{Path=$path;AllUsers=($command -match '/allusers')})}
        }
    }
    foreach($root in $roots){
        if(Test-Path -LiteralPath $root){
            foreach($file in @(Get-ChildItem -Path (Join-Path $root 'OneDriveSetup.exe'),(Join-Path $root '*\OneDriveSetup.exe') -File -ErrorAction SilentlyContinue)){$candidates.Add(@{Path=$file.FullName;AllUsers=(-not $root.StartsWith($env:LOCALAPPDATA,[StringComparison]::OrdinalIgnoreCase))})}
        }
    }
    foreach($name in @('System32','SysWOW64')){$candidates.Add(@{Path=(Join-Path $env:SystemRoot ($name+'\OneDriveSetup.exe'));AllUsers=$false})}
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
    foreach($candidate in $candidates|Sort-Object -Property Path -Unique){
        if(-not(Test-Path -LiteralPath $candidate.Path -PathType Leaf)){continue}
        $signature=Get-AuthenticodeSignature -FilePath $candidate.Path
        if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw 'Desinstalleur OneDrive non signe par Microsoft.'}
        $arguments=if($candidate.AllUsers){'/uninstall /allusers'}else{'/uninstall'}
        $process=Start-Process -FilePath $candidate.Path -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if(-not $process.WaitForExit(60000)){throw 'La desinstallation OneDrive continue ; aucune fin ne peut etre confirmee.'}
        if($process.ExitCode -notin @(0,3010)){throw ('Desinstalleur OneDrive : code '+$process.ExitCode)}
    }
    foreach($path in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')){
        if(Test-Path -LiteralPath $path){$key=Get-Item -LiteralPath $path -ErrorAction Stop;foreach($name in @('OneDrive','OneDriveSetup')){if($key.GetValueNames() -contains $name){Remove-ItemProperty -LiteralPath $path -Name $name -Force -ErrorAction Stop}}}
    }
    # No user documents or OneDrive data directories are deleted.
}

function Assert-BastosFirstLogonContext($Profile) {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Finalisation administrateur requise.'}
    if($env:USERNAME -ine $Profile.UserName){throw 'Le compte actif differe du compte de reinstallation.'}
}

function Set-BastosInstallationRegistrySetting($Setting) {
    # Open existing keys without deleting their values or children.
    if([string]$Setting.Path -notmatch '^(HKLM|HKCU):\\(.+)$'){throw 'Racine registre non prise en charge.'}
    $hive=if($Matches[1] -eq 'HKLM'){[Microsoft.Win32.RegistryHive]::LocalMachine}else{[Microsoft.Win32.RegistryHive]::CurrentUser}
    $subPath=$Matches[2]
    $type=if($Setting -is [Collections.IDictionary]){if($Setting.Contains('Type')){[string]$Setting.Type}else{'DWord'}}elseif($Setting.PSObject.Properties['Type']){[string]$Setting.Type}else{'DWord'}
    if($type -notin @('DWord','String','ExpandString','Binary')){throw ('Type registre non pris en charge : '+$type)}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$null
    try {
        $key=$base.CreateSubKey($subPath,$true)
        if($null -eq $key){throw 'Ouverture de la cle impossible.'}
        $kind=[Microsoft.Win32.RegistryValueKind]$type
        $value=$Setting.Value
        if($type -eq 'DWord'){$value=[int]$Setting.Value}
        elseif($type -eq 'Binary'){$value=[byte[]]$Setting.Value}
        $key.SetValue([string]$Setting.Name,$value,$kind)
        $actual=$key.GetValue([string]$Setting.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($key.GetValueKind([string]$Setting.Name) -ne $kind -or ($actual -join ',') -cne ($value -join ',')){throw 'Relecture de la valeur non conforme.'}
    } finally {if($null -ne $key){$key.Dispose()};$base.Dispose()}
}

function Invoke-BastosInstallationOptions {
    param([Parameter(Mandatory)][string]$ProfilePath,[Parameter(Mandatory)][string]$ResultPath)
    $ErrorActionPreference='Stop'
    $profile=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8|ConvertFrom-Json
    if($profile.Schema -ne 2){throw 'Profil complet requis pour appliquer les options.'}
    if(-not [guid]::TryParse([string]$profile.ProfileId,[ref]([guid]::Empty))){throw 'Identite du profil invalide.'}
    foreach($definition in Get-BastosCleanupDefinitions){if($profile.Options.($definition.Option) -isnot [bool]){throw ('Option invalide : '+$definition.Option)}}
    if($profile.KeyboardLayout -notmatch '^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$'){throw 'Clavier du profil invalide.'}
    [void][Globalization.CultureInfo]::GetCultureInfo($profile.UILanguage)
    [void][Globalization.CultureInfo]::GetCultureInfo($profile.Locale)
    Assert-BastosFirstLogonContext $profile
    $errors=[Collections.Generic.List[string]]::new()
    try{
        $list=New-WinUserLanguageList -Language $profile.UILanguage
        $list[0].InputMethodTips.Clear()
        $list[0].InputMethodTips.Add([string]$profile.KeyboardLayout)
        Set-WinUserLanguageList -LanguageList $list -Force -ErrorAction Stop
        Set-WinUILanguageOverride -Language $profile.UILanguage -ErrorAction Stop
        Set-Culture -CultureInfo $profile.Locale -ErrorAction Stop
        Set-WinDefaultInputMethodOverride -InputTip $profile.KeyboardLayout -ErrorAction Stop
    }catch{$errors.Add('Langues : '+$_.Exception.Message)}
    if(Test-BastosCleanInstallation $profile){try{Invoke-BastosCleanUserConfiguration}catch{$errors.Add('Profil propre : '+$_.Exception.Message)}}
    foreach($setting in Get-BastosRequestedRegistrySettings $profile){
        try{Set-BastosInstallationRegistrySetting $setting}
        catch{$errors.Add($setting.Option+' ['+$setting.Path+'|'+$setting.Name+'] : '+$_.Exception.Message)}
    }
    $patterns=@(if(Test-BastosRufusQolRequested $profile){'*Outlook*';'*Teams*'};if(Test-BastosCleanInstallation $profile){Get-BastosMinimalAppNames};if($profile.Options.RemoveTeams){'MSTeams';'MicrosoftTeams'};if($profile.Options.RemoveOutlook){'Microsoft.OutlookForWindows'};if($profile.Options.DisableCopilot){'Microsoft.Copilot';'Microsoft.Windows.Ai.Copilot.Provider'};if($profile.Options.RemoveOneDrive){'Microsoft.OneDriveSync'})
    foreach($pattern in $patterns){
        try{
            foreach($package in @(Get-BastosOnlineProvisionedPackages|Where-Object DisplayName -like $pattern)){Remove-BastosOnlineProvisionedPackage $package}
            Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Stop|Remove-AppxPackage -AllUsers -ErrorAction Stop
        }catch{$errors.Add($pattern+' : '+$_.Exception.Message)}
    }
    if($profile.Options.RemoveOneDrive){try{Invoke-BastosOneDriveUninstall}catch{$errors.Add('OneDrive : '+$_.Exception.Message)}}
    $checks=@(Get-BastosInstallationOptionChecks $profile)
    $expectedIds=@('preferredlanguage')+@(Get-BastosCleanupDefinitions|ForEach-Object Id)
    if($checks.Count -ne 8 -or (@($checks.Id|Sort-Object) -join ',') -ne (@($expectedIds|Sort-Object) -join ',')){throw 'Controles des options incomplets.'}
    $report=[ordered]@{Schema=2;ProfileId=$profile.ProfileId;ProfileSha256=(Get-FileHash -LiteralPath $ProfilePath).Hash;CheckedUtc=[DateTime]::UtcNow.ToString('o');Passed=($errors.Count -eq 0 -and @($checks|Where-Object Status -notin @('Passed','NotRequested')).Count -eq 0);Checks=$checks;ApplicationErrors=$errors.ToArray()}
    $parent=Split-Path -Parent $ResultPath;New-Item -ItemType Directory $parent -Force|Out-Null
    $temporary=$ResultPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{[IO.File]::WriteAllText($temporary,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $temporary -Destination $ResultPath -Force}
    finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    if(-not $report.Passed){throw 'Options non confirmees. Consulte Installation-Options.json puis le bilan Bastos.'}
    return [pscustomobject]$report
}


# Port of Rufus v4.15 src/wue.c, UNATTEND_QOL_ENHANCEMENTS (GPL-3.0-or-later).
# Values and specialize commands are compared with the bundled upstream in tests.
function Get-BastosRufusQolSpecializeCommands {
    $commands=@'
[
  "reg add \"HKLM\\Software\\Policies\\Microsoft\\Windows\\OneDrive\" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f",
  "PowerShell -NonInteractive -WindowStyle Hidden -Command \"Remove-Item -Path $env:SystemRoot\\System32\\OneDriveSetup.exe -Force -Confirm:$false; Remove-Item -Path $env:SystemRoot\\SysWOW64\\OneDriveSetup.exe -Force -Confirm:$false;\"",
  "PowerShell -NonInteractive -WindowStyle Hidden -Command \"Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -like '*Outlook*'} | Remove-AppxProvisionedPackage -Online\"",
  "PowerShell -NonInteractive -WindowStyle Hidden -Command \"Get-AppxPackage -AllUsers *Outlook* | Remove-AppxPackage -AllUsers\"",
  "PowerShell -NonInteractive -WindowStyle Hidden -Command \"Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -like '*Teams*'} | Remove-AppxProvisionedPackage -Online\"",
  "PowerShell -NonInteractive -WindowStyle Hidden -Command \"Get-AppxPackage -AllUsers *Teams* | Remove-AppxPackage -AllUsers\""
]
'@ | ConvertFrom-Json
    foreach($command in $commands){$command}
}
function Get-BastosRufusQolRegistrySettings {
    $entries=@'
[
  {
    "Value": 1,
    "Name": "DisableFileSyncNGSC",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Windows\\OneDrive",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "HiberbootEnabled",
    "Type": "DWord",
    "Path": "HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "ShowCopilotButton",
    "Type": "DWord",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "TurnOffWindowsCopilot",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Windows\\WindowsCopilot",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "SearchboxTaskbarMode",
    "Type": "DWord",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "SearchboxTaskbarModeCache",
    "Type": "DWord",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "DisableWindowsConsumerFeatures",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Windows\\CloudContent",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "SystemPaneSuggestionsEnabled",
    "Type": "DWord",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "BingSearchEnabled",
    "Type": "DWord",
    "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "AllowNewsAndInterests",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Dsh",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "EnableFeeds",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Windows\\Windows Feeds",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 0,
    "Name": "ConfigureChatAutoInstall",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Communications",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "DisableCloudOptimizedContent",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Windows\\CloudContent",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "HideFirstRunExperience",
    "Type": "DWord",
    "Path": "HKLM:\\Software\\Policies\\Microsoft\\Edge",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": 1,
    "Name": "Start_Layout",
    "Type": "DWord",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
    "Option": "DisableConsumerContent"
  },
  {
    "Value": "ztU0LVr6Q0WC8iLm6vd3PC+zZ+PeiVVDv85h83sYqTe8JIoUDNaJQqCAbtm7okiCRIF1/g0IrkKL2jTtl7ZjlEqwvXRK+WhPi9ZDmAcdqLyGCHNSqlFDQp97J3ZYRlnU",
    "Name": "VisiblePlaces",
    "Type": "Binary",
    "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Start",
    "Option": "DisableConsumerContent"
  }
]
'@ | ConvertFrom-Json
    foreach($entry in $entries){
        if($entry.Type -eq 'Binary'){$entry.Value=[Convert]::FromBase64String([string]$entry.Value)}
        $entry
    }
}
Export-ModuleMember -Function Restore-BastosCleanServices,Get-BastosRufusQolRegistrySettings,Get-BastosRufusQolSpecializeCommands,Get-BastosCleanupDefinitions,Get-BastosRequestedRegistrySettings,Get-BastosInstallationOptionChecks,Test-BastosInstallationEvidence,Invoke-BastosInstallationOptions,Get-BastosTelemetryLevel,Get-BastosMinimalAppNames,Get-BastosCleanPinsJson,Invoke-BastosOfflineMinimalApps
