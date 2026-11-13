[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('chrome','firefox','librewolf','brave','opera','helium')][string]$Browser,
    [string]$ResultPath = '',
    [switch]$DetectOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
$definitions = @{
    chrome = @{
        Name='Google Chrome'; Pattern='^Google Chrome$'; Extra='--force-uninstall'; Processes=@('GoogleUpdate','GoogleUpdater')
        Paths=@("$env:ProgramFiles\Google\Chrome","$programFilesX86\Google\Chrome","$env:ProgramData\Google\Chrome","$env:LOCALAPPDATA\Google\Chrome","$env:APPDATA\Google\Chrome")
        VendorRoots=@("$env:ProgramFiles\Google","$programFilesX86\Google","$env:ProgramData\Google","$env:LOCALAPPDATA\Google","$env:APPDATA\Google")
        Registry=@('Registry::HKEY_CURRENT_USER\Software\Google\Chrome','Registry::HKEY_LOCAL_MACHINE\Software\Google\Chrome','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Google\Chrome','Registry::HKEY_CURRENT_USER\Software\Classes\ChromeHTML','Registry::HKEY_LOCAL_MACHINE\Software\Classes\ChromeHTML','Registry::HKEY_CURRENT_USER\Software\Clients\StartMenuInternet\Google Chrome','Registry::HKEY_LOCAL_MACHINE\Software\Clients\StartMenuInternet\Google Chrome')
        VendorRegistry=@('Registry::HKEY_CURRENT_USER\Software\Google','Registry::HKEY_LOCAL_MACHINE\Software\Google','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Google','Registry::HKEY_CURRENT_USER\Software\Policies\Google','Registry::HKEY_LOCAL_MACHINE\Software\Policies\Google')
        Publisher='Google'; Service='^(gupdate|gupdatem|GoogleUpdater)'; Task='Google|Chrome'; Shortcut='Google Chrome'
    }
    firefox = @{
        Name='Mozilla Firefox'; Pattern='^Mozilla Firefox(?: .*)?$'; Extra='/S'; Processes=@('firefox','maintenanceservice')
        Paths=@("$env:ProgramFiles\Mozilla Firefox","$programFilesX86\Mozilla Firefox","$env:ProgramData\Mozilla\Firefox","$env:LOCALAPPDATA\Mozilla\Firefox","$env:APPDATA\Mozilla\Firefox")
        VendorRoots=@("$env:ProgramData\Mozilla","$env:LOCALAPPDATA\Mozilla","$env:APPDATA\Mozilla")
        Registry=@('Registry::HKEY_CURRENT_USER\Software\Mozilla\Firefox','Registry::HKEY_LOCAL_MACHINE\Software\Mozilla\Firefox','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Mozilla\Firefox','Registry::HKEY_CURRENT_USER\Software\Classes\FirefoxHTML','Registry::HKEY_CURRENT_USER\Software\Classes\FirefoxURL','Registry::HKEY_LOCAL_MACHINE\Software\Classes\FirefoxHTML','Registry::HKEY_LOCAL_MACHINE\Software\Classes\FirefoxURL')
        VendorRegistry=@(); Publisher='Mozilla'; Service='MozillaMaintenance'; Task='Mozilla|Firefox'; Shortcut='Mozilla Firefox|Firefox'
    }
    librewolf = @{
        Name='LibreWolf'; Pattern='^LibreWolf(?: .*)?$'; Extra='/S'; Processes=@('librewolf')
        Paths=@("$env:ProgramFiles\LibreWolf","$programFilesX86\LibreWolf","$env:ProgramData\LibreWolf","$env:LOCALAPPDATA\LibreWolf","$env:APPDATA\LibreWolf","$env:USERPROFILE\.librewolf")
        VendorRoots=@(); Registry=@('Registry::HKEY_CURRENT_USER\Software\LibreWolf','Registry::HKEY_LOCAL_MACHINE\Software\LibreWolf','Registry::HKEY_CURRENT_USER\Software\Classes\LibreWolfHTML','Registry::HKEY_CURRENT_USER\Software\Classes\LibreWolfURL','Registry::HKEY_LOCAL_MACHINE\Software\Classes\LibreWolfHTML','Registry::HKEY_LOCAL_MACHINE\Software\Classes\LibreWolfURL')
        VendorRegistry=@(); Publisher='LibreWolf'; Service='LibreWolf'; Task='LibreWolf'; Shortcut='LibreWolf'
    }
    brave = @{
        Name='Brave Browser'; Pattern='^Brave$|^Brave Browser$'; Extra='--force-uninstall'; Processes=@('brave','BraveUpdate','BraveUpdater')
        Paths=@("$env:ProgramFiles\BraveSoftware\Brave-Browser","$programFilesX86\BraveSoftware\Brave-Browser","$env:ProgramData\BraveSoftware\Brave-Browser","$env:LOCALAPPDATA\BraveSoftware\Brave-Browser","$env:APPDATA\BraveSoftware\Brave-Browser")
        VendorRoots=@("$env:ProgramFiles\BraveSoftware","$programFilesX86\BraveSoftware","$env:ProgramData\BraveSoftware","$env:LOCALAPPDATA\BraveSoftware","$env:APPDATA\BraveSoftware")
        Registry=@('Registry::HKEY_CURRENT_USER\Software\BraveSoftware\Brave-Browser','Registry::HKEY_LOCAL_MACHINE\Software\BraveSoftware\Brave-Browser','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\BraveSoftware\Brave-Browser','Registry::HKEY_CURRENT_USER\Software\Classes\BraveHTML','Registry::HKEY_LOCAL_MACHINE\Software\Classes\BraveHTML')
        VendorRegistry=@('Registry::HKEY_CURRENT_USER\Software\BraveSoftware','Registry::HKEY_LOCAL_MACHINE\Software\BraveSoftware','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\BraveSoftware'); Publisher='Brave'; Service='BraveUpdate|BraveUpdater'; Task='Brave'; Shortcut='Brave'
    }
    helium = @{
        Name='Helium'; Pattern='^(?:imput )?Helium(?: .*)?$'; Extra='--force-uninstall'; Processes=@()
        Paths=@("$env:ProgramFiles\imput\Helium","$programFilesX86\imput\Helium","$env:LOCALAPPDATA\imput\Helium","$env:APPDATA\imput\Helium")
        VendorRoots=@(); Registry=@('Registry::HKEY_CURRENT_USER\Software\imput\Helium','Registry::HKEY_LOCAL_MACHINE\Software\imput\Helium','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\imput\Helium','Registry::HKEY_CURRENT_USER\Software\Clients\StartMenuInternet\Helium','Registry::HKEY_LOCAL_MACHINE\Software\Clients\StartMenuInternet\Helium')
        VendorRegistry=@(); Publisher='^imput$'; Service='^Helium'; Task='^Helium'; Shortcut='^Helium(?:\s|\.|$)'
    }
    opera = @{
        Name='Opera'; Pattern='^Opera(?: Stable)?$'; Extra='/silent'; Processes=@('opera','opera_crashreporter','opera_autoupdate')
        Paths=@("$env:ProgramFiles\Opera","$programFilesX86\Opera","$env:ProgramData\Opera Software","$env:LOCALAPPDATA\Programs\Opera","$env:LOCALAPPDATA\Opera Software","$env:APPDATA\Opera Software")
        VendorRoots=@("$env:ProgramData\Opera Software","$env:LOCALAPPDATA\Opera Software","$env:APPDATA\Opera Software")
        Registry=@('Registry::HKEY_CURRENT_USER\Software\Opera Software','Registry::HKEY_LOCAL_MACHINE\Software\Opera Software','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Opera Software','Registry::HKEY_CURRENT_USER\Software\Classes\OperaStable','Registry::HKEY_LOCAL_MACHINE\Software\Classes\OperaStable')
        VendorRegistry=@(); Publisher='Opera'; Service='Opera'; Task='Opera'; Shortcut='Opera'
    }
}

