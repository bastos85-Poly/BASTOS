[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OfficialIsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][ValidatePattern('^[a-z]{2}-[A-Z]{2}$')][string]$WindowsLocale,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$')][string]$KeyboardLayout,
    # L'interface native 7.99 encore installee peut transmettre l'ancien nom
    # Administrator. Accepter cette valeur a la frontiere evite un echec de
    # liaison de parametre ; la ligne ci-dessous normalise toujours vers BastOS.
    [ValidateSet('Administrator','BastOS')][string]$LocalUserName = 'BastOS',
    [ValidateSet('WindowsOnly','BastosAutonomous')][string]$PostInstallMode = 'WindowsOnly',
    [string]$OptionsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Rufus.psm1') -Force -ErrorAction Stop
$script:RufusOptions=Read-BastosRufusOptions -Path $OptionsPath
if($script:RufusOptions -and $PostInstallMode -ne 'WindowsOnly'){throw 'Le menu Rufus utilise le profil Windows officiel sans surcouche autonome.'}

if (-not (Test-Path -LiteralPath $OfficialIsoPath -PathType Leaf) -or
    [IO.Path]::GetExtension($OfficialIsoPath) -ine '.iso') {
    throw 'Une ISO Windows officielle valide est requise.'
}
$LocalUserName = 'BastOS'
$localDisplayName = 'BastOS'

