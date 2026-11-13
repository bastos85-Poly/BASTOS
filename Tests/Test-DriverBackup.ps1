param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $SourceRoot 'InstallerScripts\Bastos.RecoveryEvidence.psm1') -Force -PassThru
$count=0
function Check($ok,$text){if(-not $ok){throw $text};$script:count++}
function Refuses([scriptblock]$action,$text){$refused=$false;try{& $action|Out-Null}catch{$refused=$true};Check $refused $text}
$temp=Join-Path $env:TEMP ('Bastos-Drivers-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $temp 'Recovery';$source=Join-Path $temp 'Source'
New-Item -ItemType Directory -Path $root,$source -Force|Out-Null
foreach($name in @('audio.inf','audio.sys','audio.cat')){[IO.File]::WriteAllText((Join-Path $source $name),'fixture-'+$name)}
try{
    & $module {param($source)
        $script:FixtureSource=$source;$script:FailExport=$false;$script:ExportCalls=0;$script:Unsupported=$false;$script:Empty=$false
        function script:Assert-BastosDriverSetupVersion{param($SetupPath)if($script:Unsupported){throw 'Unsupported Setup'}}
        function script:Get-WindowsDriver{param([switch]$Online,$ErrorAction)if(-not $script:Empty){[pscustomobject]@{OriginalFileName=(Join-Path $script:FixtureSource 'audio.inf')}}}
        function script:Export-WindowsDriver{param([switch]$Online,$Destination,$ErrorAction)
            $script:ExportCalls++
            New-Item -ItemType Directory -Path (Join-Path $Destination 'audio') -Force|Out-Null
            Copy-Item -Path (Join-Path $script:FixtureSource '*') -Destination (Join-Path $Destination 'audio') -Force
            if($script:FailExport){throw 'Simulated export failure'}
        }
    } $source
    New-BastosDriverBackup -Root $root -Selected $false
    Check ((Get-Content (Join-Path $root 'BASTOS-DRIVERS.enabled') -Raw).Trim() -eq '0') 'Unchecked option writes explicit opt-out'
    Check ((& $module {$script:ExportCalls}) -eq 0) 'Unchecked option never exports'
    $manifest=New-BastosDriverBackup -Root $root -Selected $true -SetupPath 'fixture'
    Check ($manifest.InfCount -eq 1 -and @($manifest.Files).Count -eq 3) 'Whole INF SYS CAT package exported'
    $active=Join-Path $root 'BASTOS-Drivers\Active'
    Check ((Test-BastosDriverBackup -Directory $active).InfCount -eq 1) 'Saved manifest independently rehashed'
    Check ((Get-Content (Join-Path $root 'BASTOS-DRIVERS.enabled') -Raw).Trim() -eq '1') 'Selection published after verification'
    $before=(Get-FileHash (Join-Path $active 'Manifest.json')).Hash
    & $module {$script:FailExport=$true}
    Refuses {New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture} 'Export failure blocks operation'
    Check ((Get-FileHash (Join-Path $active 'Manifest.json')).Hash -eq $before) 'Previous backup retained after failed export'
    Check (@(Get-ChildItem (Join-Path $root 'BASTOS-Drivers') -Filter 'Staging-*').Count -eq 0) 'Failed staging cleaned'
    & $module {$script:FailExport=$false}
    New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture|Out-Null
    Check (@(Get-ChildItem (Join-Path $root 'BASTOS-Drivers') -Filter 'Previous-*').Count -eq 0) 'Old backup cleaned only after successful publication'
    New-BastosDriverBackup -Root $root -Selected $false
    Check ([IO.File]::Exists((Join-Path $active 'Manifest.json'))) 'Opt-out keeps backup files for manual recovery'
    Check ((Get-Content (Join-Path $root 'BASTOS-DRIVERS.enabled') -Raw).Trim() -eq '0') 'Opt-out cannot leak old drivers into Setup'
    [IO.File]::AppendAllText((Join-Path $active 'Packages\audio\audio.sys'),'tampered')
    Refuses {Test-BastosDriverBackup -Directory $active} 'Changed driver bytes rejected'
    New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture|Out-Null
    [IO.File]::WriteAllText((Join-Path $active 'Packages\unexpected.inf'),'extra')
    Refuses {Test-BastosDriverBackup -Directory $active} 'Unlisted driver rejected'
    New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture|Out-Null
    Remove-Item -LiteralPath (Join-Path $active 'Packages\audio\audio.cat') -Force
    Refuses {Test-BastosDriverBackup -Directory $active} 'Missing catalog rejected'
    & $module {$script:Unsupported=$true}
    $calls=& $module {$script:ExportCalls}
    Refuses {New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture} 'Unsupported Windows Setup rejected before export'
    Check ((& $module {$script:ExportCalls}) -eq $calls) 'Unsupported target does not export'
    & $module {$script:Unsupported=$false;$script:Empty=$true}
    $empty=New-BastosDriverBackup -Root $root -Selected $true -SetupPath fixture
    Check ($empty.InfCount -eq 0 -and @($empty.Files).Count -eq 0) 'Empty third-party store explicitly represented'
    Check ((Test-BastosDriverBackup -Directory $active).InfCount -eq 0) 'Empty inventory verified'
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'InstallerScripts\Initialize-BASTOS-Recovery.ps1'),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'Worker syntax valid in Windows PowerShell 5.1'
    $batch=[IO.File]::ReadAllText((Join-Path $SourceRoot 'InstallerScripts\BASTOS-Start.cmd'))
    Check ($batch -notmatch '(?<!\r)\n' -and $batch -match '\r\n') 'WinPE launcher remains ASCII CRLF'
    Check ($batch.IndexOf('set "BASTOS_DRIVER_ARGS="') -lt $batch.IndexOf('set "BASTOS_PRECHECKS_COMPLETED=1"')) 'Driver presence checked before destructive authorization'
    Check (([regex]::Matches($batch,'/InstallFrom "%BASTOS_IMAGE%" !BASTOS_DRIVER_ARGS!')).Count -eq 2) 'Setup receives drivers with and without CopyLogs'
    Check ($batch -notmatch '(?i)forceunsigned|drvload') 'No unsigned override or initial WinPE force-loading'
    $begin=$batch.IndexOf('rem Drivers are supplied to Setup')
    $end=$batch.IndexOf('echo Tous les precontroles ont reussi',$begin)
    $precheck=$batch.Substring($begin,$end-$begin)
    Check ($batch -notmatch '(?im)^\s*findstr(?:\.exe)?\s') 'Launcher has no findstr dependency in minimal WinPE'
    $testBatch=Join-Path $temp 'Driver-handoff.cmd'
    $content='@echo off'+"`r`n"+'setlocal EnableExtensions EnableDelayedExpansion'+"`r`n"+'set "PATH="'+"`r`n"+'set "BASTOS_MEDIA='+$root+'"'+"`r`n"+$precheck+"`r`n"+'echo SETUP !BASTOS_DRIVER_ARGS!'+"`r`n"+'exit /b 0'+"`r`n"+':SAFE_REBOOT'+"`r`n"+'echo BLOCK_CODE=!BASTOS_EXIT_CODE!'+"`r`n"+'exit /b 77'+"`r`n"
    [IO.File]::WriteAllText($testBatch,$content,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),"0`r`n")
    $result=& $env:ComSpec /d /c $testBatch
    Check ($LASTEXITCODE -eq 0 -and ($result -join '') -notmatch '/InstallDrivers') 'Actual cmd precheck omits drivers when disabled'
    [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),"1`r`n")
    [IO.File]::WriteAllText((Join-Path $active 'Packages\test.inf'),'fixture')
    $result=& $env:ComSpec /d /c $testBatch
    Check ($LASTEXITCODE -eq 0 -and ($result -join '') -match '/InstallDrivers "[^"\r\n]+\\Packages"') 'Actual cmd precheck builds quoted Setup argument'
    foreach($value in @('0','1')){
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),$value)
        $result=& $env:ComSpec /d /c $testBatch
        Check ($LASTEXITCODE -eq 0 -and (($result -join '') -match '/InstallDrivers') -eq ($value -eq '1')) ('Single-byte marker accepted without external tools: '+$value)
    }
    foreach($value in @('',"`r`n",'2',"1`r`n0`r`n","1`nx",' 1','1 ','invalid')){
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),$value)
        $result=& $env:ComSpec /d /c $testBatch
        Check ($LASTEXITCODE -eq 77 -and ($result -join '') -match 'BLOCK_CODE=81') 'Empty, malformed or multiline marker rejected without external tools'
    }
    [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),"1`r`n")
    Remove-Item -LiteralPath (Join-Path $active 'Manifest.json') -Force
    $null=& $env:ComSpec /d /c $testBatch
    Check ($LASTEXITCODE -eq 77) 'Actual WinPE precheck blocks missing backup before destructive phase'
    [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DRIVERS.enabled'),"invalid`r`n")
    $null=& $env:ComSpec /d /c $testBatch
    Check ($LASTEXITCODE -eq 77) 'Actual WinPE precheck blocks invalid marker'
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture outside TEMP'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Remove-Module $module.Name -Force
}
Write-Output "PASS : $count driver backup checks; export mocked, no driver installed."
