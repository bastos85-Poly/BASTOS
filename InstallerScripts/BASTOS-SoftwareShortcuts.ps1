# Shared post-install actions. Dot-sourcing this file does not change the PC.
function Get-BastosFluentCleanerExecutable {
    $packageRoots=@(
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\WinGet\Packages'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'WinGet\Packages')
    )
    $searchRoots=@()
    foreach($root in $packageRoots){
        if(Test-Path -LiteralPath $root -PathType Container){
            $searchRoots+=@(Get-ChildItem -LiteralPath $root -Directory -Filter 'Builtbybel.FluentCleaner_*' -ErrorAction Stop | Select-Object -ExpandProperty FullName)
        }
    }
    foreach($root in @(
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\FluentCleaner'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'FluentCleaner'),
        (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'chocolatey\lib\fluentcleaner')
    )){if(Test-Path -LiteralPath $root -PathType Container){$searchRoots+=$root}}
    foreach($root in $searchRoots){
        $executable=Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop |
            Where-Object {$_.Name -in @('FCleaner.exe','FluentCleaner.exe')} |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if($executable){return $executable.FullName}
    }
    throw 'FluentCleaner est installé, mais son exécutable est introuvable. Le raccourci reste absent.'
}

function New-BastosFluentCleanerDesktopShortcut {
    [CmdletBinding()]
    param([string]$DesktopPath=[Environment]::GetFolderPath('DesktopDirectory'))
    $target=Get-BastosFluentCleanerExecutable
    if(-not $DesktopPath){throw 'Le dossier Bureau de cet utilisateur est indisponible.'}
    if(-not(Test-Path -LiteralPath $DesktopPath -PathType Container)){New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null}
    $path=Join-Path $DesktopPath 'FluentCleaner.lnk'
    $shell=New-Object -ComObject WScript.Shell
    try {
        $shortcut=$shell.CreateShortcut($path)
        $shortcut.TargetPath=$target
        $shortcut.Arguments=''
        $shortcut.WorkingDirectory=Split-Path -Parent $target
        $shortcut.IconLocation=$target+',0'
        $shortcut.Description='FluentCleaner — nettoyage des fichiers temporaires Windows'
        $shortcut.WindowStyle=1
        $shortcut.Save()
        $check=$shell.CreateShortcut($path)
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or $check.TargetPath -ne $target -or $check.IconLocation -ne ($target+',0')){
            throw 'La vérification du raccourci FluentCleaner a échoué.'
        }
        return $path
    } finally {
        if($null -ne $shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    }
}
