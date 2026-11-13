param([Parameter(Mandatory)][ValidateSet('Collect')][string]$Action,[ValidateSet('RecreateEFI','KeepEFI')][string]$Scenario='KeepEFI',[Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$CandidateRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.VmLab.psm1') -Force
$plan=Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json
$vm=Get-VM -Id $plan.VmId
$null=Read-BastosLabAuthorization $plan (Join-Path $plan.Directory 'LabAuthorization.json')
$drives=@(Get-VMHardDiskDrive -VMName $plan.Name)
$null=Assert-BastosVmIsolation $plan $vm $drives @(Get-VMNetworkAdapter -VM $vm)
if([string]$vm.State -ne 'Off'){throw 'La VM doit etre arretee par la sonde.'}
$current=$drives[0].Path
$before=Get-Content (Join-Path $EvidenceRoot 'VM-Test-Results/disk-before.json') -Raw|ConvertFrom-Json
Mount-VHD -Path $current -ReadOnly -NoDriveLetter|Out-Null
$mounts=@()
try{
 $disk=Get-Disk -Number (Get-VHD -Path $current).DiskNumber
 if(-not $disk.IsReadOnly -or $disk.IsBoot -or $disk.IsSystem -or $disk.Number -in @(Get-Partition -DriveLetter C,D|ForEach-Object DiskNumber)){throw 'Disque hote ou non protege refuse.'}
 $parts=@(Get-Partition -DiskNumber $disk.Number)
 $recovery=@($parts|Where-Object {[guid]$_.Guid -eq [guid]$before.PartitionGuid});$windows=@($parts|Where-Object {$_.Size -gt 64GB -and [guid]$_.Guid -ne [guid]$before.PartitionGuid -and $_.GptType -eq '{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}'})
 if($recovery.Count -ne 1 -or $windows.Count -ne 1){throw 'Partitions virtuelles ambigues.'}
 foreach($item in @(@{Name='ReleaseEvidenceRecovery';Partition=$recovery[0]},@{Name='ReleaseEvidenceWindows';Partition=$windows[0]})){
  $path=Join-Path $plan.Directory $item.Name;New-Item -ItemType Directory $path -Force|Out-Null
  Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $item.Partition.PartitionNumber -AccessPath ($path+'\')
  $mounts+=@{Path=$path;Partition=$item.Partition.PartitionNumber}
 }
 $r=$mounts[0].Path;$w=$mounts[1].Path
 if((Get-Content (Join-Path $r 'BASTOS-VM-KEEP.txt') -Raw) -ne $plan.LabId){throw 'Temoin invite divergent.'}
 foreach($name in @('VM-Test-Results','BASTOS-Diagnostics','BASTOS-LAST-ERROR.txt','BASTOS-LAST-ATTEMPT.txt','BASTOS-Recovery.log')){
  $path=Join-Path $r $name;if(Test-Path -LiteralPath $path){$target=Join-Path $EvidenceRoot $name;if((Get-Item $path).PSIsContainer){New-Item -ItemType Directory $target -Force|Out-Null;Get-ChildItem -LiteralPath $path -Force|Copy-Item -Destination $target -Recurse -Force}else{Copy-Item -LiteralPath $path -Destination $target -Force}}
 }
 foreach($path in @('ProgramData/BASTOS-ISO/Logs','Windows/Panther')){$from=Join-Path $w $path;if(Test-Path $from){Copy-Item -LiteralPath $from -Destination $EvidenceRoot -Recurse -Force}}
 $proof=Get-Content (Join-Path $EvidenceRoot 'VM-Test-Results/PostInstallProbe.json') -Raw|ConvertFrom-Json
 $proof|ConvertTo-Json -Depth 8
 if($proof.Passed -ne $true){throw 'Verification finale invitee negative.'}
}finally{foreach($m in $mounts){Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $m.Partition -AccessPath ($m.Path+'\')};Dismount-VHD -Path $current}
