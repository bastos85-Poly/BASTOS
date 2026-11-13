param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.RecoveryEvidence.psm1') -Force
$count=0
function Check($ok,$message){if(-not $ok){throw $message};$script:count++}
$temp=Join-Path $env:TEMP ('Bastos-Cache-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'media\sources'),(Join-Path $temp 'media\boot'),(Join-Path $temp 'iso\sources') -Force|Out-Null
try{
    $root=Join-Path $temp 'media';$isoRoot=Join-Path $temp 'iso'
    $iso=Join-Path $temp 'windows.iso';$launcher=Join-Path $temp 'launcher.cmd';$probe=Join-Path $temp 'probe.exe'
    foreach($file in @($iso,$launcher,$probe,(Join-Path $root 'setup.exe'),(Join-Path $root 'boot\boot.sdi'),(Join-Path $root 'sources\install.wim'),(Join-Path $root 'sources\boot.wim'),(Join-Path $isoRoot 'sources\boot.wim'))){[IO.File]::WriteAllText($file,'fixture-'+[IO.Path]::GetFileName($file))}
    $state=[ordered]@{Schema=8;IsoSha256=(Get-FileHash $iso).Hash;InstallWimSanitized=$true;SanitizedImageIndex=6;WindowsEditionId='Professional';InstallWimSha256=(Get-FileHash (Join-Path $root 'sources\install.wim')).Hash;BootWimSha256=(Get-FileHash (Join-Path $root 'sources\boot.wim')).Hash;RecoveryLauncherSha256=(Get-FileHash $launcher).Hash;RecoveryProbeSha256=(Get-FileHash $probe).Hash}
    function Save-State{[IO.File]::WriteAllText((Join-Path $root 'BASTOS-MEDIA-STATE.json'),($state|ConvertTo-Json));[IO.File]::WriteAllText((Join-Path $root 'BASTOS-ISO.sha256'),$state.IsoSha256)}
    function Plan{Get-BastosRecoveryCachePlan -Root $root -IsoPath $iso -ImageIndex 6 -EditionId Professional -LauncherPath $launcher -ProbePath $probe}
    Check ((Plan).Mode -eq 'Full') 'Absent state requires full staging'
    Save-State
    Check ((Plan).Mode -eq 'Reuse') 'Schema 8 migrates without rebuilding verified Windows'
    Check ((Plan).RequiredFreeBytes -eq 2GB) 'Reuse requires reserve, not another full ISO'
    Check ((Get-BastosRecoveryCachePlan -Root $root -IsoPath $iso -ImageIndex 6 -EditionId Professional -LauncherPath $launcher -ProbePath $probe -CleanupProfile minimal-2).Mode -eq 'Full') 'Enabling offline cleanup rebuilds Windows'
    $state.CleanupProfile='minimal-1';Save-State
    Check ((Get-BastosRecoveryCachePlan -Root $root -IsoPath $iso -ImageIndex 6 -EditionId Professional -LauncherPath $launcher -ProbePath $probe -CleanupProfile minimal-2).Mode -eq 'Full') 'Previous clean revision must rebuild to preserve Phone Link'
    $state.CleanupProfile='minimal-2';Save-State
    Check ((Plan).Mode -eq 'Full') 'Disabling cleanup restores image from official source'
    Check ((Get-BastosRecoveryCachePlan -Root $root -IsoPath $iso -ImageIndex 6 -EditionId Professional -LauncherPath $launcher -ProbePath $probe -CleanupProfile minimal-2).Mode -eq 'Reuse') 'Same cleanup profile may reuse verified image'
    $state.CleanupProfile='';Save-State
    foreach($key in @('RecoveryLauncherSha256','RecoveryProbeSha256','BootWimSha256')){
        $old=$state[$key];$state[$key]='A'*64;Save-State
        Check ((Plan).Mode -eq 'Boot') ('Only boot invalidated by '+$key)
        Check ((Plan).RequiredFreeBytes -gt 2GB) 'Boot plan budgets its staged image'
        $state[$key]=$old;Save-State
    }
    foreach($pair in @(@('IsoSha256',('A'*64)),@('SanitizedImageIndex',5),@('WindowsEditionId','Core'),@('InstallWimSanitized',$false),@('InstallWimSha256',('B'*64)),@('Schema',99))){
        $old=$state[$pair[0]];$state[$pair[0]]=$pair[1];Save-State
        Check ((Plan).Mode -eq 'Full') ('Full invalidation for '+$pair[0])
        $state[$pair[0]]=$old;Save-State
    }
    $state.Schema=9;$state.WindowsCacheRevision=1;$state.BootCacheRevision=1;$state.SourceBootWimBytes=1024;Save-State
    Check ((Plan).Mode -eq 'Reuse') 'Current cache revision reusable'
    $state.Remove('WindowsCacheRevision');Save-State;Check ((Plan).Mode -eq 'Full') 'Current schema requires Windows revision proof'
    $state.WindowsCacheRevision=1;$state.Remove('BootCacheRevision');Save-State;Check ((Plan).Mode -eq 'Boot') 'Missing current boot revision refreshes only boot'
    $state.BootCacheRevision=2;Save-State;Check ((Plan).Mode -eq 'Boot') 'Boot revision preserves Windows'
    $state.BootCacheRevision=1;$state.WindowsCacheRevision=2;Save-State;Check ((Plan).Mode -eq 'Full') 'Sanitizer revision invalidates Windows'
    $state.WindowsCacheRevision=1;Save-State
    [IO.File]::AppendAllText((Join-Path $root 'sources\install.wim'),'tampered')
    Check ((Plan).Mode -eq 'Full') 'Real Windows bytes checked, not only metadata'
    [IO.File]::WriteAllText((Join-Path $root 'sources\install.wim'),'fixture-install.wim')
    [IO.File]::AppendAllText((Join-Path $root 'sources\boot.wim'),'tampered')
    Check ((Plan).Mode -eq 'Boot') 'Corrupt boot preserves independently verified Windows'
    Remove-Item -LiteralPath (Join-Path $root 'sources\boot.wim') -Force
    Check ((Plan).Mode -eq 'Boot') 'Missing boot can be rebuilt independently'
    [IO.File]::WriteAllText((Join-Path $root 'BASTOS-MEDIA-STATE.json'),'{invalid')
    Check ((Plan).Mode -eq 'Full') 'Unreadable evidence cannot authorize reuse'
    Save-State
    # Execute the actual worker boot-refresh branch with tiny files and mocked
    # DISM/partition operations. This exercises staging, atomic publication,
    # cleanup and failure retention without opening an image or touching disks.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'InstallerScripts\Initialize-BASTOS-Recovery.ps1'),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'Worker syntax valid in Windows PowerShell 5.1'
    $body=$null
    foreach($node in $ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst]},$true)){
        foreach($clause in $node.Clauses){if($clause.Item1.Extent.Text -eq '$cachePlan.Mode -eq ''Boot''' -and $clause.Item2.Extent.Text.Contains('$stagedBoot=')){$body=$clause.Item2.Extent.Text}}
    }
    Check ($null -ne $body) 'Actual boot-refresh branch located'
    $refresh=[scriptblock]::Create($body.Substring(1,$body.Length-2))
    function Assert-RecoveryWriteTarget{}
    function Write-RecoveryProgress{}
    $script:failPatch=$false
    function Update-RecoveryBootImage{param($BootWimPath,$LauncherPath,$ProbePath)
        [IO.File]::AppendAllText($BootWimPath,'-patched')
        if($script:failPatch){throw 'simulated DISM failure'}
        [pscustomobject]@{CompatibilityMode='ExactLauncher';EmbeddedLauncherSha256='fixture'}
    }
    $recoveryPartition=$null;$letter='Z';$launcherPath=$launcher;$probePath=$probe
    $isoBootHash=(Get-FileHash (Join-Path $isoRoot 'sources\boot.wim')).Hash
    $currentMediaState=[pscustomobject]$state
    $installHash=(Get-FileHash (Join-Path $root 'sources\install.wim')).Hash
    & $refresh
    Check (([IO.File]::ReadAllText((Join-Path $root 'sources\boot.wim'))) -eq 'fixture-boot.wim-patched') 'Missing boot published from pristine ISO'
    & $refresh
    Check (([IO.File]::ReadAllText((Join-Path $root 'sources\boot.wim'))) -eq 'fixture-boot.wim-patched') 'Refresh does not accumulate patches'
    Check ((Get-FileHash (Join-Path $root 'sources\install.wim')).Hash -eq $installHash) 'Windows image remains byte-identical'
    $before=(Get-FileHash (Join-Path $root 'sources\boot.wim')).Hash
    $script:failPatch=$true;$failed=$false
    try{& $refresh}catch{$failed=$true}
    Check $failed 'DISM failure propagated'
    Check ((Get-FileHash (Join-Path $root 'sources\boot.wim')).Hash -eq $before) 'Failed patch preserves previous boot'
    Check (@(Get-ChildItem (Join-Path $root 'sources') -Filter 'BASTOS-Boot-Staging-*').Count -eq 0) 'Temporary boot file cleaned after success and failure'
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture outside TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "PASS : $count cache checks; no real image mounted or disk modified."
