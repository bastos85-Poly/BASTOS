param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.InstallationOptions.psm1') -Force -PassThru
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.Rufus.psm1') -Force
$count=0
function Check($ok,$text){if(-not $ok){throw $text};$script:count++}
function Refuses([scriptblock]$action,$text){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $text}
$temp=Join-Path $env:TEMP ('Bastos-Clean-'+[guid]::NewGuid().ToString('N'))
$oldProgramData=$env:ProgramData
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $names=@(Get-BastosMinimalAppNames)
    Check ($names.Count -gt 30 -and @($names|Where-Object {$_ -match '[*?]'}).Count -eq 0) 'Explicit bounded app identities, no wildcard sweep'
    $protected=@('Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.ShellExperienceHost','Microsoft.SecHealthUI','Microsoft.VCLibs.140.00','Microsoft.UI.Xaml.2.8','Microsoft.GamingServices','Microsoft.XboxIdentityProvider','Microsoft.Xbox.TCUI','Microsoft.WindowsNotepad','Microsoft.WindowsCalculator','Microsoft.ScreenSketch','Microsoft.YourPhone','MicrosoftCorporationII.QuickAssist')
    foreach($name in $protected){Check ($name -notin $names) ('Essential package excluded: '+$name)}
    $pins=Get-BastosCleanPinsJson|ConvertFrom-Json
    Check (@($pins.pinnedList).Count -eq 3 -and $pins.applyOnce -eq $true) 'Exactly three initial pins with applyOnce'
    Check ($pins.pinnedList[0].packagedAppId -match 'immersivecontrolpanel') 'Settings pinned'
    Check ($pins.pinnedList[1].desktopAppId -eq 'Microsoft.Windows.Explorer') 'Explorer pinned'
    Check ($pins.pinnedList[2].desktopAppLink -like '*\BASTOS.lnk') 'BASTOS pinned via common shortcut'
    $image=Join-Path $temp 'Image'
    New-Item -ItemType Directory -Path (Join-Path $image 'Windows\PolicyDefinitions') -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $image 'Windows\PolicyDefinitions\StartMenu.admx'),'ConfigureStartPinsJSON')
    & $module {param($names,$protected)
        $script:Packages=@(@($names)+@($protected)|ForEach-Object {[pscustomobject]@{DisplayName=$_;PackageName=($_+'_fixture')}})
        $script:FailRemoval=$false;$script:Removed=@()
        function script:Get-AppxProvisionedPackage{param($Path,$ErrorAction)$script:Packages}
        function script:Remove-AppxProvisionedPackage{param($Path,$PackageName,$ErrorAction)
            if($script:FailRemoval){throw 'DISM refused package'}
            $script:Removed+=$PackageName;$script:Packages=@($script:Packages|Where-Object PackageName -ne $PackageName)
        }
        function script:Get-ItemProperty{param($LiteralPath,$ErrorAction)[pscustomobject]@{EditionID='Professional'}}
    } $names $protected
    $report=Invoke-BastosOfflineMinimalApps -ImagePath $image
    Check (@($report.Removed).Count -eq $names.Count -and @($report.RemainingTargets).Count -eq 0) 'Offline removal covers every selected identity'
    $remaining=& $module {@($script:Packages.DisplayName)}
    foreach($name in $protected){Check ($name -in $remaining) ('Offline cleanup preserves '+$name)}
    & $module {$script:Packages=@([pscustomobject]@{DisplayName='Microsoft.BingNews';PackageName='News_fixture'});$script:FailRemoval=$true}
    Refuses {Invoke-BastosOfflineMinimalApps -ImagePath $image} 'DISM refusal propagated before image commit'
    [IO.File]::WriteAllText((Join-Path $image 'Windows\PolicyDefinitions\StartMenu.admx'),'old policy definitions')
    Refuses {Invoke-BastosOfflineMinimalApps -ImagePath $image} 'Unsupported Start policy rejected before removals'
    $xmlText=[regex]::Match([IO.File]::ReadAllText((Join-Path $SourceRoot 'Tests\Test-RufusQolParity.ps1')),'(?s)<unattend xmlns=.*?</unattend>').Value
    [xml]$document=$xmlText
    $options=[pscustomobject]@{UserName='BastosLab';ComputerName='BASTOS-LAB';WindowsLocale='fr-FR';WindowsUILanguage='fr-FR';KeyboardLayout='040C:0000040C';RecoveryPartitionGuid='';WindowsDiskIdentity='';BypassHardwareChecks=$false;UseCleanBastosInstallation=$true;UseExactRufusExperience=$false;DisableTelemetry=$false;DisableConsumerContent=$false;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$false}
    Set-BastosRufusAccountFlow -Document $document -Options $options -FirstLogonScriptPath (Join-Path $temp 'Rufus-FirstLogon.ps1') -EditionId Professional
    $profile=Get-Content (Join-Path $temp 'Installation-Expected.json') -Raw|ConvertFrom-Json
    Check ($profile.Options.CleanBastosVersion -eq '1' -and $profile.Options.RufusExperienceVersion -eq '') 'Generated expected profile binds clean mode without claiming strict Rufus'
    $startCommands=@($document.SelectNodes('//*[local-name()="settings" and @pass="specialize"]//*[local-name()="RunSynchronousCommand"]')|Where-Object {$_.Description -eq 'BASTOS initial Start shortcut'})
    Check ($startCommands.Count -eq 1) 'Common Start shortcut created before first sign-in'
    Check ($startCommands[0].Path -like '*New-BASTOS-DesktopShortcut.ps1" -CommonStartMenuOnly' -and $startCommands[0].Path.Length -le 259) 'Specialize command invokes verified shortcut helper within Windows limit'
    Check ((Get-FileHash (Join-Path $temp 'New-BASTOS-DesktopShortcut.ps1')).Hash -eq (Get-FileHash (Join-Path $SourceRoot 'InstallerScripts\New-BASTOS-DesktopShortcut.ps1')).Hash) 'Pre-logon shortcut helper packaged without changes'
    $orders=@($document.SelectNodes('//*[local-name()="settings" and @pass="specialize"]//*[local-name()="RunSynchronousCommand"]')|ForEach-Object {[int]$_.Order})
    Check ((@($orders|Sort-Object -Unique).Count -eq $orders.Count) -and $orders[0] -eq 1) 'Specialize command ordering remains unique'
    foreach($flag in @('DisableTelemetry','DisableConsumerContent','RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){Check ($profile.Options.$flag) ('Clean profile forces '+$flag)}
    $requested=@(Get-BastosRequestedRegistrySettings $profile)
    Check (@($requested|Where-Object Name -in @('EnableFeeds','ConfigureChatAutoInstall','TaskbarDa')).Count -eq 0) 'Clean mode omits legacy feeds and protected user preferences'
    Check (@($requested|Where-Object {$_.Name -eq 'AllowNewsAndInterests' -and $_.Value -eq 0}).Count -eq 1) 'Clean mode always disables established Widgets policy even when preview ADMX exists'
    Check ($document.SelectSingleNode('//*[local-name()="ConfigureChatAutoInstall"]').InnerText -eq 'false') 'Clean mode configures Chat through official unattend setting'
    Check (@($requested|Where-Object {$_.Name -eq 'AllowTelemetry' -and $_.Value -eq 1}).Count -eq 1) 'Pro keeps required diagnostic floor, no fake telemetry zero'
    Check (@($requested|Where-Object Name -eq ConfigureStartPinsJSON).Count -eq 1) 'Start policy included in requested verification'
    $evidence=@{Registry=@{};RegistryErrors=@{};Packages=@();Provisioned=@();PackageError='';OneDriveEntries=@();OneDriveFiles=@();OneDriveStartup=@();OneDriveError='';QolOneDriveSetupFiles=@();QolFileError='';PreferredLanguages=@('fr-FR');LanguageError='';CleanPrivacyError='';CleanPrivacyMismatches=@();CleanLayoutError=''}
    foreach($setting in $requested){$evidence.Registry[$setting.Path+'|'+$setting.Name]=$setting.Value}
    $checks=@(Test-BastosInstallationEvidence $profile $evidence $requested)
    Check (@($checks|Where-Object Status -notin @('Passed','NotRequested')).Count -eq 0) 'Complete clean configuration passes evidence checks'
    Check (@($checks|Where-Object {$_.Id -eq 'suggestions' -and $_.Expected -eq 'Configured'}).Count -eq 1) 'Start configuration distinct from visual proof'
    Check (@($checks|Where-Object {$_.Id -eq 'widgets' -and $_.Expected -eq 'Configured' -and $_.Detail -match 'ne prouve pas'}).Count -eq 1) 'Widgets registry verification does not claim visual proof'
    $widgetKey='HKLM:\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests'
    $evidence.Registry.Remove($widgetKey)
    Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object {$_.Id -eq 'widgets' -and $_.Status -eq 'Mismatch'}).Count -eq 1) 'Missing established policy cannot pass with only preview policy'
    $evidence.Registry[$widgetKey]=0
    foreach($name in @('Microsoft.BingNews','Clipchamp.Clipchamp','Microsoft.GamingApp')){
        $evidence.Packages=@($name)
        Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object {$_.Id -eq 'suggestions' -and $_.Status -eq 'Mismatch'}).Count -eq 1) ('Remaining minimal app detected: '+$name)
    }
    $evidence.Packages=@();$evidence.CleanPrivacyMismatches=@('DiagTrack')
    Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object {$_.Id -eq 'privacy' -and $_.Status -eq 'Mismatch'}).Count -eq 1) 'Diagnostic service mismatch detected'
    $evidence.Remove('CleanPrivacyError')
    Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object {$_.Id -eq 'privacy' -and $_.Status -eq 'Unavailable'}).Count -eq 1) 'Missing privacy evidence never passes'
    $evidence.CleanLayoutError='missing file'
    Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object {$_.Id -eq 'suggestions' -and $_.Status -eq 'Unavailable'}).Count -eq 1) 'Missing pin file never passes'
    $options.UseExactRufusExperience=$true
    Refuses {Set-BastosRufusAccountFlow -Document $document -Options $options -FirstLogonScriptPath (Join-Path $temp 'Bad.ps1')} 'Conflicting profiles rejected'
    $first=[IO.File]::ReadAllText((Join-Path $temp 'Rufus-FirstLogon.ps1'))
    Check ($first.IndexOf('New-BASTOS-DesktopShortcut.ps1') -lt $first.IndexOf('Invoke-BastosInstallationOptions')) 'BASTOS shortcut created before pin configuration verification'
    # Run the real clean configuration function using only fake service/task APIs.
    $env:ProgramData=Join-Path $temp 'ProgramData'
    $programs=Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Path $programs -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $programs 'BASTOS.lnk'),'fixture')
    & $module {
        Initialize-BastosStartPolicyType # Compile interop only; never create COM on the host.
        $script:SavedPins=''
        function script:Set-BastosCleanStartPolicy{param($File)$script:SavedPins=$File}
        function script:Test-BastosCleanStartPolicy{param($File)return $File -eq $script:SavedPins}
        $script:Tasks=@([pscustomobject]@{TaskPath='\Microsoft\Windows\Customer Experience Improvement Program\';TaskName='Consolidator';State='Ready'},[pscustomobject]@{TaskPath='\Microsoft\Windows\Windows Defender\';TaskName='Windows Defender Scheduled Scan';State='Ready'})
        $script:Stopped=@();$script:Disabled=@()
        function script:Get-Service{param($Name,$ErrorAction)[pscustomobject]@{Name='DiagTrack'}}
        function script:Stop-Service{param($Name,[switch]$Force,$ErrorAction)$script:Stopped+=$Name}
        function script:Set-Service{param($Name,$StartupType,$ErrorAction)$script:Disabled+=$Name}
        function script:Get-ScheduledTask{param($ErrorAction)$script:Tasks}
        function script:Disable-ScheduledTask{param($InputObject,$ErrorAction)$InputObject.State='Disabled'}
        function script:Get-CimInstance{param($ClassName,$Filter,$ErrorAction)[pscustomobject]@{StartMode='Disabled';State='Stopped'}}
        function script:Get-ItemProperty{param($LiteralPath,$ErrorAction)[pscustomobject]@{Start=3;DelayedAutoStart=0}}
        function script:Set-ItemProperty{param($LiteralPath,$Name,$Value,$ErrorAction)}
        function script:Start-Service{param($Name,$ErrorAction)}
        Invoke-BastosCleanUserConfiguration
    }
    Check ((Get-Content (Join-Path $env:ProgramData 'BASTOS-ISO\StartPins.json') -Raw) -ceq (Get-BastosCleanPinsJson)) 'Actual pin file generation uses all three identities'
    $state=& $module {Get-BastosCleanEvidence}
    Check ($state.CleanPrivacyError -eq '' -and $state.CleanPrivacyMismatches.Count -eq 0 -and $state.CleanLayoutError -eq '') 'Real collector accepts independently queried disabled state'
    Check ((& $module {$script:SavedPins}) -eq (Join-Path $env:ProgramData 'BASTOS-ISO\StartPins.json')) 'Layout registered through local GPO API rather than registry preference alone'
    Check ((& $module {($script:Stopped -join ',')}) -eq 'DiagTrack,RetailDemo,MapsBroker' -and (& $module {($script:Disabled -join ',')}) -eq 'DiagTrack,RetailDemo,MapsBroker') 'Only the three named services touched'
    $backupPath=Join-Path $env:ProgramData 'BASTOS-ISO\Services-Before.json'
    $backupText=[IO.File]::ReadAllText($backupPath)
    Check (@(($backupText|ConvertFrom-Json).Services).Count -eq 3) 'Original settings saved for every present service'
    Check ((Get-Content (Join-Path $env:ProgramData 'BASTOS-ISO\Services-Applied.json') -Raw|ConvertFrom-Json).Disabled.Count -eq 3) 'Verified service changes recorded'
    & $module {Invoke-BastosCleanServices}
    Check ([IO.File]::ReadAllText($backupPath) -ceq $backupText) 'Repeated application preserves original backup'
    Restore-BastosCleanServices
    Check ((& $module {$script:Disabled[-1]}) -eq 'MapsBroker') 'Restore accepts validated original backup'
    & $module {
        function script:Get-CimInstance{param($ClassName,$Filter,$ErrorAction)if($Filter -eq "Name='MapsBroker'"){[pscustomobject]@{StartMode='Auto';State='Running'}}}
    }
    $state=& $module {Get-BastosCleanEvidence}
    Check ($state.CleanPrivacyMismatches -contains 'MapsBroker') 'Independent evidence rejects a service that remains enabled'
    Refuses {& $module {Invoke-BastosCleanServices}} 'Unconfirmed change cannot report success'
    & $module {function script:Get-CimInstance{param($ClassName,$Filter,$ErrorAction)}}
    & $module {Invoke-BastosCleanServices}
    Check (@((Get-Content (Join-Path $env:ProgramData 'BASTOS-ISO\Services-Applied.json') -Raw|ConvertFrom-Json).Absent).Count -eq 3) 'Missing services are skipped without creating them'
    [IO.File]::WriteAllText($backupPath,'{"Schema":1,"Services":[{"Name":"DiagTrack","StartMode":"Auto","DelayedAutoStart":true,"WasRunning":true},{"Name":"RetailDemo","StartMode":"Manual","DelayedAutoStart":false,"WasRunning":false},{"Name":"MapsBroker","StartMode":"Disabled","DelayedAutoStart":false,"WasRunning":false}]}')
    & $module {
        $script:RestoredModes=@();$script:RestoredDelay=@();$script:Restarted=@()
        function script:Set-Service{param($Name,$StartupType,$ErrorAction)$script:RestoredModes+=($Name+':'+$StartupType)}
        function script:Set-ItemProperty{param($LiteralPath,$Name,$Value,$ErrorAction)$script:RestoredDelay+=$Value}
        function script:Start-Service{param($Name,$ErrorAction)$script:Restarted+=$Name}
    }
    Restore-BastosCleanServices
    Check ((& $module {$script:RestoredModes -join ','}) -eq 'DiagTrack:Automatic,RetailDemo:Manual,MapsBroker:Disabled') 'Restore preserves each original startup mode'
    Check ((& $module {$script:RestoredDelay -join ','}) -eq '1,0,0') 'Delayed automatic startup restored'
    Check ((& $module {$script:Restarted -join ','}) -eq 'DiagTrack') 'Only services originally running restarted'
    [IO.File]::WriteAllText($backupPath,'{"Schema":1,"Services":[{"Name":"WinDefend","StartMode":"Disabled"}]}')
    Refuses {Restore-BastosCleanServices} 'Restore refuses any service outside allowlist'
    Check ((& $module {($script:Tasks|Where-Object TaskName -eq 'Windows Defender Scheduled Scan').State}) -eq 'Ready') 'Security task preserved'
}finally{
    $env:ProgramData=$oldProgramData
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture outside TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count clean-profile checks; DISM, services and tasks mocked; no Windows setting changed."
