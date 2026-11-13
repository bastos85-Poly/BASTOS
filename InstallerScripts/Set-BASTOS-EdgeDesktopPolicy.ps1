[CmdletBinding()]
param([switch]$RemoveExistingShortcut)
$ErrorActionPreference='Stop'
# Only the browser's shortcuts. Keep Edge/WebView2 updates and browser data intact.
$key='HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
New-Item -Path $key -Force|Out-Null
foreach($pair in @(
    @{Name='CreateDesktopShortcutDefault';Value=0},
    @{Name='CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}';Value=0},
    @{Name='RemoveDesktopShortcutDefault';Value=2},
    @{Name='RemoveDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}';Value=2}
)){
    New-ItemProperty -LiteralPath $key -Name $pair.Name -PropertyType DWord -Value $pair.Value -Force|Out-Null
    if((Get-ItemPropertyValue -LiteralPath $key -Name $pair.Name) -ne $pair.Value){throw 'Politique raccourci Edge non appliquee.'}
}
if($RemoveExistingShortcut){
    $backup=Join-Path $env:LOCALAPPDATA ('BASTOS\Backups\EdgeDesktop-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $shell=New-Object -ComObject WScript.Shell
    foreach($desktop in @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))){
        $shortcut=Join-Path $desktop 'Microsoft Edge.lnk'
        if(Test-Path -LiteralPath $shortcut -PathType Leaf){
            $target=$shell.CreateShortcut($shortcut).TargetPath
            if($target -notmatch '\\Microsoft\\Edge\\Application\\msedge\.exe$'){throw 'Raccourci inattendu : conserve.'}
            New-Item -ItemType Directory -Path $backup -Force|Out-Null
            $saved=Join-Path $backup (([Guid]::NewGuid().ToString('N'))+'-Microsoft Edge.lnk')
            Move-Item -LiteralPath $shortcut -Destination $saved
            Write-Host ('Raccourci sauvegarde : '+$saved)
        }
    }
}
Write-Host 'Creation du raccourci Edge desactivee ; mises a jour et WebView2 conserves.'
