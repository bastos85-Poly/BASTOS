param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.InstallationOptions.psm1') -Force
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.Rufus.psm1') -Force
$count=0
function Check([bool]$ok,[string]$name){if(-not $ok){throw $name};$script:count++;Write-Output "OK : $name"}
$flags=@{RufusQolVersion='4.15';DisableTelemetry=$true;DisableConsumerContent=$true;RemoveOneDrive=$true;RemoveTeams=$true;RemoveOutlook=$true;DisableCopilot=$true;DisableWidgets=$true}
$profile=[pscustomobject]@{Schema=2;ProfileId=[guid]::NewGuid().ToString('D');UILanguage='fr-FR';Locale='fr-FR';KeyboardLayout='040C:0000040C';Options=[pscustomobject]$flags}
$settings=@(Get-BastosRequestedRegistrySettings $profile)
function Evidence {
    $e=@{QolOneDriveSetupFiles=@();QolFileError='';Registry=@{};RegistryErrors=@{};Packages=@();Provisioned=@();PackageError='';OneDriveEntries=@();OneDriveFiles=@();OneDriveStartup=@();OneDriveError='';PreferredLanguages=@('fr-FR');LanguageError=''}
    foreach($setting in $settings){$e.Registry[$setting.Path+'|'+$setting.Name]=$setting.Value}
    return $e
}
function Checks($e){@(Test-BastosInstallationEvidence $profile $e $settings)}
function Find($checks,[string]$id){$checks|Where-Object Id -eq $id}
Check (@(Checks (Evidence)|Where-Object Status -ne 'Passed').Count -eq 0) 'Toutes les preuves independantes conformes donnent huit controles d options valides'
foreach($edition in @('Professional','Core','ProfessionalWorkstation')){Check ((Get-BastosTelemetryLevel $edition) -eq 1) ('Diagnostic requis conserve sur '+$edition)}
foreach($edition in @('Enterprise','EnterpriseS','Education','IoTEnterpriseS')){Check ((Get-BastosTelemetryLevel $edition) -eq 0) ('Niveau diagnostique adapte a '+$edition)}
$e=Evidence;$e.PreferredLanguages=@('en-US','fr-FR');Check ((Find (Checks $e) 'preferredlanguage').Status -eq 'Mismatch') 'Anglais prioritaire refuse'
$e=Evidence;$e.PreferredLanguages=@('fr-FR','en-US');Check ((Find (Checks $e) 'preferredlanguage').Status -eq 'Mismatch') 'Langue anglaise ajoutee sans demande signalee'
foreach($definition in Get-BastosCleanupDefinitions){
    $profile.Options.($definition.Option)=$false
    Check ((Find (Checks (Evidence)) $definition.Id).Status -eq 'NotRequested') ('Option decochee conservee : '+$definition.Option)
    $profile.Options.($definition.Option)=$true
}
foreach($setting in $settings){$e=Evidence;$e.Registry[$setting.Path+'|'+$setting.Name]=999;Check (@(Checks $e|Where-Object Status -eq 'Mismatch').Count -ge 1) ('Valeur divergente detectee : '+$setting.Name)}
foreach($pattern in @('MSTeams','MicrosoftTeams','Microsoft.OutlookForWindows','Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.OneDriveSync')){
    foreach($source in @('Packages','Provisioned')){$e=Evidence;$e[$source]=@($pattern);Check (@(Checks $e|Where-Object Status -eq 'Mismatch').Count -ge 1) ('Presence '+$source+' detectee : '+$pattern)}
}
$e=Evidence;$e.PackageError='access denied';Check (@(Checks $e|Where-Object Status -eq 'Unavailable').Count -eq 5) 'Inventaire tous comptes indisponible ne devient pas une absence'
foreach($source in @('OneDriveFiles','OneDriveEntries','OneDriveStartup')){$e=Evidence;$e[$source]=@('present');Check ((Find (Checks $e) 'onedrive').Status -eq 'Mismatch') ('OneDrive encore present : '+$source)}
$e=Evidence;$setting=$settings[0];$e.RegistryErrors[$setting.Path+'|'+$setting.Name]='denied';Check ((Find (Checks $e) 'privacy').Status -eq 'Unavailable') 'Refus registre reste non verifie'
Check (@($settings|Where-Object Name -eq 'DisableWindowsConsumerFeatures').Count -eq 1) 'Strategie Rufus incluse avec les preferences utilisateur Pro'
$temporary=Join-Path $env:TEMP ('Bastos-Options-Test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary|Out-Null
try{
    function Template {
        [xml]@'
<unattend xmlns="urn:schemas-microsoft-com:unattend"><settings pass="windowsPE"><component name="Microsoft-Windows-International-Core-WinPE"><UILanguage>fr-FR</UILanguage><InputLocale>040C:0000040C</InputLocale><SystemLocale>fr-FR</SystemLocale></component></settings><settings pass="specialize"><component name="Microsoft-Windows-Shell-Setup"><ComputerName>OLD</ComputerName></component></settings><settings pass="oobeSystem"><component name="Microsoft-Windows-International-Core"><UILanguage>fr-FR</UILanguage><InputLocale>040C:0000040C</InputLocale><UserLocale>fr-FR</UserLocale><SystemLocale>fr-FR</SystemLocale></component><component name="Microsoft-Windows-Shell-Setup"><UserAccounts><LocalAccounts><LocalAccount><Name>BastOS</Name><DisplayName>BastOS</DisplayName><Password><Value></Value><PlainText>false</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts><RegisteredOwner>BastOS</RegisteredOwner><OOBE><ProtectYourPC>1</ProtectYourPC></OOBE></component></settings></unattend>
'@
    }
    $options=[pscustomobject]@{Schema=1;UserName='BastosLab';ComputerName='BASTOS-LAB';WindowsLocale='fr-FR';WindowsUILanguage='fr-FR';KeyboardLayout='0409:00000409';KeepOnlyRecoveryPartition=$true;BypassHardwareChecks=$false;DisableTelemetry=$true;DisableConsumerContent=$true;RemoveOneDrive=$true;RemoveTeams=$true;RemoveOutlook=$true;DisableCopilot=$true;DisableWidgets=$true;RecoveryPartitionGuid='';WindowsDiskIdentity='';DiskSafetySnapshot='';WindowsEditionId='Professional'}
    $document=Template
    $firstLogon=Join-Path $temporary 'Rufus-FirstLogon.ps1'
    Set-BastosRufusAccountFlow -Document $document -Options $options -FirstLogonScriptPath $firstLogon -EditionId Professional
    $expected=Get-Content (Join-Path $temporary 'Installation-Expected.json') -Raw|ConvertFrom-Json
    Check ($expected.Schema -eq 2 -and $expected.Options.RemoveOneDrive -and $expected.Options.DisableWidgets) 'Profil complet conserve les cases demandees'
    Check ($expected.KeyboardLayout -eq '040C:00000409' -and $expected.UILanguage -eq 'fr-FR') 'QWERTY physique conserve sans langue anglaise prioritaire'
    Check (Test-Path (Join-Path $temporary 'Bastos.InstallationOptions.psm1')) 'Module application/controle copie dans le media'
    $script=[IO.File]::ReadAllText($firstLogon)
    Check ($script.IndexOf('Invoke-BastosInstallationOptions') -lt $script.LastIndexOf('Rufus-FirstLogon.ok')) 'Options controlees avant la marque de finalisation'
    Check ($script.Contains('ProfileSha256') -and $script.Contains('exit 1')) 'Finalisation liee au profil et erreur bloquante'
    Check (-not $script.Contains('-ErrorAction Continue')) 'Pas de masquage des erreurs de suppression Appx'
    $optionsPath=Join-Path $temporary 'Options.json';$options|ConvertTo-Json|Set-Content $optionsPath -Encoding UTF8
    Check ((Read-BastosRufusOptions $optionsPath).DisableWidgets) 'Option widgets lue sans perte'
    $options.DisableWidgets='yes';$options|ConvertTo-Json|Set-Content $optionsPath -Encoding UTF8
    $refused=$false;try{Read-BastosRufusOptions $optionsPath|Out-Null}catch{$refused=$true};Check $refused 'Booleen widgets invalide refuse'
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($firstLogon,[ref]$tokens,[ref]$errors)|Out-Null;Check ($errors.Count -eq 0) 'Script genere valide en Windows PowerShell 5.1'
    $harness=Join-Path $temporary 'Harness.ps1'
    @'
param([string]$Root,[string]$Scenario)
$env:ProgramData=$Root
$env:BASTOS_OPTIONS_TEST_FAILURE=$Scenario
$global:netCalls=0
function global:net.exe {$global:netCalls++;$global:LASTEXITCODE=0}
function global:Set-ItemProperty {param($LiteralPath,$Name,$Value)}
function global:Remove-ItemProperty {param($LiteralPath,$Name,[switch]$Force,$ErrorAction)}
function global:Get-Volume {param($FileSystemLabel,$ErrorAction) if($FileSystemLabel){throw 'No volume matching the requested label'}; @()}
foreach($command in @('net.exe','Set-ItemProperty','Remove-ItemProperty','Get-Volume')){if((Get-Command $command).CommandType -ne 'Function'){throw 'Windows mutation mock missing'}}
& (Join-Path $Root 'BASTOS-ISO\Rufus-FirstLogon.ps1')
$scriptExitCode=$LASTEXITCODE
if($global:netCalls -ne 0){throw 'FirstLogon must never change account authentication'}
exit $scriptExitCode
'@ | Set-Content -LiteralPath $harness -Encoding UTF8
    foreach($scenario in @('success','failure')){
        $child=Join-Path $temporary ('generated-'+$scenario);$payload=Join-Path $child 'BASTOS-ISO';New-Item -ItemType Directory $payload -Force|Out-Null
        Copy-Item -LiteralPath $firstLogon -Destination $payload
        Copy-Item -LiteralPath (Join-Path $temporary 'Installation-Expected.json') -Destination $payload
        @'
function Invoke-BastosInstallationOptions {param($ProfilePath,$ResultPath) if($env:BASTOS_OPTIONS_TEST_FAILURE -eq 'failure'){throw 'Simulated cleanup failure'}}
Export-ModuleMember -Function Invoke-BastosInstallationOptions
'@ | Set-Content -LiteralPath (Join-Path $payload 'Bastos.InstallationOptions.psm1') -Encoding UTF8
        '# Simulated shortcut; no Windows mutation' | Set-Content (Join-Path $payload 'New-BASTOS-DesktopShortcut.ps1') -Encoding UTF8
        '# Simulated read-only inspection' | Set-Content (Join-Path $payload 'Test-BASTOS-InstalledWindows.ps1') -Encoding UTF8
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $harness -Root $child -Scenario $scenario *> (Join-Path $child 'console.log')
        $exitCode=$LASTEXITCODE;$marker=Join-Path $payload 'Logs\Rufus-FirstLogon.ok'
        Check (($exitCode -eq 0) -eq ($scenario -eq 'success')) ('Script genere retourne le bon resultat : '+$scenario)
        Check ((Test-Path $marker) -eq ($scenario -eq 'success')) ('Marque de finalisation exige un vrai succes du nettoyage : '+$scenario)
        if($scenario -eq 'success'){$receipt=Get-Content $marker -Raw|ConvertFrom-Json;Check ($receipt.ProfileId -eq $expected.ProfileId -and $receipt.ProfileSha256 -eq (Get-FileHash (Join-Path $payload 'Installation-Expected.json')).Hash) 'Recu du script genere lie au bon profil'}
    }
    # Exercise the real orchestration with all Windows mutations replaced in module scope.
    $profile|Add-Member -NotePropertyName UserName -NotePropertyValue 'BastosLab'
    $applyProfile=Join-Path $temporary 'ApplyProfile.json';$profile|ConvertTo-Json -Depth 5|Set-Content $applyProfile -Encoding UTF8
    $module=Get-Module Bastos.InstallationOptions
    foreach($scenario in @('success','appx-failure','onedrive-failure','all-off')){
        if($scenario -eq 'all-off'){
            foreach($definition in Get-BastosCleanupDefinitions){$profile.Options.($definition.Option)=$false}
            $profile|ConvertTo-Json -Depth 5|Set-Content $applyProfile -Encoding UTF8
        }
        $context=@{Scenario=$scenario;Languages=0;OneDrive=0;Patterns=[Collections.Generic.List[string]]::new();Checks=@(Checks (Evidence))}
        & $module {
            param($context)
            $script:testContext=$context
            function script:Assert-BastosFirstLogonContext {param($Profile)}
            function script:Get-BastosRequestedRegistrySettings {param($Profile) @()}
            function script:New-WinUserLanguageList {param($Language) ,@([pscustomobject]@{InputMethodTips=[Collections.Generic.List[string]]::new()})}
            function script:Set-WinUserLanguageList {[CmdletBinding()]param($LanguageList,[switch]$Force) $script:testContext.Languages++}
            function script:Set-WinUILanguageOverride {[CmdletBinding()]param($Language)}
            function script:Set-Culture {[CmdletBinding()]param($CultureInfo)}
            function script:Set-WinDefaultInputMethodOverride {[CmdletBinding()]param($InputTip)}
            function script:Get-AppxProvisionedPackage {[CmdletBinding()]param([switch]$Online) if($script:testContext.Scenario -eq 'appx-failure'){throw 'simulated Appx failure'}}
            function script:Get-BastosProvisionedPackagesViaWindowsApi {throw 'simulated fallback unavailable'}
            function script:Get-AppxPackage {[CmdletBinding()]param([switch]$AllUsers,$Name) $script:testContext.Patterns.Add([string]$Name)}
            function script:Remove-AppxProvisionedPackage {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$Package,[switch]$Online) process{}}
            function script:Remove-AppxPackage {[CmdletBinding()]param([Parameter(ValueFromPipeline)]$Package,[switch]$AllUsers) process{}}
            function script:Invoke-BastosOneDriveUninstall {$script:testContext.OneDrive++;if($script:testContext.Scenario -eq 'onedrive-failure'){throw 'simulated OneDrive failure'}}
            function script:Get-BastosInstallationOptionChecks {param($Profile) $script:testContext.Checks}
        } $context
        $resultFile=Join-Path $temporary ($scenario+'.json');$failed=$false
        try{Invoke-BastosInstallationOptions -ProfilePath $applyProfile -ResultPath $resultFile|Out-Null}catch{$failed=$true}
        $result=Get-Content $resultFile -Raw|ConvertFrom-Json
        $expectSuccess=$scenario -in @('success','all-off')
        Check ($result.Passed -eq $expectSuccess -and $failed -ne $expectSuccess) ('Orchestration ne masque pas une erreur : '+$scenario)
        Check ($context.Languages -eq 1 -and $context.OneDrive -eq $(if($scenario -eq 'all-off'){0}else{1})) ('Langue et OneDrive respectent la selection : '+$scenario)
        if($scenario -eq 'all-off'){Check ($context.Patterns.Count -eq 0) 'Aucune suppression Appx si toutes les options sont decochees'}
        if($scenario -eq 'success'){Check ($context.Patterns.Count -eq 8 -and 'MSTeams' -in $context.Patterns -and 'Microsoft.Copilot' -in $context.Patterns) 'Chaque identifiant Appx est traite individuellement'}
    }
}finally{
    $resolved=[IO.Path]::GetFullPath($temporary);$tempRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Nettoyage fixture hors TEMP refuse'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count controles options ; aucun reglage Windows applique, aucune application supprimee."
