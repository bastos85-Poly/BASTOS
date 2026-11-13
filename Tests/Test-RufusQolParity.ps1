param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.InstallationOptions.psm1') -Force
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.Rufus.psm1') -Force
$count=0
function Check([bool]$value,[string]$message){if(-not $value){throw $message};$script:count++}
$upstream=[IO.File]::ReadAllText((Join-Path $SourceRoot 'ThirdParty\Rufus\wue-qol-v4.15.c'))
$blocks=[regex]::Matches($upstream,'(?s)if \(flags & UNATTEND_QOL_ENHANCEMENTS\) \{(.*?)\n\t\t\s*\}')
function Extract($block){foreach($match in [regex]::Matches($block,'(?s)StrArrayAdd\(&commands,\s*((?:"(?:\\.|[^"\\])*"\s*)+),\s*TRUE\);')){([regex]::Matches($match.Groups[1].Value,'"((?:\\.|[^"\\])*)"')|ForEach-Object {[regex]::Unescape($_.Groups[1].Value)}) -join ''}}
$specialize=@(Extract $blocks[0].Groups[1].Value)
$first=@(Extract $blocks[1].Groups[1].Value)
Check ((@(Get-BastosRufusQolSpecializeCommands) -join "`n") -ceq ($specialize -join "`n")) 'Commandes specialize divergentes de Rufus'
$settings=@(Get-BastosRufusQolRegistrySettings)
Check ($settings.Count -eq 16) '16 valeurs QoL attendues (15 first logon et strategie OneDrive)'
foreach($command in @($specialize[0])+$first){
    if($command -match '^reg add "(HKLM|HKCU)\\(.+)" /v (\w+) /t REG_DWORD /d (\d+) /f$'){
        $path=$Matches[1]+':\'+$Matches[2];$name=$Matches[3];$value=[int]$Matches[4]
        Check (@($settings|Where-Object {$_.Path -ieq $path -and $_.Name -ceq $name -and $_.Value -eq $value -and $_.Type -eq 'DWord'}).Count -eq 1) ('Valeur Rufus absente : '+$name)
    }else{
        Check ($command -match "FromBase64String\('([^']+)'\)") 'Commande first logon non couverte'
        $binary=[Convert]::FromBase64String($Matches[1]);$actual=$settings|Where-Object Name -eq VisiblePlaces
        Check ($actual.Type -eq 'Binary' -and [Convert]::ToBase64String($actual.Value) -ceq [Convert]::ToBase64String($binary)) 'Raccourcis Demarrer differents de Rufus'
    }
}
Check (@($settings|Where-Object Name -match 'BitLocker|DeviceEncryption').Count -eq 0) 'BitLocker doit rester hors QoL'
$temporary=Join-Path $env:TEMP ('BASTOS-Qol-Parity-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary|Out-Null
try{
    foreach($selected in @($true,$false)){
        [xml]$document=@'
<unattend xmlns="urn:schemas-microsoft-com:unattend"><settings pass="windowsPE"><component name="Microsoft-Windows-International-Core-WinPE"><UILanguage>fr-FR</UILanguage><InputLocale>040C:0000040C</InputLocale><SystemLocale>fr-FR</SystemLocale></component></settings><settings pass="specialize"><component name="Microsoft-Windows-Shell-Setup"><ComputerName>OLD</ComputerName></component></settings><settings pass="oobeSystem"><component name="Microsoft-Windows-International-Core"><UILanguage>fr-FR</UILanguage><InputLocale>040C:0000040C</InputLocale><UserLocale>fr-FR</UserLocale><SystemLocale>fr-FR</SystemLocale></component><component name="Microsoft-Windows-Shell-Setup"><UserAccounts><LocalAccounts><LocalAccount><Name>BastOS</Name><DisplayName>BastOS</DisplayName><Password><Value></Value><PlainText>false</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts><RegisteredOwner>BastOS</RegisteredOwner><OOBE><ProtectYourPC>1</ProtectYourPC></OOBE></component></settings></unattend>
'@
        $flags=[pscustomobject]@{RufusQolVersion='4.15';DisableTelemetry=$selected;DisableConsumerContent=$selected;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$false}
        $options=[pscustomobject]@{UserName='BastosLab';ComputerName='BASTOS-LAB';WindowsLocale='fr-FR';WindowsUILanguage='fr-FR';KeyboardLayout='040C:0000040C';RecoveryPartitionGuid='';WindowsDiskIdentity='';BypassHardwareChecks=$false;DisableTelemetry=$selected;DisableConsumerContent=$selected;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$false}
        $firstLogon=Join-Path $temporary 'Rufus-FirstLogon.ps1'
        Set-BastosRufusAccountFlow -Document $document -Options $options -FirstLogonScriptPath $firstLogon -EditionId Professional
        $firstLogonText=Get-Content -LiteralPath $firstLogon -Raw -Encoding UTF8
        Check ($firstLogonText -match "Finalize-BASTOS-TemporaryRecovery\.ps1'\) -Apply") 'Restitution automatique de D: absente du premier logon'
        $expected=Get-Content -LiteralPath (Join-Path $temporary 'Installation-Expected.json') -Raw|ConvertFrom-Json
        Check ($expected.Options.RufusQolVersion -eq $(if($selected){'4.15'}else{''})) 'Version QoL liee au profil genere'
        $ns=[Xml.XmlNamespaceManager]::new($document.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
        $actual=@($document.SelectNodes('//u:settings[@pass="specialize"]//u:RunSynchronousCommand[u:Description="BASTOS Rufus"]/u:Path',$ns)|ForEach-Object InnerText)
        Check (($actual.Count -eq $(if($selected){8}else{2}))) 'QoL specialize doit suivre la case selectionnee'
        Check ($actual[1] -match 'DisablePrivacyExperience') 'Ecran de choix de confidentialite non masque'
        if($selected){Check (($actual[2..7] -join "`n") -ceq ($specialize -join "`n")) 'QoL specialize XML divergent'}
        $auto=$document.SelectSingleNode('//u:AutoLogon',$ns)
        $localPassword=$document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccount/u:Password',$ns)
        Check ($null -eq $localPassword -and $expected.AccountProvisioning -eq 'SpecializePasswordlessV1' -and
               $expected.PasswordMode -eq 'Empty') 'Creation specialisee unique du compte sans mot de passe'
        Check ($auto.SelectSingleNode('u:Username',$ns).InnerText -ceq 'BastosLab' -and
               $auto.SelectSingleNode('u:Domain',$ns).InnerText -ceq 'BASTOS-LAB' -and
               $auto.SelectSingleNode('u:Password/u:Value',$ns).InnerText -eq '' -and
               $auto.SelectSingleNode('u:LogonCount',$ns).InnerText -eq '1') 'Premiere connexion sans mot de passe non automatisee'
        Check ($document.SelectSingleNode('//u:ProtectYourPC',$ns).InnerText -eq $(if($selected){'3'}else{'1'})) 'Collecte OOBE divergente de la case'
        $profile=[pscustomobject]@{UILanguage='fr-FR';Options=$flags}
        $requested=@(Get-BastosRequestedRegistrySettings $profile)
        Check (@($requested|Where-Object Name -eq HiberbootEnabled).Count -eq $(if($selected){1}else{0})) 'Fast Startup doit suivre QoL'
        $evidence=@{Registry=@{};RegistryErrors=@{};Packages=@();Provisioned=@();PackageError='';OneDriveEntries=@();OneDriveFiles=@();OneDriveStartup=@();OneDriveError='';QolOneDriveSetupFiles=@();QolFileError='';PreferredLanguages=@('fr-FR');LanguageError=''}
        foreach($setting in $requested){$evidence.Registry[$setting.Path+'|'+$setting.Name]=$setting.Value}
        $qol=@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object Id -eq suggestions)[0]
        Check ($qol.Status -eq $(if($selected){'Passed'}else{'NotRequested'})) 'Verification QoL selon selection'
        if($selected){
            foreach($remaining in @('Contoso.Outlook.New','MSTeams','MicrosoftTeams')){
                $evidence.Packages=@($remaining)
                Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object { $_.Id -eq 'suggestions' -and $_.Status -eq 'Mismatch'}).Count -eq 1) ('Paquet restant non detecte : '+$remaining)
            }
            $evidence.Packages=@();$evidence.QolOneDriveSetupFiles=@('OneDriveSetup.exe')
            Check (@(Test-BastosInstallationEvidence $profile $evidence $requested|Where-Object { $_.Id -eq 'suggestions' -and $_.Status -eq 'Mismatch'}).Count -eq 1) 'Installateur OneDrive restant non detecte'
        }
    }
    foreach($qolSelected in @($true,$false)){
      foreach($privacySelected in @($true,$false)){
        $options | Add-Member -NotePropertyName UseExactRufusExperience -NotePropertyValue $true -Force
        $options.DisableConsumerContent=$qolSelected;$options.DisableTelemetry=$privacySelected
        foreach($extra in @('RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){$options.$extra=$true}
        Set-BastosRufusAccountFlow -Document $document -Options $options -FirstLogonScriptPath $firstLogon -EditionId Professional
        $expected=Get-Content -LiteralPath (Join-Path $temporary 'Installation-Expected.json') -Raw|ConvertFrom-Json
        Check ($expected.Options.RufusExperienceVersion -eq '4.15') 'Mode strict transmis au profil interne'
        foreach($extra in @('RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){Check (-not $expected.Options.$extra) ('Option supplementaire ignoree : '+$extra)}
        $requested=@(Get-BastosRequestedRegistrySettings $expected)
        Check ($requested.Count -eq $(if($qolSelected){16}else{0})) 'Aucune valeur registre supplementaire en mode strict'
        Check (@($requested|Where-Object Name -eq AllowTelemetry).Count -eq 0) 'Rufus ne force pas AllowTelemetry'
        [xml]$oobe=Get-Content -LiteralPath (Join-Path $temporary 'Rufus-Oobe.xml') -Raw
        $protection=$oobe.SelectSingleNode('//*[local-name()="ProtectYourPC"]').InnerText
        Check ($protection -eq $(if($privacySelected){'3'}else{'1'})) 'Archive OOBE conforme au XML final'
        $evidence=@{Registry=@{};RegistryErrors=@{};Packages=@('Microsoft.Copilot','Microsoft.BingNews','Microsoft.OneDriveSync');Provisioned=@();PackageError='';OneDriveEntries=@();OneDriveFiles=@();OneDriveStartup=@();OneDriveError='';QolOneDriveSetupFiles=@();QolFileError='';PreferredLanguages=@('fr-FR');LanguageError='';OobeProtectYourPC=$protection;OobeError=''}
        foreach($setting in $requested){$evidence.Registry[$setting.Path+'|'+$setting.Name]=$setting.Value}
        $checks=@(Test-BastosInstallationEvidence $expected $evidence $requested)
        Check (@($checks|Where-Object Status -notin @('Passed','NotRequested')).Count -eq 0) 'News et Copilot peuvent rester installes comme avec Rufus'
        $privacy=@($checks|Where-Object Id -eq privacy)[0]
        Check ($privacy.Expected -eq $(if($privacySelected){'Configured'}else{'NotRequested'})) 'Configuration OOBE distinguee des effets mesures'
        if($privacySelected){
            $evidence.OobeProtectYourPC='1'
            Check (@(Test-BastosInstallationEvidence $expected $evidence $requested|Where-Object {$_.Id -eq 'privacy' -and $_.Status -eq 'Mismatch'}).Count -eq 1) 'Configuration OOBE divergente refusee'
            $evidence.Remove('OobeProtectYourPC')
            Check (@(Test-BastosInstallationEvidence $expected $evidence $requested|Where-Object {$_.Id -eq 'privacy' -and $_.Status -eq 'Unavailable'}).Count -eq 1) 'Preuve OOBE manquante ne peut pas passer'
        }
      }
    }
    $legacy=[pscustomobject]@{Options=[pscustomobject]@{DisableTelemetry=$false;DisableConsumerContent=$true;RemoveOneDrive=$false;RemoveTeams=$false;RemoveOutlook=$false;DisableCopilot=$false;DisableWidgets=$false}}
    Check (@(Get-BastosRequestedRegistrySettings $legacy|Where-Object Name -eq HiberbootEnabled).Count -eq 0) 'Ancien profil ne doit pas pretendre demander le nouveau bloc QoL'
}finally{
    $resolved=[IO.Path]::GetFullPath($temporary);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture hors TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count controles de parite Rufus ; aucun reglage Windows applique."
