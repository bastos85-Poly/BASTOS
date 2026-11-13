param([string]$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $SourceRoot 'InstallerScripts\Manage-BASTOS-InterruptAffinity.ps1'
$global:BASTOS_AFFINITY_TEST_CPU = $null
function Get-CimInstance {
    param([string]$ClassName)
    if ($ClassName -ne 'Win32_Processor') { throw "Unexpected CIM query: $ClassName" }
    return $global:BASTOS_AFFINITY_TEST_CPU
}
function Assert-Plan([string]$profile,[string]$name,[int]$cores,[int]$threads,[string]$gpu,[string]$usb,[string]$network,[string]$audio) {
    $global:BASTOS_AFFINITY_TEST_CPU = [pscustomobject]@{ Name=$name; NumberOfCores=$cores; NumberOfLogicalProcessors=$threads }
    $report = & $scriptPath -Action Plan -Profile $profile | ConvertFrom-Json
    if (-not $report.Success -or $report.Masks.GPU -ne $gpu -or $report.Masks.USB -ne $usb -or
        $report.Masks.NETWORK -ne $network -or $report.Masks.AUDIO -ne $audio) {
        throw "Unexpected $profile plan: $($report | ConvertTo-Json -Compress)"
    }
}
Assert-Plan X3D 'AMD Ryzen 7 9800X3D' 8 16 '1000000000000000' '4000000000000000' '0001000000000000' '0004000000000000'
Assert-Plan SixCore 'AMD Ryzen 5 9600X' 6 12 '1000000000000000' '4000000000000000' '0001000000000000' '0001000000000000'
Assert-Plan DualCcd 'AMD Ryzen 9 9950X3D' 16 32 '0000010000000000' '0000040000000000' '0000100000000000' '0000400000000000'
Assert-Plan Intel 'Intel Core i7-12700K' 8 16 '1000000000000000' '4000000000000000' '0001000000000000' '0004000000000000'
$global:BASTOS_AFFINITY_TEST_CPU = [pscustomobject]@{ Name='Intel Core i7-14700K'; NumberOfCores=20; NumberOfLogicalProcessors=28 }
$hybrid = & $scriptPath -Action Plan -Profile Intel | ConvertFrom-Json
if ($hybrid.Success -or $hybrid.Message -notmatch 'hybride') { throw 'Hybrid CPU must be refused.' }
Write-Output 'PASS : 4 profils et refus de topologie hybride ; aucune modification Windows.'
