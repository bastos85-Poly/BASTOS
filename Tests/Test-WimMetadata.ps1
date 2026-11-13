param([Parameter(Mandatory)][string]$SourceWim,[string]$SourceRoot='')
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path -Parent $PSScriptRoot}
$module=Import-Module (Join-Path $SourceRoot 'InstallerScripts\BASTOS-RecoveryValidation.psm1') -Force -PassThru
$count=0
function Check($ok,$message){if(-not $ok){throw $message};$script:count++}
function Refuses([scriptblock]$action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Check $failed $message}
$temp=Join-Path $env:TEMP ('Bastos-WimMetadata-Test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    $sourceHash=(Get-FileHash -LiteralPath $SourceWim).Hash
    $file=Join-Path $temp 'fixture.wim'
    Copy-Item -LiteralPath $SourceWim -Destination $file
    (Get-Item -LiteralPath $file).IsReadOnly=$false
    $original=Get-BastosWimMetadata -ImagePath $file
    Check (@($original.WIM.IMAGE).Count -ge 2) 'Fixture includes multiple image indices'
    $index=[int]$original.WIM.IMAGE[0].INDEX
    $path="/WIM/IMAGE[@INDEX='$index']"
    $before=$original.SelectSingleNode($path)
    $other=$original.WIM.IMAGE[1].OuterXml
    [xml]$wanted=$original.OuterXml
    $wanted.SelectSingleNode($path+'/WINDOWS/EDITIONID').InnerText='BASTOS-METADATA-REGRESSION'
    Restore-BastosWimWindowsMetadata -ImagePath $file -ImageIndex $index -OriginalMetadata $wanted
    $actual=Get-BastosWimMetadata -ImagePath $file
    $image=$actual.SelectSingleNode($path)
    Check ($image.SelectSingleNode('WINDOWS').OuterXml -ceq $wanted.SelectSingleNode($path+'/WINDOWS').OuterXml) 'Real WIMGAPI write persists selected image Windows metadata'
    Check ($actual.WIM.IMAGE[1].OuterXml -ceq $other) 'Unselected index unchanged'
    foreach($name in @('NAME','DESCRIPTION','FLAGS','DIRCOUNT','FILECOUNT','TOTALBYTES')){
        Check ($image.SelectSingleNode($name).OuterXml -ceq $before.SelectSingleNode($name).OuterXml) ('Current image field retained: '+$name)
    }
    # Simulate a commit which lost WINDOWS while retaining current image data.
    [void]$image.RemoveChild($image.SelectSingleNode('WINDOWS'))
    & $module {param($p,$i,$xml)[Bastos.WimMetadata]::WriteImage($p,[uint32]$i,$xml)} $file $index $image.OuterXml
    Check (-not (Get-BastosWimMetadata $file).SelectSingleNode($path+'/WINDOWS')) 'Missing WINDOWS fixture confirmed through real API'
    Restore-BastosWimWindowsMetadata -ImagePath $file -ImageIndex $index -OriginalMetadata $original
    $restored=Get-BastosWimMetadata $file
    Check ($restored.SelectSingleNode($path+'/WINDOWS').OuterXml -ceq $before.SelectSingleNode('WINDOWS').OuterXml) 'Missing WINDOWS restored from original snapshot'
    Check ($restored.WIM.IMAGE[1].OuterXml -ceq $other) 'Other index still unchanged after restoration'
    Refuses {Restore-BastosWimWindowsMetadata -ImagePath $file -ImageIndex 99 -OriginalMetadata $original} 'Invalid index refused'
    Check ((Get-FileHash -LiteralPath $SourceWim).Hash -eq $sourceHash) 'Original source WIM unchanged'
}finally{
    $resolved=[IO.Path]::GetFullPath($temp)
    if((Split-Path -Parent $resolved) -ne [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') -or [IO.Path]::GetFileName($resolved) -notmatch '^Bastos-WimMetadata-Test-[0-9a-f]{32}$'){throw 'Temporary cleanup outside scope refused'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count real WIMGAPI metadata checks on a disposable copy; no DISM mount, partition or reboot action."
