# BASTOS adaptation of Rufus CreateUnattendXml (Windows User Experience).
# Upstream Copyright (C) 2022-2026 Pete Batard <pete@akeo.ie>.
# Adaptation Copyright (C) 2026 BASTOS contributors.
# SPDX-License-Identifier: GPL-3.0-or-later
# Complete corresponding source and upstream provenance are shipped with BASTOS.
Set-StrictMode -Version Latest


function Read-BastosRufusOptions {
    param([string]$Path)
    if(-not $Path){return $null}
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Options de reinstallation absentes.'}
    $options=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($options.Schema -ne 1){throw 'Version des options de reinstallation inconnue.'}
    $name=([string]$options.UserName).Trim()
    if($name.Length -lt 1 -or $name.Length -gt 20 -or $name -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]*$' -or $name.EndsWith('.') -or
        $name -match '^(?i:Administrator|Administrateur|Guest|Invite|Invité|DefaultAccount|defaultuser0|WDAGUtilityAccount|HelpAssistant|KRBTGT|Local|NONE|SYSTEM)$'){
        throw 'Nom de compte local invalide ou reserve (1 a 20 caracteres).'
    }
    $options.UserName=$name
    $computer=([string]$options.ComputerName).Trim().ToUpperInvariant()
    if($computer.Length -lt 1 -or $computer.Length -gt 15 -or $computer -notmatch '^[A-Z0-9][A-Z0-9-]*$' -or $computer -notmatch '[A-Z]' -or $computer.EndsWith('-')){
        throw 'Nom du PC invalide : 1 a 15 lettres, chiffres ou tirets, avec au moins une lettre.'
    }
    $options.ComputerName=$computer
    if(-not $options.PSObject.Properties['DisableWidgets']){$options|Add-Member -NotePropertyName DisableWidgets -NotePropertyValue $false}
    if(-not $options.PSObject.Properties['UseExactRufusExperience']){$options|Add-Member -NotePropertyName UseExactRufusExperience -NotePropertyValue $false}
    if(-not $options.PSObject.Properties['PreserveDrivers']){$options|Add-Member -NotePropertyName PreserveDrivers -NotePropertyValue $false}
    if($options.PreserveDrivers -isnot [bool]){throw 'Option booleenne invalide : PreserveDrivers'}
    if(-not $options.PSObject.Properties['UseCleanBastosInstallation']){$options|Add-Member -NotePropertyName UseCleanBastosInstallation -NotePropertyValue $false}
    if($options.UseCleanBastosInstallation -isnot [bool]){throw 'Option booleenne invalide : UseCleanBastosInstallation'}
    if($options.UseCleanBastosInstallation -and $options.UseExactRufusExperience){throw 'Choisissez le profil propre BASTOS ou le mode conforme Rufus.'}
    foreach($setting in @('UseExactRufusExperience','KeepOnlyRecoveryPartition','BypassHardwareChecks','DisableTelemetry','DisableConsumerContent','RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){
        if($options.$setting -isnot [bool]){throw "Option booleenne invalide : $setting"}
    }
    if($options.WindowsLocale -notmatch '^[a-z]{2}-[A-Z]{2}$' -or $options.KeyboardLayout -notmatch '^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$'){
        throw 'Langue ou disposition de clavier invalide.'
    }
    if(-not $options.PSObject.Properties['WindowsUILanguage']){$options|Add-Member -NotePropertyName WindowsUILanguage -NotePropertyValue ''}
    if(-not $options.PSObject.Properties['DiskSafetySnapshot']){$options|Add-Member -NotePropertyName DiskSafetySnapshot -NotePropertyValue ''}
    if($options.DiskSafetySnapshot -isnot [string]){throw 'Plan du disque illisible. Reouvrez les options de partitions.'}
    if($options.WindowsUILanguage -and $options.WindowsUILanguage -notmatch '^[a-z]{2,3}-[A-Za-z0-9-]+$'){throw 'Langue d interface Windows invalide.'}
    foreach($key in @('RecoveryPartitionGuid','WindowsDiskIdentity')){
        $value=[string]$options.$key
        $parsed=[guid]::Empty
        if($value -and -not [guid]::TryParse($value,[ref]$parsed)){throw "Identite GPT invalide : $key"}
    }
    return $options
}

