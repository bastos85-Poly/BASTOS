param([string]$SourceRoot = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$worker = Join-Path $SourceRoot 'InstallerScripts\Initialize-BASTOS-Recovery.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($worker, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Le script Recovery contient une erreur de syntaxe.' }
$statusBody = $null
foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst]}, $true)) {
    foreach ($clause in $node.Clauses) {
        if ($clause.Item1.Extent.Text -eq '$Action -eq ''Status''') { $statusBody = $clause.Item2.Extent.Text }
    }
}
if (-not $statusBody) { throw 'Branche Status introuvable.' }
$statusBody = $statusBody.Substring(1, $statusBody.Length - 2) -replace '(?m)^\s*exit 0\s*$', ''
$status = [scriptblock]::Create($statusBody)

function Get-PartitionSupportedSize {
    param($DiskNumber, $PartitionNumber, $ErrorAction)
    $script:shrinkQueries++
    [pscustomobject]@{SizeMin = $script:minimumSize}
}
function Get-Volume {
    param($DriveLetter, $ErrorAction)
    if ($DriveLetter -eq 'D') { return $null }
    [pscustomobject]@{SizeRemaining = 100GB}
}
function Save-Result {
    param([bool]$Success, [string]$Message, [hashtable]$Extra)
    $script:lastResult = [pscustomobject]@{Success = $Success; Message = $Message; Extra = $Extra}
}
function Run-Case([long]$FreeExtent, [long]$MinimumSize) {
    $script:minimumSize = $MinimumSize
    $script:shrinkQueries = 0
    $script:lastResult = $null
    $script:layout = [pscustomobject]@{
        RecoveryPartitions = @()
        TargetIsWindowsDisk = $true
        WindowsDisk = [pscustomobject]@{Number = 0; FriendlyName = 'Fixture'; Size = 1000GB}
        InstallDisk = [pscustomobject]@{Number = 0; FriendlyName = 'Fixture'; Size = 1000GB}
        TargetDisk = [pscustomobject]@{Number = 0; FriendlyName = 'Fixture'; Size = 1000GB; LargestFreeExtent = $FreeExtent}
        OsPartition = [pscustomobject]@{Number = 2; PartitionNumber = 2; Size = 900GB; DriveLetter = 'C'}
        EfiPartitions = @([pscustomobject]@{PartitionNumber = 1})
        SelectionSource = 'AutomaticWindowsDisk'
        WindowsDiskIdentity = 'fixture'
        InstallDiskIdentity = 'fixture'
        TargetDiskIdentity = 'fixture'
        InstallIsCurrentWindowsDisk = $true
        RecoveryIsInstallDisk = $true
    }
    $script:RecoverySizeGB = 40
    $script:RecoveryMode = 'Novice'
    & $status
    if (-not $script:lastResult) { throw 'Aucun rapport produit.' }
    return [pscustomobject]@{Report = $script:lastResult; ShrinkQueries = $script:shrinkQueries}
}

$preallocated = Run-Case 45GB 890GB
if (-not $preallocated.Report.Success -or
    $preallocated.Report.Extra.ProvisionMethod -ne 'UseUnallocatedSpace' -or
    $preallocated.ShrinkQueries -ne 0) {
    throw '40 Go deja non alloues doivent eviter la reduction de C:.'
}
$blocked = Run-Case 0 880GB
if ($blocked.Report.Success -or
    $blocked.Report.Extra.ProvisionMethod -ne 'ShrinkWindows' -or
    $blocked.Report.Extra.MaximumShrinkBytes -ne 20GB) {
    throw 'Reduction de C: insuffisante aurait du etre refusee.'
}
$shrinkable = Run-Case 0 850GB
if (-not $shrinkable.Report.Success -or
    $shrinkable.Report.Extra.ProvisionMethod -ne 'ShrinkWindows' -or
    $shrinkable.ShrinkQueries -ne 1) {
    throw 'Reduction de C: suffisante aurait du etre admise.'
}

$provisionBody = $null
foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst]}, $true)) {
    foreach ($clause in $node.Clauses) {
        if ($clause.Item1.Extent.Text -eq '-not $recoveryPartition' -and
            $clause.Item2.Extent.Text.Contains('New-Partition -DiskNumber')) {
            $provisionBody = $clause.Item2.Extent.Text
        }
    }
}
if (-not $provisionBody) { throw 'Branche de creation Recovery introuvable.' }
$provision = [scriptblock]::Create($provisionBody.Substring(1, $provisionBody.Length - 2))
function Assert-RecoveryStorageCheckpoint { return $script:layout }
function Assert-RecoveryWriteTarget { param($Partition) }
function Resize-Partition { throw 'C: ne doit pas etre reduit avec 40 Go non alloues.' }
function New-Partition {
    param($DiskNumber, $Size, $DriveLetter)
    $script:newPartitionCalls++
    $script:newPartitionLetter = $DriveLetter
    [pscustomobject]@{DiskNumber = $DiskNumber; Size = $Size; DriveLetter = $DriveLetter}
}
function Format-Volume { param($Partition, $FileSystem, $NewFileSystemLabel, [switch]$Confirm, [switch]$Force) }
$script:layout.TargetDisk.LargestFreeExtent = 45GB
$script:required = 40GB
$script:recoveryPartition = $null
$script:recoveryLabel = 'BASTOS_RECOVERY'
$script:newPartitionCalls = 0
$script:newPartitionLetter = ''
& $provision
if ($script:newPartitionCalls -ne 1 -or $script:newPartitionLetter -ne 'D') {
    throw 'La preparation doit creer D: directement dans les 40 Go non alloues.'
}
'PASS : espace non alloue, reduction insuffisante, reduction suffisante et preparation sans reduction.'
