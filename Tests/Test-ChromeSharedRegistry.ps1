param([string]$ScriptPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'InstallerScripts\Uninstall-BASTOS-Browser.ps1'),[switch]$CheckCurrentMachine)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Test-SharedChromeRegistryTree','Test-MeaningfulRegistryPath')){
    $function=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
    . ([scriptblock]::Create($function.Extent.Text))
}
$count=0
function Check([bool]$condition,[string]$name){if(-not $condition){throw $name};$script:count++;Write-Output "OK : $name"}
$testPath='Software\BASTOS\Tests\ChromeShared-'+[guid]::NewGuid().ToString('N')
$base=[Microsoft.Win32.Registry]::CurrentUser
function Fixture([scriptblock]$setup,[bool]$expected,[string]$name){
    $key=$base.CreateSubKey($testPath)
    try {
        & $setup $key
        Check ((Test-SharedChromeRegistryTree $key 'Google') -eq $expected) $name
    } finally {$key.Dispose();$base.DeleteSubKeyTree($testPath,$false)}
}
function HostKey($key,[string]$name,[string]$path){$child=$key.CreateSubKey('Chrome\NativeMessagingHosts\'+$name);try{$child.SetValue('',$path,[Microsoft.Win32.RegistryValueKind]::String)}finally{$child.Dispose()}}
$browsercore=Join-Path $env:SystemRoot 'BrowserCore\manifest.json'
$defender=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Windows Defender\com.microsoft.defender.be.chrome.json'
Fixture {} $true 'Conteneur Google vide'
Fixture {param($key)$child=$key.CreateSubKey('Chrome\Extensions');$child.Dispose()} $true 'Conteneur Extensions vide'
Fixture {param($key)HostKey $key 'com.microsoft.browsercore' $browsercore} $true 'Integration BrowserCore Windows preservee'
Fixture {param($key)HostKey $key 'com.microsoft.defender.browser_extension.native_message_host' $defender} $true 'Integration Defender preservee'
Fixture {param($key)HostKey $key 'com.microsoft.browsercore' $browsercore;HostKey $key 'com.microsoft.defender.browser_extension.native_message_host' $defender} $true 'Deux integrations Microsoft ensemble'
Fixture {param($key)HostKey $key 'com.microsoft.browsercore' 'C:\other\manifest.json'} $false 'Nom Microsoft avec mauvais chemin signale'
Fixture {param($key)HostKey $key 'unknown.host' $browsercore} $false 'Hote inconnu signale'
Fixture {param($key)$key.SetValue('Version','1')} $false 'Valeur residuelle Google signalee'
Fixture {param($key)$child=$key.CreateSubKey('Chrome');$child.SetValue('UsageStatsInSample',1);$child.Dispose()} $false 'Valeur residuelle Chrome signalee'
Fixture {param($key)$child=$key.CreateSubKey('Chrome\Extensions\real-extension');$child.Dispose()} $false 'Extension Chrome reelle signalee'
Fixture {param($key)$child=$key.CreateSubKey('OtherProduct');$child.Dispose()} $false 'Autre produit Google non ignore'
Fixture {param($key)HostKey $key 'com.microsoft.browsercore' $browsercore;$child=$key.OpenSubKey('Chrome\NativeMessagingHosts\com.microsoft.browsercore',$true);$child.SetValue('extra','data');$child.Dispose()} $false 'Valeur supplementaire sous hote connu signalee'
Fixture {param($key)$child=$key.CreateSubKey('Chrome\NativeMessagingHosts\com.microsoft.browsercore');$child.Dispose()} $false 'Hote connu sans manifeste non ignore'
Fixture {param($key)$child=$key.CreateSubKey('Chrome\NativeMessagingHosts\com.microsoft.browsercore\unexpected');$child.Dispose()} $false 'Sous-cle inattendue signalee'
$Browser='chrome'
# Read-only integration checks on the reported machine, in both registry views.
if($CheckCurrentMachine){foreach($path in @('Registry::HKEY_CURRENT_USER\Software\Google','Registry::HKEY_LOCAL_MACHINE\Software\Google','Registry::HKEY_CURRENT_USER\Software\Google\Chrome','Registry::HKEY_LOCAL_MACHINE\Software\Google\Chrome')){
    Check (-not(Test-MeaningfulRegistryPath $path)) ('Etat reel sans faux positif : '+$path)
}}
Write-Output "PASS : $count controles ; fixtures registre isolees supprimees ; integrations Windows lues uniquement."