function Save-Result([bool]$Success,[string]$Message,[int]$Removed=0) {
    $result=[ordered]@{Success=$Success;Browser=$Browser;Removed=$Removed;Message=$Message;Date=[DateTime]::UtcNow.ToString('o')}
    if($ResultPath){$parent=Split-Path -Parent $ResultPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    [pscustomobject]$result
}

function Get-UninstallEntries {
    $paths=@('Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','Registry::HKEY_CURRENT_USER\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)
}

function Get-EntryText($Entry,[string]$Property) {$item=$Entry.PSObject.Properties[$Property];if($item){[string]$item.Value}else{''}}
function Test-EntryDisplayName($Entry,[string]$Pattern) {$name=Get-EntryText $Entry 'DisplayName';return -not [string]::IsNullOrWhiteSpace($name) -and $name -match $Pattern}

function Split-UninstallCommand([string]$CommandLine) {
    $value=$CommandLine.Trim()
    if($value -match '^"([^"]+)"\s*(.*)$'){return @($Matches[1],$Matches[2])}
    if($value -match '^([^\s]+)\s*(.*)$'){return @($Matches[1],$Matches[2])}
    throw 'La commande de desinstallation enregistree par Windows est illisible.'
}

function Get-ShortcutRoots {
    @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('CommonDesktopDirectory'),[Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'),(Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')) | Where-Object {$_}
}

function Invoke-Reg([string[]]$Arguments) {
    $previous=$ErrorActionPreference;$ErrorActionPreference='SilentlyContinue'
    try{$output=@(& reg.exe @Arguments 2>&1);$code=$LASTEXITCODE;[pscustomobject]@{Code=$code;Output=$output}}
    finally{$ErrorActionPreference=$previous}
}

function Test-SharedChromeRegistryTree([Microsoft.Win32.RegistryKey]$Key,[string]$RelativePath) {
    # These registrations are shared Windows integrations, not Chrome installation evidence.
    # Inspect registry data directly: reg.exe labels and empty output vary with Windows language.
    $containers=@('Google','Google\Chrome','Google\Chrome\NativeMessagingHosts','Google\Chrome\Extensions')
    $knownHosts=@{
        'Google\Chrome\NativeMessagingHosts\com.microsoft.browsercore'=(Join-Path $env:SystemRoot 'BrowserCore\manifest.json')
        'Google\Chrome\NativeMessagingHosts\com.microsoft.defender.browser_extension.native_message_host'=(Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Windows Defender\com.microsoft.defender.be.chrome.json')
    }
    $values=@($Key.GetValueNames())
    $children=@($Key.GetSubKeyNames())
    if($knownHosts.ContainsKey($RelativePath)) {
        if($children.Count -ne 0 -or $values.Count -ne 1 -or $values[0] -ne ''){return $false}
        if($Key.GetValueKind('') -ne [Microsoft.Win32.RegistryValueKind]::String){return $false}
        return [string]::Equals([string]$Key.GetValue(''),$knownHosts[$RelativePath],[StringComparison]::OrdinalIgnoreCase)
    }
    if($RelativePath -notin $containers -or $values.Count -gt 0){return $false}
    foreach($name in $children) {
        $child=$Key.OpenSubKey($name)
        if(-not $child){throw 'Une cle de registre a change pendant sa lecture.'}
        try {if(-not(Test-SharedChromeRegistryTree $child ($RelativePath+'\'+$name))){return $false}}
        finally {$child.Dispose()}
    }
    return $true
}

function Test-MeaningfulRegistryPath([string]$Path) {
    if($Browser -ne 'chrome' -or $Path -notmatch '^Registry::(HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE)\\(Software\\(?:WOW6432Node\\)?Google(?:\\Chrome)?)$'){return (Test-Path -LiteralPath $Path -ErrorAction Stop)}
    $hive=if($Matches[1] -eq 'HKEY_CURRENT_USER'){[Microsoft.Win32.RegistryHive]::CurrentUser}else{[Microsoft.Win32.RegistryHive]::LocalMachine}
    $subkey=$Matches[2]
    $relative=($subkey -replace '^Software\\(?:WOW6432Node\\)?','')
    foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
        try {
            $key=$base.OpenSubKey($subkey)
            if($key){try {if(-not(Test-SharedChromeRegistryTree $key $relative)){return $true}}finally{$key.Dispose()}}
        } finally {$base.Dispose()}
    }
    return $false
}

function Get-ResidualItems($Definition,[bool]$IncludeVendor) {
    $items=New-Object Collections.Generic.List[string]
    foreach($path in @($Definition.Paths)){if($path -and (Test-Path -LiteralPath $path)){$items.Add($path)}}
    foreach($path in @($Definition.Registry)){if(Test-MeaningfulRegistryPath $path){$items.Add($path)}}
    if($IncludeVendor){foreach($path in @($Definition.VendorRoots)){if($path -and (Test-Path -LiteralPath $path)){$items.Add($path)}};foreach($path in @($Definition.VendorRegistry)){if(Test-MeaningfulRegistryPath $path){$items.Add($path)}}}
    foreach($root in Get-ShortcutRoots){if(Test-Path -LiteralPath $root){Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue|Where-Object {$_.Name -match $Definition.Shortcut -and $_.Extension -in '.lnk','.url'}|ForEach-Object {$items.Add($_.FullName)}}}
    @($items|Select-Object -Unique)
}

function Remove-ApprovedDirectory([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)-or -not(Test-Path -LiteralPath $Path)){return 0}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $roots=@($env:ProgramFiles,$programFilesX86,$env:ProgramData,$env:LOCALAPPDATA,$env:APPDATA,$env:USERPROFILE)|Where-Object {$_}|ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\')}
    $approved=$false
    foreach($root in $roots){if($full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)-and $full.Length -gt ($root.Length+1)){$approved=$true;break}}
    if(-not $approved){throw "Chemin de nettoyage refuse : $full"}
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
    return 1
}

function Remove-RegistryPath([string]$Path) {
    if($Browser -eq 'chrome' -and -not(Test-MeaningfulRegistryPath $Path)){return 0}
    $native=$Path -replace '^Registry::HKEY_CURRENT_USER\\','HKCU\' -replace '^Registry::HKEY_LOCAL_MACHINE\\','HKLM\'
    if($native -eq $Path){throw "Chemin de registre refuse : $Path"}
    $removed=0
    foreach($view in @('/reg:64','/reg:32')){
        $query=Invoke-Reg @('query',$native,$view)
        if($query.Code -eq 0){$delete=Invoke-Reg @('delete',$native,'/f',$view);if($delete.Code -eq 0){$removed=1}}
    }
    return $removed
}

function Clear-ChromeVendorResidue {
    foreach($key in @('HKCU\Software\Google\Update','HKLM\Software\Google\Update','HKLM\Software\WOW6432Node\Google\Update')){foreach($view in @('/reg:64','/reg:32')){[void](Invoke-Reg @('delete',$key,'/f',$view))}}
    foreach($key in @('HKCU\Software\Google\Chrome','HKLM\Software\Google\Chrome')){foreach($value in @('UsageStatsInSample','InstallerPinned')){foreach($view in @('/reg:64','/reg:32')){[void](Invoke-Reg @('delete',$key,'/v',$value,'/f',$view))}}}
}

try {
    $definition=$definitions[$Browser]
    $entry=Get-UninstallEntries|Where-Object {Test-EntryDisplayName $_ $definition.Pattern}|Select-Object -First 1
    $otherVendorProduct=Get-UninstallEntries|Where-Object {(Get-EntryText $_ 'Publisher') -match $definition.Publisher -and -not(Test-EntryDisplayName $_ $definition.Pattern) -and (Get-EntryText $_ 'DisplayName') -notmatch 'Update|Updater|Maintenance'}|Select-Object -First 1
    $includeVendor=$null -eq $otherVendorProduct
    $before=@(Get-ResidualItems $definition $includeVendor)
    if($DetectOnly){$state=if($entry){'installe'}elseif($before.Count){"absent mais $($before.Count) residu(s) detecte(s)"}else{'absent et sans residu'};Save-Result $true "$($definition.Name) : $state." 0|Out-Null;exit 0}

    if($Browser -in @('helium','chrome')){
        foreach($process in @(Get-Process chrome -ErrorAction SilentlyContinue)){
            if($process.Path -and @($definition.Paths | Where-Object {$process.Path.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){$process | Stop-Process -Force -ErrorAction Stop}
        }
    }
    foreach($name in @($definition.Processes)){Get-Process -Name $name -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue}
    $uninstallerExitCode=0
    if($entry){
        $quiet=$entry.PSObject.Properties['QuietUninstallString'];$normal=$entry.PSObject.Properties['UninstallString']
        $commandLine=if($quiet-and $quiet.Value){[string]$quiet.Value}elseif($normal){[string]$normal.Value}else{''}
        if([string]::IsNullOrWhiteSpace($commandLine)){throw "Windows ne fournit aucune commande pour supprimer $($definition.Name)."}
        $parts=Split-UninstallCommand $commandLine;$executable=[Environment]::ExpandEnvironmentVariables($parts[0])
        if(-not(Test-Path -LiteralPath $executable -PathType Leaf)){throw "Le desinstalleur officiel est introuvable : $executable"}
        $arguments=$parts[1];if($arguments -notmatch [regex]::Escape([string]$definition.Extra)){$arguments=($arguments+' '+$definition.Extra).Trim()}
        $process=Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden;$uninstallerExitCode=$process.ExitCode
        $deadline=[DateTime]::UtcNow.AddSeconds(30);do{Start-Sleep -Milliseconds 500;$remaining=Get-UninstallEntries|Where-Object {Test-EntryDisplayName $_ $definition.Pattern}|Select-Object -First 1}while($remaining-and [DateTime]::UtcNow-lt $deadline)
        if($remaining){throw "$($definition.Name) est encore enregistre comme installe apres son desinstalleur (code $uninstallerExitCode)."}
    }

    $removed=0
    foreach($path in @($definition.Paths)){$removed+=Remove-ApprovedDirectory $path}
    foreach($path in @($definition.Registry)){$removed+=Remove-RegistryPath $path}
    foreach($root in Get-ShortcutRoots){if(Test-Path -LiteralPath $root){Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue|Where-Object {$_.Name-match $definition.Shortcut -and $_.Extension-in '.lnk','.url'}|ForEach-Object {Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue;$removed++}}}
    if($includeVendor){
        Get-ScheduledTask -ErrorAction SilentlyContinue|Where-Object {$_.TaskName-match $definition.Task -or $_.TaskPath-match $definition.Task}|ForEach-Object {Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue;$removed++}
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue|Where-Object {$_.Name-match $definition.Service}|ForEach-Object {Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue;& sc.exe delete $_.Name|Out-Null;$removed++}
        if($Browser -eq 'chrome'){Clear-ChromeVendorResidue}
        foreach($path in @($definition.VendorRegistry)){$removed+=Remove-RegistryPath $path}
        foreach($path in @($definition.VendorRoots)){$removed+=Remove-ApprovedDirectory $path}
    }

    $left=@(Get-ResidualItems $definition $includeVendor)
    if($left.Count){throw "Nettoyage incomplet de $($definition.Name) : $($left -join '; ')"}
    $detail=if($uninstallerExitCode){" Le code technique $uninstallerExitCode a ete ignore car la suppression complete est confirmee."}else{''}
    Save-Result $true "$($definition.Name) et toutes ses donnees locales ont ete supprimes. $removed element(s) nettoye(s).$detail" $removed|Out-Null
    exit 0
} catch {Save-Result $false $_.Exception.Message 0|Out-Null;exit 1}