function Set-BastosRufusAccountFlow {
    param([Parameter(Mandatory)][xml]$Document,$Options=$null,[Parameter(Mandatory)][string]$FirstLogonScriptPath,[string]$EditionId='')
    $exact=$null -ne $Options -and $Options.PSObject.Properties['UseExactRufusExperience'] -and $Options.UseExactRufusExperience
    $clean=$null -ne $Options -and $Options.PSObject.Properties['UseCleanBastosInstallation'] -and $Options.UseCleanBastosInstallation
    if($clean -and $exact){throw 'Profils propre BASTOS et Rufus incompatibles.'}
    if($clean){foreach($flag in @('DisableTelemetry','DisableConsumerContent','RemoveOneDrive','RemoveTeams','RemoveOutlook','DisableCopilot','DisableWidgets')){$Options.$flag=$true}}
    $uri='urn:schemas-microsoft-com:unattend'
    $wcm='http://schemas.microsoft.com/WMIConfig/2002/State'
    $ns=[Xml.XmlNamespaceManager]::new($Document.NameTable);$ns.AddNamespace('u',$uri)
    $shell=$Document.SelectSingleNode('//u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]',$ns)
    $account=$shell.SelectSingleNode('u:UserAccounts/u:LocalAccounts/u:LocalAccount',$ns)
    if(-not $account -and $Document.SelectSingleNode('//u:RunSynchronousCommand[u:Description="BASTOS local account before OOBE"]',$ns)){
        # Regeneration of our own document is safe; arbitrary missing accounts
        # in an input template still cause a generation error.
        $fragment=$Document.CreateDocumentFragment()
        $fragment.InnerXml='<UserAccounts xmlns="urn:schemas-microsoft-com:unattend"><LocalAccounts><LocalAccount><Name/><DisplayName/><Password><Value/><PlainText>true</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts>'
        [void]$shell.AppendChild($fragment.FirstChild)
        $account=$shell.SelectSingleNode('u:UserAccounts/u:LocalAccounts/u:LocalAccount',$ns)
    }
    if(-not $account){throw 'Compte local absent du profil Rufus.'}
    $user=if($Options){[string]$Options.UserName}else{'BastOS'}
    if($user.Length -lt 1 -or $user.Length -gt 20 -or $user -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]*$' -or $user.EndsWith('.') -or $user -match '^(?i:Administrator|Administrateur|Guest|Invite|Invité|DefaultAccount|defaultuser0|WDAGUtilityAccount|HelpAssistant|KRBTGT|Local|NONE|SYSTEM)$'){throw 'Nom de compte local invalide ou reserve.'}
    foreach($secretField in @('Password','TemporaryPassword','LocalPassword')){
        if($Options -and $Options.PSObject.Properties[$secretField] -and -not [string]::IsNullOrEmpty([string]$Options.$secretField)){throw 'Ce profil prend uniquement en charge un compte local sans mot de passe.'}
    }
    $autoLogonEnabled=$true
    if($Options -and $Options.PSObject.Properties['AutoLogonEnabled']){
        if($Options.AutoLogonEnabled -isnot [bool]){throw 'AutoLogonEnabled doit etre booleen.'}
        $autoLogonEnabled=$Options.AutoLogonEnabled
    }
    $account.SelectSingleNode('u:Name',$ns).InnerText=$user
    $account.SelectSingleNode('u:DisplayName',$ns).InnerText=$user
    $account.SelectSingleNode('u:Password/u:Value',$ns).InnerText=''
    $account.SelectSingleNode('u:Password/u:PlainText',$ns).InnerText='true'
    $owner=$shell.SelectSingleNode('u:RegisteredOwner',$ns);if($owner){$owner.InnerText=$user}
    if($clean){
        $chat=$shell.SelectSingleNode('u:ConfigureChatAutoInstall',$ns)
        if(-not $chat){$chat=$Document.CreateElement('ConfigureChatAutoInstall',$uri);[void]$shell.AppendChild($chat)}
        $chat.InnerText='false'
    }
    if($Options){
        $Document.SelectSingleNode('//u:settings[@pass="specialize"]//u:ComputerName',$ns).InnerText=$Options.ComputerName
        foreach($setting in @('SystemLocale','UserLocale')){
            foreach($node in $Document.SelectNodes("//u:$setting",$ns)){$node.InnerText=$Options.WindowsLocale}
        }
        $uiLanguage=if($Options.PSObject.Properties['WindowsUILanguage'] -and $Options.WindowsUILanguage){[string]$Options.WindowsUILanguage}else{[string]$Options.WindowsLocale}
        foreach($node in $Document.SelectNodes('//u:UILanguage',$ns)){$node.InnerText=$uiLanguage}
        # Keep the physical layout, attach it to the selected UI language instead of
        # introducing English as the preferred application language for a US keyboard.
        $languageId=[Globalization.CultureInfo]::GetCultureInfo($uiLanguage).KeyboardLayoutId
        if($languageId -le 0 -or $languageId -eq 0x1000){throw 'Association langue/clavier non prise en charge. Choisis une langue regionale explicite.'}
        $effectiveInput=('{0:X4}' -f $languageId)+':'+($Options.KeyboardLayout -split ':')[1]
        foreach($node in $Document.SelectNodes('//u:InputLocale',$ns)){$node.InnerText=$effectiveInput}
    }
    foreach($node in @($shell.SelectNodes('u:AutoLogon | u:FirstLogonCommands',$ns))){[void]$shell.RemoveChild($node)}
    $computerName=$Document.SelectSingleNode('//u:settings[@pass="specialize"]//u:ComputerName',$ns).InnerText
    if($computerName.Length -lt 1 -or $computerName.Length -gt 15 -or $computerName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$' -or $computerName -notmatch '[A-Za-z]' -or $computerName.EndsWith('-')) {throw 'Nom du PC invalide pour la premiere connexion.'}
    $auto=$Document.CreateElement('AutoLogon',$uri)
    foreach($pair in @(@('Domain',$computerName),@('Enabled','true'),@('LogonCount','1'),@('Username',$user))){
        $node=$Document.CreateElement($pair[0],$uri);$node.InnerText=$pair[1];[void]$auto.AppendChild($node)
    }
    $password=$Document.CreateElement('Password',$uri)
    $value=$Document.CreateElement('Value',$uri)
    $plain=$Document.CreateElement('PlainText',$uri);$plain.InnerText='true'
    [void]$password.AppendChild($value);[void]$password.AppendChild($plain)
    [void]$auto.PrependChild($password)
    [void]$shell.InsertBefore($auto,$shell.SelectSingleNode('u:UserAccounts',$ns))
    # The local account uses an explicitly empty password in the answer file.
    # BASTOS keeps it passwordless on subsequent starts.
    $userLiteral="'"+$user.Replace("'","''")+"'"
    $commands=[Collections.Generic.List[string]]::new()
    $commands.Add("`$ErrorActionPreference='Stop'")
    $commands.Add("trap { try { & (Join-Path `$env:ProgramData 'BASTOS-ISO\Test-BASTOS-InstalledWindows.ps1') } catch { Write-Warning ('Bilan Windows : '+`$_.Exception.Message) }; exit 1 }")
    $commands.Add("`$logRoot=Join-Path `$env:ProgramData 'BASTOS-ISO\Logs'; New-Item -ItemType Directory -Path `$logRoot -Force|Out-Null; Start-Transcript -Path (Join-Path `$logRoot 'Rufus-FirstLogon.log') -Append -ErrorAction Stop|Out-Null")
    $commands.Add("Remove-Item -LiteralPath (Join-Path `$logRoot 'Rufus-FirstLogon.ok') -Force -ErrorAction SilentlyContinue")
    # Account creation and authentication are completed in specialize, before
    # OOBE/AutoLogon. No first-logon action is allowed to change a password.
    $commands.Add("`$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'")
    $commands.Add("Set-ItemProperty -LiteralPath `$key -Name AutoAdminLogon -Value '0'")
    $commands.Add("Remove-ItemProperty -LiteralPath `$key -Name AutoLogonCount,DefaultPassword,DefaultDomainName,DefaultUserName,ForceAutoLogon -Force -ErrorAction SilentlyContinue")
    if($Options){
        $protect=$shell.SelectSingleNode('u:OOBE/u:ProtectYourPC',$ns)
        if($protect){$protect.InnerText=if($Options.DisableTelemetry){'3'}else{'1'}}
        # Rufus applies BypassNRO in specialize and the optional hardware checks
        # in windowsPE. Both are scoped to the installation, never the host OS.
        foreach($pass in @('specialize','windowsPE')){
            $settings=$Document.SelectSingleNode("//u:settings[@pass='$pass']",$ns)
            $componentName=if($pass -eq 'specialize'){'Microsoft-Windows-Deployment'}else{'Microsoft-Windows-Setup'}
            $component=$settings.SelectSingleNode("u:component[@name='$componentName']",$ns)
            if(-not $component){
                $component=$Document.CreateElement('component',$uri)
                foreach($pair in @(@('name',$componentName),@('processorArchitecture','amd64'),@('publicKeyToken','31bf3856ad364e35'),@('language','neutral'),@('versionScope','nonSxS'))){$component.SetAttribute($pair[0],$pair[1])}
                [void]$settings.AppendChild($component)
            }
            foreach($old in @($component.SelectNodes('u:RunSynchronous/u:RunSynchronousCommand[u:Description="BASTOS Rufus"]',$ns))){[void]$old.ParentNode.RemoveChild($old)}
            $installCommands=@()
            if($pass -eq 'specialize'){$installCommands=@('reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f','reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f');if($Options.DisableConsumerContent){$qolModule=Import-Module (Join-Path $PSScriptRoot 'Bastos.InstallationOptions.psm1') -PassThru -ErrorAction Stop;$installCommands+=@(& $qolModule {Get-BastosRufusQolSpecializeCommands})}}
            elseif($Options.BypassHardwareChecks){$installCommands=@('BypassTPMCheck','BypassSecureBootCheck','BypassRAMCheck')|ForEach-Object {'reg add HKLM\SYSTEM\Setup\LabConfig /v '+$_+' /t REG_DWORD /d 1 /f'}}
            if($installCommands.Count -gt 0){
                $run=$component.SelectSingleNode('u:RunSynchronous',$ns)
                if(-not $run){$run=$Document.CreateElement('RunSynchronous',$uri);[void]$component.AppendChild($run)}
                $order=@($run.ChildNodes|Where-Object NodeType -eq Element).Count+1
                foreach($installCommand in $installCommands){
                    $entry=$Document.CreateElement('RunSynchronousCommand',$uri)
                    $action=$Document.CreateAttribute('wcm','action',$wcm);$action.Value='add';[void]$entry.Attributes.Append($action)
                    foreach($pair in @(@('Order',[string]$order),@('Path',$installCommand),@('Description','BASTOS Rufus'))){$node=$Document.CreateElement($pair[0],$uri);$node.InnerText=$pair[1];[void]$entry.AppendChild($node)}
                    [void]$run.AppendChild($entry);$order++
                }
            }
        }
    }
    $commands.Add("Write-Output 'BASTOS : creation du raccourci Bureau'")
    $commands.Add("try { & (Join-Path `$env:ProgramData 'BASTOS-ISO\New-BASTOS-DesktopShortcut.ps1') } catch { Write-Warning ('Raccourci BASTOS : '+`$_.Exception.Message); throw `$_ }")
    $commands.Add("Import-Module (Join-Path `$env:ProgramData 'BASTOS-ISO\Bastos.InstallationOptions.psm1') -Force -ErrorAction Stop")
    $commands.Add("Invoke-BastosInstallationOptions -ProfilePath (Join-Path `$env:ProgramData 'BASTOS-ISO\Installation-Expected.json') -ResultPath (Join-Path `$logRoot 'Installation-Options.json') | Out-Null")
    $commands.Add(@'
$logRoot=Join-Path $env:ProgramData 'BASTOS-ISO\Logs'
New-Item -ItemType Directory -Path $logRoot -Force|Out-Null
try{
  $recovery=@(Get-Volume -ErrorAction Stop|Where-Object {$_.FileSystemLabel -eq 'BASTOS_RECOVERY' -and $_.DriveLetter})
  if($recovery.Count -eq 1){
    $recoveryRoot=([string]$recovery[0].DriveLetter)+':\'
    $attempt=(Get-Content -LiteralPath (Join-Path $recoveryRoot 'BASTOS-ACTIVE-ATTEMPT.txt') -Raw).Trim()
    if($attempt -match '^Attempt-[0-9a-f]{32}$'){
      $attemptRoot=Join-Path (Join-Path $recoveryRoot 'BASTOS-Diagnostics\Attempts') $attempt
      New-Item -ItemType Directory -Path $attemptRoot -Force|Out-Null
      $state=[ordered]@{Schema=1;AttemptId=$attempt;Stage='RufusFirstLogonCompleted';Success=$true;UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
      $json=$state|ConvertTo-Json
      [IO.File]::WriteAllText((Join-Path $attemptRoot 'Rufus-FirstLogon-State.json'),$json)
      [IO.File]::WriteAllText((Join-Path $recoveryRoot 'BASTOS-LAST-ATTEMPT.json'),$json)
      [IO.File]::WriteAllText((Join-Path $recoveryRoot 'BASTOS-LAST-ATTEMPT.txt'),('AttemptId='+$attempt+"`r`nStage=RufusFirstLogonCompleted`r`nResult=SUCCESS"))
    }
  }
}catch{Write-Warning $_.Exception.Message;throw $_}
$profilePath=Join-Path $env:ProgramData 'BASTOS-ISO\Installation-Expected.json'
$profile=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json
$receipt=[ordered]@{ProfileId=$profile.ProfileId;ProfileSha256=(Get-FileHash -LiteralPath $profilePath).Hash;MachineGuid=[Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography','MachineGuid',$null);CompletedUtc=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $logRoot 'Rufus-FirstLogon.ok'),($receipt|ConvertTo-Json))
'@)
    $commands.Add("try { & (Join-Path `$env:ProgramData 'BASTOS-ISO\Test-BASTOS-InstalledWindows.ps1') } catch { Write-Warning ('Bilan Windows : '+`$_.Exception.Message) }")
    $commands.Add("try { & (Join-Path `$env:ProgramData 'BASTOS-ISO\Finalize-BASTOS-TemporaryRecovery.ps1') -Apply | Out-Null } catch { Write-Warning ('Recuperation de D: reportee : '+`$_.Exception.Message) }")
    $commands.Add("Stop-Transcript -ErrorAction SilentlyContinue|Out-Null; exit 0")
    $scriptDirectory=Split-Path -Parent $FirstLogonScriptPath
    New-Item -ItemType Directory -Path $scriptDirectory -Force|Out-Null
    if(-not $EditionId -and $Options -and $Options.PSObject.Properties['WindowsEditionId']){$EditionId=[string]$Options.WindowsEditionId}
    $expected=[ordered]@{
        Schema=2;ProfileId=[guid]::NewGuid().ToString('D');CreatedUtc=[DateTime]::UtcNow.ToString('o')
        EditionId=$EditionId
        UILanguage=$Document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UILanguage',$ns).InnerText
        Locale=$Document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UserLocale',$ns).InnerText
        KeyboardLayout=$Document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:InputLocale',$ns).InnerText
        ComputerName=$Document.SelectSingleNode('//u:settings[@pass="specialize"]//u:ComputerName',$ns).InnerText
        UserName=$user
        AccountProvisioning='SpecializePasswordlessV1'
        PasswordMode='Empty'
        AutoLogonEnabled=$autoLogonEnabled
        AccountWorkerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Initialize-BASTOS-LocalAccount.ps1') -Algorithm SHA256).Hash
        ApplicationPlacement='Windows'
        RecoveryPartitionGuid=if($Options){[string]$Options.RecoveryPartitionGuid}else{''}
        WindowsDiskIdentity=if($Options){[string]$Options.WindowsDiskIdentity}else{''}
        Options=[ordered]@{
            CleanBastosVersion=if($clean){'1'}else{''}
            RufusExperienceVersion=if($exact){'4.15'}else{''}
            RufusQolVersion=if($Options -and $Options.DisableConsumerContent){'4.15'}else{''}
            DisableTelemetry=($null -ne $Options -and $Options.DisableTelemetry)
            DisableConsumerContent=($null -ne $Options -and $Options.DisableConsumerContent)
            RemoveOneDrive=(-not $exact -and $null -ne $Options -and $Options.RemoveOneDrive)
            RemoveTeams=(-not $exact -and $null -ne $Options -and $Options.RemoveTeams)
            RemoveOutlook=(-not $exact -and $null -ne $Options -and $Options.RemoveOutlook)
            DisableCopilot=(-not $exact -and $null -ne $Options -and $Options.DisableCopilot)
            DisableWidgets=(-not $exact -and $null -ne $Options -and $Options.PSObject.Properties['DisableWidgets'] -and $Options.DisableWidgets)
        }
    }
    if($exact){[IO.File]::WriteAllText((Join-Path $scriptDirectory 'Rufus-Oobe.xml'),$shell.SelectSingleNode('u:OOBE',$ns).OuterXml,[Text.UTF8Encoding]::new($false))}
    [IO.File]::WriteAllText((Join-Path $scriptDirectory 'Installation-Expected.json'),($expected|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Initialize-BASTOS-LocalAccount.ps1') -Destination (Join-Path $scriptDirectory 'Initialize-BASTOS-LocalAccount.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-BASTOS-InstalledWindows.ps1') -Destination (Join-Path $scriptDirectory 'Test-BASTOS-InstalledWindows.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Bastos.InstallationOptions.psm1') -Destination (Join-Path $scriptDirectory 'Bastos.InstallationOptions.psm1') -Force
    [IO.File]::WriteAllText($FirstLogonScriptPath,($commands -join "`r`n"),[Text.UTF8Encoding]::new($true))
    # Install the collector beside the first-logon script and start it before OOBE.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Watch-BASTOS-Setup.ps1') -Destination (Join-Path $scriptDirectory 'Watch-BASTOS-Setup.ps1') -Force
    $identity=[ordered]@{RecoveryPartitionGuid=if($Options){[string]$Options.RecoveryPartitionGuid}else{''};WindowsDiskIdentity=if($Options){[string]$Options.WindowsDiskIdentity}else{''}}
    [IO.File]::WriteAllText((Join-Path $scriptDirectory 'SetupDiagnostics-Identity.json'),($identity|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $specialize=$Document.SelectSingleNode('//u:settings[@pass="specialize"]',$ns)
    $deployment=$specialize.SelectSingleNode('u:component[@name="Microsoft-Windows-Deployment"]',$ns)
    if(-not $deployment){
        $deployment=$Document.CreateElement('component',$uri)
        foreach($pair in @(@('name','Microsoft-Windows-Deployment'),@('processorArchitecture','amd64'),@('publicKeyToken','31bf3856ad364e35'),@('language','neutral'),@('versionScope','nonSxS'))){$deployment.SetAttribute($pair[0],$pair[1])}
        [void]$specialize.AppendChild($deployment)
    }
    $run=$deployment.SelectSingleNode('u:RunSynchronous',$ns)
    if(-not $run){$run=$Document.CreateElement('RunSynchronous',$uri);[void]$deployment.AppendChild($run)}
    foreach($old in @($run.SelectNodes('u:RunSynchronousCommand[u:Description="BASTOS automatic diagnostics"]',$ns))){[void]$run.RemoveChild($old)}
    $path='powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\Watch-BASTOS-Setup.ps1" -Start'
    if($path.Length -gt 259){throw 'Commande specialize trop longue.'}
    $entry=$Document.CreateElement('RunSynchronousCommand',$uri)
    $action=$Document.CreateAttribute('wcm','action',$wcm);$action.Value='add';[void]$entry.Attributes.Append($action)
    foreach($pair in @(@('Order','1'),@('Path',$path),@('Description','BASTOS automatic diagnostics'))){$node=$Document.CreateElement($pair[0],$uri);$node.InnerText=$pair[1];[void]$entry.AppendChild($node)}
    [void]$run.PrependChild($entry)
    # applyOnce consumes the pin list at first sign-in. Create and verify the
    # common shortcut in specialize, before Explorer can read that list.
    if($clean){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-BASTOS-DesktopShortcut.ps1') -Destination (Join-Path $scriptDirectory 'New-BASTOS-DesktopShortcut.ps1') -Force
        foreach($old in @($run.SelectNodes('u:RunSynchronousCommand[u:Description="BASTOS initial Start shortcut"]',$ns))){[void]$run.RemoveChild($old)}
        $pinCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\New-BASTOS-DesktopShortcut.ps1" -CommonStartMenuOnly'
        if($pinCommand.Length -gt 259){throw 'Commande specialize du raccourci trop longue.'}
        $pinEntry=$Document.CreateElement('RunSynchronousCommand',$uri)
        $pinAction=$Document.CreateAttribute('wcm','action',$wcm);$pinAction.Value='add';[void]$pinEntry.Attributes.Append($pinAction)
        foreach($pair in @(@('Order','1'),@('Path',$pinCommand),@('Description','BASTOS initial Start shortcut'))){$node=$Document.CreateElement($pair[0],$uri);$node.InnerText=$pair[1];[void]$pinEntry.AppendChild($node)}
        [void]$run.AppendChild($pinEntry)
    }
    # A single writer owns account creation. oobeSystem must not recreate or
    # overwrite the account which was already created and verified in specialize.
    $accounts=$shell.SelectSingleNode('u:UserAccounts/u:LocalAccounts',$ns)
    [void]$accounts.ParentNode.RemoveChild($accounts)
    $userAccounts=$shell.SelectSingleNode('u:UserAccounts',$ns)
    if(-not $userAccounts.HasChildNodes){[void]$shell.RemoveChild($userAccounts)}
    foreach($old in @($run.SelectNodes('u:RunSynchronousCommand[u:Description="BASTOS local account before OOBE"]',$ns))){[void]$run.RemoveChild($old)}
    $accountCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\Initialize-BASTOS-LocalAccount.ps1"'
    if($accountCommand.Length -gt 259){throw 'Commande de creation du compte trop longue.'}
    $accountEntry=$Document.CreateElement('RunSynchronousCommand',$uri)
    $accountAction=$Document.CreateAttribute('wcm','action',$wcm);$accountAction.Value='add';[void]$accountEntry.Attributes.Append($accountAction)
    foreach($pair in @(@('Order','1'),@('Path',$accountCommand),@('Description','BASTOS local account before OOBE'),@('WillReboot','Never'))){$node=$Document.CreateElement($pair[0],$uri);$node.InnerText=$pair[1];[void]$accountEntry.AppendChild($node)}
    [void]$run.PrependChild($accountEntry)
    $order=1;foreach($command in $run.SelectNodes('u:RunSynchronousCommand',$ns)){$command.SelectSingleNode('u:Order',$ns).InnerText=[string]$order;$order++}
    # Windows caps FirstLogonCommands/CommandLine at 1024 characters.
    $commandLine='powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\Rufus-FirstLogon.ps1"'
    if($commandLine.Length -gt 1024){throw 'Commande de premiere connexion trop longue.'}
    $fragment=$Document.CreateDocumentFragment()
    $fragment.InnerXml=('<FirstLogonCommands xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><SynchronousCommand wcm:action="add"><Order>1</Order><Description>Configurer le compte local et les options Windows</Description><CommandLine>powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;%ProgramData%\BASTOS-ISO\Rufus-FirstLogon.ps1&quot;</CommandLine></SynchronousCommand></FirstLogonCommands>')
    [void]$shell.AppendChild($fragment.FirstChild)
    $configured=$Document.SelectSingleNode('//u:AutoLogon',$ns)
    if(-not $configured -or $configured.SelectSingleNode('u:Username',$ns).InnerText -cne $user -or
       $configured.SelectSingleNode('u:Domain',$ns).InnerText -cne $computerName -or
       $configured.SelectSingleNode('u:Password/u:Value',$ns).InnerText -ne '' -or
       $configured.SelectSingleNode('u:LogonCount',$ns).InnerText -ne '1'){
        throw 'La premiere connexion automatique locale n est pas correctement configuree.'
    }
    if(-not $autoLogonEnabled){[void]$shell.RemoveChild($configured)}
}

function Test-BastosRufusAccountFlow {
    param([Parameter(Mandatory)][xml]$Document,[Parameter(Mandatory)]$Profile)
    $ns=[Xml.XmlNamespaceManager]::new($Document.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
    $commands=@($Document.SelectNodes('//u:settings[@pass="specialize"]//u:RunSynchronousCommand[u:Description="BASTOS local account before OOBE"]',$ns))
    $expectedCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ProgramData%\BASTOS-ISO\Initialize-BASTOS-LocalAccount.ps1"'
    if($Profile.AccountProvisioning -ne 'SpecializePasswordlessV1' -or $Profile.PasswordMode -ne 'Empty' -or
       $commands.Count -ne 1 -or $commands[0].SelectSingleNode('u:Path',$ns).InnerText -cne $expectedCommand -or
       $commands[0].SelectSingleNode('u:Order',$ns).InnerText -ne '1' -or
       $Document.SelectSingleNode('//u:LocalAccounts',$ns)) {throw 'Creation unique du compte avant OOBE non garantie.'}
    $computer=$Document.SelectSingleNode('//u:settings[@pass="specialize"]//u:ComputerName',$ns)
    if(-not $computer -or $computer.InnerText -cne $Profile.ComputerName){throw 'Nom de PC divergent du profil.'}
    $auto=$Document.SelectSingleNode('//u:AutoLogon',$ns)
    if(@($Document.SelectNodes('//u:AutoLogon',$ns)).Count -ne $(if($Profile.AutoLogonEnabled){1}else{0})){throw 'Nombre de configurations AutoLogon incorrect.'}
    if($Profile.AutoLogonEnabled){
        if(-not $auto -or $auto.SelectSingleNode('u:Username',$ns).InnerText -cne $Profile.UserName -or
           $auto.SelectSingleNode('u:Domain',$ns).InnerText -cne $Profile.ComputerName -or
           $auto.SelectSingleNode('u:Password/u:Value',$ns).InnerText -ne '' -or
           $auto.SelectSingleNode('u:Password/u:PlainText',$ns).InnerText -ne 'true' -or
           $auto.SelectSingleNode('u:Enabled',$ns).InnerText -ne 'true' -or
           $auto.SelectSingleNode('u:LogonCount',$ns).InnerText -ne '1'){throw 'AutoLogon divergent du compte local.'}
    }elseif($auto){throw 'AutoLogon present malgre sa desactivation.'}
    return $true
}
Export-ModuleMember -Function Read-BastosRufusOptions,Set-BastosRufusAccountFlow,Test-BastosRufusAccountFlow
