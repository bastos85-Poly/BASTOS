[CmdletBinding()]
param([string]$ApplicationRoot=$PSScriptRoot,[string]$RecoveryRoot='D:\')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert-Condition { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Test-LocalOnlyAnswer {
    param([string]$Path,[switch]$AllowTemplateMarkers)
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Fichier absent : $Path"
    [xml]$answer=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $ns=[Xml.XmlNamespaceManager]::new($answer.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
    if($answer.SelectSingleNode('//u:RunSynchronousCommand[u:Description="BASTOS local account before OOBE"]',$ns)){
        Import-Module (Join-Path $ApplicationRoot 'Bastos.Rufus.psm1') -Force -ErrorAction Stop
        $payload=Join-Path (Split-Path -Parent $Path) 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
        $profile=Get-Content -LiteralPath (Join-Path $payload 'Installation-Expected.json') -Raw|ConvertFrom-Json
        Assert-Condition (Test-BastosRufusAccountFlow -Document $answer -Profile $profile) 'Profil specialize invalide.'
        Assert-Condition ((Get-FileHash -LiteralPath (Join-Path $payload 'Initialize-BASTOS-LocalAccount.ps1')).Hash -eq $profile.AccountWorkerSha256) 'Worker de compte divergent.'
        return
    }
    $expected=if($AllowTemplateMarkers){'__BASTOS_USERNAME__'}else{'BastOS'}
    $account=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccounts/u:LocalAccount',$ns)
    $password=if($account){$account.SelectSingleNode('u:Password/u:Value',$ns)}else{$null}
    $name=if($account){$account.SelectSingleNode('u:Name',$ns)}else{$null}
    $displayName=if($account){$account.SelectSingleNode('u:DisplayName',$ns)}else{$null}
    $group=if($account){$account.SelectSingleNode('u:Group',$ns)}else{$null}
    $auto=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon',$ns)
    $autoPassword=if($auto){$auto.SelectSingleNode('u:Password/u:Value',$ns)}else{$null}
    $autoDomain=if($auto){$auto.SelectSingleNode('u:Domain',$ns)}else{$null}
    $autoName=if($auto){$auto.SelectSingleNode('u:Username',$ns)}else{$null}
    $computerName=$answer.SelectSingleNode('//u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:ComputerName',$ns)
    Assert-Condition ($null -ne $account) "LocalAccounts absent : $Path"
    Assert-Condition ($null -ne $password -and $password.InnerText -eq '') "Mot de passe local non vide : $Path"
    Assert-Condition ($null -ne $name -and $name.InnerText -ceq $expected) "Nom du compte local incorrect : $Path"
    Assert-Condition ($null -ne $displayName -and $displayName.InnerText -ceq 'BastOS') "Nom affiche BastOS incorrect : $Path"
    Assert-Condition ($null -ne $group -and $group.InnerText -eq 'Administrators') "Compte local non administrateur : $Path"
    $expectedDomain=if($AllowTemplateMarkers){'__BASTOS_COMPUTER_NAME__'}else{if($computerName){$computerName.InnerText}else{''}}
    Assert-Condition ($null -ne $autoDomain -and $autoDomain.InnerText -ceq $expectedDomain -and $autoDomain.InnerText -ne '.') "Domaine AutoLogon local incorrect : $Path"
    Assert-Condition ($null -ne $autoPassword -and $autoPassword.InnerText -eq '') "Mot de passe AutoLogon non vide : $Path"
    Assert-Condition ($null -ne $autoName -and $autoName.InnerText -ceq $expected) "AutoLogon ne cible pas le compte local : $Path"
    Assert-Condition (@($answer.SelectNodes('//u:AdministratorPassword',$ns)).Count -eq 0) "AdministratorPassword encore present : $Path"
    Assert-Condition (@($answer.SelectNodes('//u:settings[@pass="specialize"]//u:RunSynchronousCommand',$ns)).Count -eq 0) "Commande preconnexion fragile presente : $Path"
    Assert-Condition ($answer.OuterXml -notmatch '(?i)SkipMachineOOBE|SkipUserOOBE') "Contournement OOBE deconseille encore present : $Path"
    Assert-Condition ($answer.OuterXml -notmatch 'BASTOS-Setup-Temporary') "Ancien mot de passe temporaire present : $Path"
    if(-not $AllowTemplateMarkers){Assert-Condition ($answer.OuterXml -notmatch '__BASTOS_[A-Z_]+__') "Marqueur BASTOS non resolu : $Path"}
}
$fallback=Join-Path $ApplicationRoot 'BASTOS-LocalOnly-OOBE.cmd'
$launcher=Join-Path $ApplicationRoot 'BASTOS-Start.cmd'
Assert-Condition (Test-Path -LiteralPath $fallback -PathType Leaf) 'Filet OOBE localonly absent.'
Assert-Condition ((Get-Content -LiteralPath $fallback -Raw) -match 'start\s+""\s+ms-cxh:localonly') 'Commande start ms-cxh:localonly incorrecte.'
$launcherBytes=[IO.File]::ReadAllBytes($launcher)
$launcherAscii=[Text.Encoding]::ASCII.GetString($launcherBytes)
Assert-Condition ($launcherBytes.Count -gt 0 -and $launcherBytes.Where({$_ -gt 127},'First').Count -eq 0) 'Le lanceur WinPE doit etre un batch ASCII non vide.'
Assert-Condition ($launcherAscii -match '\r\n' -and $launcherAscii -notmatch '(?<!\r)\n' -and $launcherAscii -notmatch '\r(?!\n)') 'Le lanceur WinPE doit utiliser exclusivement des fins de ligne CRLF.'
$launcherText=Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
Assert-Condition ($launcherText -match 'Precontrole compte local Bastos') 'Le lanceur WinPE ne valide pas Bastos.'
Assert-Condition ($launcherText -match 'find /i "<LocalAccounts"') 'Le controle WinPE LocalAccounts ne tolere pas les attributs XML.'
Assert-Condition ($launcherText -notmatch 'find /i "<LocalAccounts>"') 'Le controle WinPE LocalAccounts exact et fragile est encore present.'
Assert-Condition ($launcherText -notmatch '(?im)^\s*fc(?:\.exe)?\s+/b') 'Le lanceur depend encore de FC absent de WinPE.'
Assert-Condition ($launcherText -match 'BASTOS_EXPECTED_COMPUTER_NAME') 'Le lanceur ne lit pas le nom stable de la reponse specialize.'
Assert-Condition ($launcherText -match 'DefaultDomainName.*BASTOS_EXPECTED_COMPUTER_NAME') 'Le lanceur ne prepare pas Winlogon avec le nom stable specialize.'
Assert-Condition ($launcherText -notmatch 'DefaultDomainName.*BASTOS_OFFLINE_COMPUTER_NAME') 'Le lanceur reutilise encore le nom provisoire avant specialize.'
Assert-Condition ($launcherText -notmatch 'ChildCompletion.+/v setup\.exe.+/d 3') 'Le lanceur force encore artificiellement ChildCompletion.'
Assert-Condition ($launcherText -match 'BASTOS_ACCOUNT_SOURCE_SIZE') 'Le marqueur local n est pas valide sans dependance externe.'
Assert-Condition ($launcherText -match 'ms-cxh:localonly') 'Le lanceur ne connait pas le filet localonly.'
Assert-Condition ($launcherText -match 'BASTOS_PRECHECKS_COMPLETED' -and $launcherText -match 'BASTOS_DISK_PREPARED' -and $launcherText -match 'BASTOS_SETUP_LAUNCHED') 'Les gardes anti-saut de flux WinPE sont absentes.'
$preLogonText=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'Initialize-BASTOS-PreLogon.ps1') -Raw -Encoding UTF8
Assert-Condition ($preLogonText -match "standardName='BastOS'") 'Le filet preconnexion ne cible pas strictement BastOS.'
Assert-Condition ($preLogonText -match 'Disable-BuiltInAdministrator') 'Le filet preconnexion ne desactive pas SID-500.'
Assert-Condition ($preLogonText -notmatch 'Rename-BuiltInAdministrator') 'L ancienne strategie de renommage SID-500 subsiste.'
Assert-Condition ($preLogonText -match 'DefaultUserName.+\$accountName') 'Le filet preconnexion ne configure pas Winlogon avec BastOS.'
$setupCompleteText=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'BASTOS-SetupComplete.cmd') -Raw -Encoding UTF8
Assert-Condition ($setupCompleteText -match 'Initialize-BASTOS-PreLogon\.ps1') 'SetupComplete ne lance pas le filet preconnexion.'
Assert-Condition ($setupCompleteText -match 'BASTOS_PRELOGON_EXIT') 'SetupComplete ne controle pas le resultat preconnexion.'
$buildText=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'Build-BASTOS-ISO.ps1') -Raw -Encoding UTF8
Assert-Condition ($buildText -match 'if \(\$Name -cne ''BastOS''\)') 'Le constructeur ISO refuse encore le compte local BastOS.'
Assert-Condition ($buildText -notmatch 'if \(\$Name -cne ''Administrator''\)') 'L ancien blocage Administrator subsiste dans le constructeur ISO.'
Assert-Condition ($buildText -match 'Ne jamais figer une reponse OOBE dans install\.wim') 'Le build peut encore figer un ancien compte dans install.wim.'
Assert-Condition ($buildText -match 'Remove-Item -LiteralPath \$cachedUnattendPath,\$embeddedUnattendPath') 'Le nettoyage Panther de install.wim est absent.'
$initializeText=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'Initialize-BASTOS-Recovery.ps1') -Raw -Encoding UTF8
Assert-Condition ($initializeText -match 'function Remove-BastosEmbeddedPantherAnswers') 'Le reprovisionnement ne nettoie pas install.wim.'
Assert-Condition ($initializeText -match 'InstallWimSanitized=\$true') 'L état média ne certifie pas le nettoyage de install.wim.'
Assert-Condition ($initializeText -match 'InstallWimSha256=\$preparedInstallHash') 'L empreinte de install.wim nettoyé n est pas conservée.'
Test-LocalOnlyAnswer -Path (Join-Path $ApplicationRoot 'autounattend.xml') -AllowTemplateMarkers
$answers=@(Get-ChildItem -LiteralPath $RecoveryRoot -Filter 'BASTOS-Recovery-Unattend*.xml' -File -ErrorAction SilentlyContinue)
Assert-Condition ($answers.Count -ge 1) "Aucun fichier de reponses Recovery dans $RecoveryRoot"
foreach($answer in $answers){Test-LocalOnlyAnswer -Path $answer.FullName}
$mediaStatePath=Join-Path $RecoveryRoot 'BASTOS-MEDIA-STATE.json'
$readyPath=Join-Path $RecoveryRoot 'BASTOS-LOCAL-OOBE-READY.txt'
Assert-Condition (Test-Path -LiteralPath $mediaStatePath -PathType Leaf) 'BASTOS-MEDIA-STATE.json absent.'
Assert-Condition (Test-Path -LiteralPath $readyPath -PathType Leaf) 'BASTOS-LOCAL-OOBE-READY.txt absent.'
$mediaState=Get-Content -LiteralPath $mediaStatePath -Raw -Encoding UTF8|ConvertFrom-Json
$ready=@{}
foreach($line in @(Get-Content -LiteralPath $readyPath -Encoding UTF8)){
    if($line -match '^([^=]+)=(.*)$'){$ready[$matches[1]]=$matches[2]}
}
Assert-Condition ([bool]$mediaState.InstallWimSanitized) 'install.wim n est pas certifie assaini.'
Assert-Condition ([int]$mediaState.AccountFlowVersion -eq 16) 'Le media ne certifie pas le flux compte v16.'
Assert-Condition ([string]$mediaState.AccountStrategy -eq 'BastOS-Local-NonSID500') 'La strategie de compte du media est perimee.'
Assert-Condition ([string]$mediaState.ComputerNameStrategy -eq 'SpecializeThenSetupCompleteVerification') 'La strategie ComputerName du media est perimee.'
Assert-Condition ([string]$mediaState.BootWimCompatibilityMode -eq 'EmbeddedLauncherV16-SpecializeAware-BastOS') 'Le boot.wim n est pas certifie v16.'
Assert-Condition ([string]$mediaState.EmbeddedRecoveryLauncherSha256 -eq [string]$mediaState.RecoveryLauncherSha256) 'Le lanceur embarque diverge du lanceur source.'
Assert-Condition ((Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash -eq [string]$mediaState.RecoveryLauncherSha256) 'Le lanceur source diverge de BASTOS-MEDIA-STATE.'
Assert-Condition ((Get-FileHash -LiteralPath (Join-Path $RecoveryRoot 'sources\boot.wim') -Algorithm SHA256).Hash -eq [string]$mediaState.BootWimSha256) 'boot.wim diverge de BASTOS-MEDIA-STATE.'
Assert-Condition ((Get-FileHash -LiteralPath (Join-Path $RecoveryRoot 'sources\install.wim') -Algorithm SHA256).Hash -eq [string]$mediaState.InstallWimSha256) 'install.wim diverge de BASTOS-MEDIA-STATE.'
Assert-Condition ($ready.BootWimSha256 -eq [string]$mediaState.BootWimSha256) 'Le marqueur READY contient une ancienne empreinte boot.wim.'
Assert-Condition ($ready.LauncherSha256 -eq [string]$mediaState.RecoveryLauncherSha256) 'Le marqueur READY contient une ancienne empreinte lanceur.'
Assert-Condition ($ready.InstallWimSha256 -eq [string]$mediaState.InstallWimSha256) 'Le marqueur READY contient une ancienne empreinte install.wim.'
[pscustomobject]@{Success=$true;AnswerFilesTested=1+$answers.Count;VerifiedUtc=[DateTime]::UtcNow.ToString('o')}
