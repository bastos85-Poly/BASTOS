param([Parameter(Mandatory)][string]$AppRoot,[Parameter(Mandatory)][int]$ParentId,[string]$TestRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1')
$parent=if($TestRoot){[IO.Path]::GetFullPath($TestRoot)}else{Join-Path $env:LOCALAPPDATA 'Programs'}
$expected=[IO.Path]::GetFullPath((Join-Path $parent 'BASTOS')).TrimEnd('\')
if([IO.Path]::GetFullPath($AppRoot).TrimEnd('\') -ine $expected){throw 'Destination de desinstallation refusee.'}
function Assert-Plain {
 for($path=$expected;$path;$path=Split-Path -Parent $path){if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Destination redirigee refusee.'}}
 if(@(Get-ChildItem -LiteralPath $expected -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Lien interne refuse.'}
 if(-not(Test-Path -LiteralPath (Join-Path $expected 'Bastos.Native/BASTOS-Native.exe')) -or -not(Test-Path -LiteralPath (Join-Path $expected 'BASTOS-App-Manifest.json'))){throw 'Installation non reconnue.'}
}
try {
 Assert-Plain
 $self=Get-Process -Id $ParentId -ErrorAction SilentlyContinue
 if($self){if($self.Path -ine (Join-Path $expected 'Bastos-Uninstall.exe')){throw 'Processus parent divergent.'};Wait-Process -Id $ParentId -Timeout 30 -ErrorAction Stop}
 $active=@(Get-Process BASTOS-Native,BASTOS-Game -ErrorAction SilentlyContinue|Where-Object {((-not $TestRoot) -and (-not $_.Path)) -or ($_.Path -and $_.Path.StartsWith($expected+'\',[StringComparison]::OrdinalIgnoreCase))})
 if($active.Count){throw 'Fermez BASTOS et son module de jeu avant de desinstaller.'}
 Assert-Plain
 # Remove the checked application folder first. Leave the shortcut/registration
 # available if locked files prevent a complete uninstall.
 Remove-Item -LiteralPath $expected -Recurse -Force
 if(-not $TestRoot){
  $link=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'BASTOS.lnk'
  if(Test-Path -LiteralPath $link){$shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut($link);if($shortcut.TargetPath -ieq (Join-Path $expected 'Bastos.Native/BASTOS-Native.exe')){Remove-Item -LiteralPath $link -Force}}
  $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BASTOS'
  $registration=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
  if($registration -and $registration.InstallLocation -ieq $expected){Remove-Item -LiteralPath $key -Recurse -Force}
 }
}catch{
 $message='Desinstallation non terminee : '+$_.Exception.Message
 if($TestRoot){[IO.File]::WriteAllText((Join-Path $TestRoot 'Uninstall-error.txt'),$message)}else{Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($message,'BASTOS')}
 exit 1
}