$temporaryPassword = ''
$computerName = ([string]$env:COMPUTERNAME).Trim().ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($computerName) -or
    $computerName.Length -gt 15 -or
    $computerName -match '[^A-Z0-9-]' -or
    $computerName -notmatch '[A-Z]' -or
    $computerName -like 'MININT-*' -or
    $computerName -match '(?i)KernelOS|KernelPan|KRNLGame|KOS[ -]?Post') {
    $computerName = 'BASTOS-' + [guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()
}

$firstLogonCommand = @"
        <SynchronousCommand wcm:action="add"><Order>1</Order><Description>Terminer la connexion locale BASTOS</Description><CommandLine>cmd.exe /d /c reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoLogonCount /t REG_DWORD /d 0 /f</CommandLine></SynchronousCommand>
"@
if ($PostInstallMode -eq 'BastosAutonomous') {
    # Une tentative reelle 7.86 a prouve que Windows pouvait encore abandonner
    # avant le premier marqueur BASTOS lorsqu une commande etait presente dans
    # specialize. Ne rien executer dans cette passe critique : la phase machine
    # BASTOS est lancee par l orchestrateur de premier logon, apres OOBE.
    $firstLogonCommand = @"
        <SynchronousCommand wcm:action="add"><Order>1</Order><Description>Lancer la sequence utilisateur BASTOS en arriere-plan</Description><CommandLine>powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\BASTOS-ISO\Start-BASTOS-Autonomous-FirstLogon.ps1</CommandLine></SynchronousCommand>
"@
}

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$WindowsLocale</UILanguage></SetupUILanguage>
      <InputLocale>$KeyboardLayout</InputLocale>
      <SystemLocale>$WindowsLocale</SystemLocale>
      <UILanguage>$WindowsLocale</UILanguage>
      <UserLocale>$WindowsLocale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <DynamicUpdate><Enable>false</Enable><WillShowUI>Never</WillShowUI></DynamicUpdate>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>$localDisplayName</FullName>
        <Organization></Organization>
        <ProductKey><Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key><WillShowUI>Never</WillShowUI></ProductKey>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$computerName</ComputerName>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$KeyboardLayout</InputLocale>
      <SystemLocale>$WindowsLocale</SystemLocale>
      <UILanguage>$WindowsLocale</UILanguage>
      <UserLocale>$WindowsLocale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <RegisteredOwner>$localDisplayName</RegisteredOwner>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <AutoLogon><Password><Value></Value><PlainText>true</PlainText></Password><Domain>$computerName</Domain><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>$LocalUserName</Username></AutoLogon>
      <UserAccounts><LocalAccounts><LocalAccount wcm:action="add"><Password><Value></Value><PlainText>true</PlainText></Password><Description>Compte local BastOS sans mot de passe</Description><DisplayName>$localDisplayName</DisplayName><Group>Administrators</Group><Name>$LocalUserName</Name></LocalAccount></LocalAccounts></UserAccounts>
      <FirstLogonCommands>
$firstLogonCommand
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@

$document = [xml]$xml
$namespace = [Xml.XmlNamespaceManager]::new($document.NameTable)
$namespace.AddNamespace('u','urn:schemas-microsoft-com:unattend')
$oobeNode = $document.SelectSingleNode('//u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:OOBE',$namespace)
if (-not $oobeNode) {
    throw 'Le composant OOBE du fichier de reponses est absent.'
}

# Liste publiee par Microsoft pour Microsoft-Windows-Shell-Setup/OOBE.
# HidePrivacySettings est une propriete Autopilot/Intune, pas un parametre
# Windows Unattend. Son ajout a provoque la boucle OOBE de la version 7.88.
# SkipMachineOOBE et SkipUserOOBE sont volontairement exclus. Microsoft demande
# d automatiser OOBE avec UserAccounts et les reglages Hide* documentes.
$supportedOobeSettings = @(
    'HideEULAPage','HideLocalAccountScreen','HideOEMRegistrationScreen',
    'HideOnlineAccountScreens','HideWirelessSetupInOOBE','NetworkLocation',
    'OEMAppID','ProtectYourPC',
    'UnattendEnableRetailDemo','VMModeOptimizations'
)
$unsupportedOobeSettings = @(
    $oobeNode.ChildNodes |
        Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element -and $_.LocalName -notin $supportedOobeSettings } |
        ForEach-Object LocalName
)
if ($unsupportedOobeSettings.Count -gt 0) {
    throw "Parametre OOBE non pris en charge par Windows Unattend : $($unsupportedOobeSettings -join ', ')."
}
$autoLogonDomain=$document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Domain',$namespace)
$autoLogonPassword=$document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Password/u:Value',$namespace)
$localPassword=$document.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccount/u:Password/u:Value',$namespace)
if(-not $autoLogonDomain -or $autoLogonDomain.InnerText -cne $computerName -or $autoLogonDomain.InnerText -eq '.' -or
   -not $autoLogonPassword -or $autoLogonPassword.InnerText -ne '' -or -not $localPassword -or $localPassword.InnerText -ne '' -or
   $document.OuterXml -match 'BASTOS-Setup-Temporary'){
    throw 'Le fichier de reponses contient un domaine local ou un mot de passe incoherent.'
}



if($PostInstallMode -eq 'WindowsOnly'){Set-BastosRufusAccountFlow -Document $document -Options $script:RufusOptions -FirstLogonScriptPath (Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) 'sources\$OEM$\$1\ProgramData\BASTOS-ISO\Rufus-FirstLogon.ps1')}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$settings = [Xml.XmlWriterSettings]::new()
$settings.Encoding = [Text.UTF8Encoding]::new($false)
$settings.Indent = $true
$writer = [Xml.XmlWriter]::Create($OutputPath,$settings)
try { $document.Save($writer) } finally { $writer.Dispose() }

[pscustomobject]@{
    Success = $true
    OfficialIsoPath = [IO.Path]::GetFullPath($OfficialIsoPath)
    AnswerFilePath = [IO.Path]::GetFullPath($OutputPath)
    WindowsLocale = $WindowsLocale
    KeyboardLayout = $KeyboardLayout
    LocalUserName = $LocalUserName
    LocalDisplayName = $localDisplayName
    ComputerName = $computerName
    PostInstallMode = $PostInstallMode
    CreatedUtc = [DateTime]::UtcNow.ToString('o')
}
