param([Parameter(Mandatory)][ValidateSet('Collect')][string]$Action,[ValidateSet('RecreateEFI','KeepEFI')][string]$Scenario='KeepEFI',[Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$CandidateRoot,[switch]$DiagnosticsOnly)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.VmLab.psm1') -Force
$plan=Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json
$vm=Get-VM -Id $plan.VmId
$null=Read-BastosLabAuthorization $plan (Join-Path $plan.Directory 'LabAuthorization.json')
$drives=@(Get-BastosVmDiskDrives -VmName $plan.Name)
$null=Assert-BastosVmIsolation $plan $vm $drives @(Get-VMNetworkAdapter -VM $vm)
if([string]$vm.State -ne 'Off'){throw 'La VM doit etre arretee par la sonde.'}
$current=$drives[0].Path
$beforeRoot=if($DiagnosticsOnly){Split-Path -Parent $EvidenceRoot}else{$EvidenceRoot}
$before=Get-Content (Join-Path $beforeRoot 'VM-Test-Results/disk-before.json') -Raw|ConvertFrom-Json
New-Item -ItemType Directory $EvidenceRoot -Force|Out-Null
Mount-VHD -Path $current -ReadOnly -NoDriveLetter|Out-Null
$mounts=@()
try{
 $disk=Get-Disk -Number (Get-VHD -Path $current).DiskNumber
 $hostSystemDiskNumbers=@(Get-Partition | Where-Object { $_.DriveLetter -in @('C','D') } | ForEach-Object DiskNumber)
 if(-not $disk.IsReadOnly -or $disk.IsBoot -or $disk.IsSystem -or $disk.Number -in $hostSystemDiskNumbers){throw 'Disque hote ou non protege refuse.'}
 $disk|Select-Object Number,UniqueId,Size,IsReadOnly,IsOffline,BusType|ConvertTo-Json|Set-Content (Join-Path $EvidenceRoot 'DiskInventory.json') -Encoding UTF8
 if($disk.IsOffline){Set-Disk -Number $disk.Number -IsOffline $false; $disk=Get-Disk -Number $disk.Number;if(-not $disk.IsReadOnly){throw 'Protection lecture seule perdue.'}}
 $parts=@(Get-Partition -DiskNumber $disk.Number)
 $parts|Select-Object PartitionNumber,Guid,GptType,Size,Offset|ConvertTo-Json -Depth 4|Set-Content (Join-Path $EvidenceRoot 'PartitionInventory.json') -Encoding UTF8
 if($DiagnosticsOnly){
  foreach($part in $parts|Where-Object {[guid]$_.GptType -eq [guid]'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'}){
   $path=Join-Path $plan.Directory ('DiagnosticPartition-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $path|Out-Null
   Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath ($path+'\')
   $mounts+=@{Path=$path;Partition=$part.PartitionNumber}
   $target=Join-Path $EvidenceRoot ('Partition-'+$part.PartitionNumber);New-Item -ItemType Directory $target|Out-Null
   foreach($relative in @('VM-Test-Results','VM-Lab','BASTOS-Diagnostics','BASTOS-LAST-ERROR.txt','BASTOS-LAST-ATTEMPT.txt','BASTOS-Recovery.log','BASTOS-Minimal-Offline.json','ProgramData/BASTOS-ISO/Logs','ProgramData/BASTOS-ISO/Installation-Expected.json','Windows/Panther','Windows/Logs/MoSetup')){
    $from=Join-Path $path $relative
    if(Test-Path -LiteralPath $from){$dest=Join-Path $target $relative;New-Item -ItemType Directory (Split-Path -Parent $dest) -Force|Out-Null;Copy-Item -LiteralPath $from -Destination $dest -Recurse -Force}
   }
  }
  Write-Output 'Diagnostics prives collectes apres echec ; aucune validation de livraison.';return
 }
 $expected=Get-Content (Join-Path $EvidenceRoot 'Expected.json') -Raw|ConvertFrom-Json
 if($expected.RecoveryFinalized -ne $true){throw 'Scenario de finalisation automatique non confirme.'}
 $selected=Get-BastosVmEvidencePartitions $parts ([guid]$before.PartitionGuid) -RecoveryFinalized
 foreach($item in @(@{Name='ReleaseEvidenceWindows';Partition=$selected.Windows})){
  $path=Join-Path $plan.Directory ($item.Name+'-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $path|Out-Null
  Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $item.Partition.PartitionNumber -AccessPath ($path+'\')
  $mounts+=@{Path=$path;Partition=$item.Partition.PartitionNumber}
 }
 $w=$mounts[0].Path
 foreach($path in @('ProgramData/BASTOS-ISO/Logs','Windows/Panther')){$from=Join-Path $w $path;if(Test-Path $from){Copy-Item -LiteralPath $from -Destination $EvidenceRoot -Recurse -Force}}
 Copy-Item -LiteralPath (Join-Path $w 'ProgramData/BASTOS-ISO/Installation-Expected.json') -Destination (Join-Path $EvidenceRoot 'Installation-Expected.json') -Force
 Copy-Item -LiteralPath (Join-Path $w 'VM-Lab/PostInstallProbe.json') -Destination (Join-Path $EvidenceRoot 'VM-Test-Results/PostInstallProbe.json') -Force
 $proof=Get-Content (Join-Path $EvidenceRoot 'VM-Test-Results/PostInstallProbe.json') -Raw|ConvertFrom-Json
 $proof|ConvertTo-Json -Depth 8
 $required=@('CandidateOnWindows','WindowsPro','ComputerName','LocalUser','Passwordless','French','Azerty','DesktopObserved','SingleVirtualDisk','TemporaryRecoveryRemoved','SpaceReturnedToWindows','WindowsRecreated','EfiPolicy','FirstLogonComplete','DesktopShortcut','DesktopShortcutTarget','FinalizationVerified','HiddenWinRE','WinREImageVerified','InstallationReportMatchesProfile','InstallationReportConformity')
 if($proof.Schema -ne 2 -or $proof.Passed -ne $true -or $proof.RunId -ne $expected.RunId -or $proof.NativeProbeSha256 -ne $expected.NativeProbeSha256 -or @($proof.Checks.PSObject.Properties).Count -ne $required.Count){throw 'Verification finale invitee negative ou incoherente.'}
 foreach($name in $required){if(-not $proof.Checks.PSObject.Properties[$name] -or $proof.Checks.$name -ne $true){throw ('Controle VM absent ou negatif : '+$name)}}
}finally{foreach($m in $mounts){Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $m.Partition -AccessPath ($m.Path+'\')};Dismount-VHD -Path $current}
