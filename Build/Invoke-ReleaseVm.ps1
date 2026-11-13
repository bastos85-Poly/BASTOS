param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$CandidateRoot,[Parameter(Mandatory)][string]$RuntimeRoot,[Parameter(Mandatory)][string]$DotNetPath,[Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SourceRoot 'Tests/VmLab/Bastos.VmLab.psm1') -Force
$plan=Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json
$authorization=Read-BastosLabAuthorization $plan (Join-Path $plan.Directory 'LabAuthorization.json')
function Assert-Lab {
 $script:vm=Get-VM -Id $plan.VmId
  $drives=@(Get-VMHardDiskDrive -VMName $plan.Name)
 $null=Assert-BastosVmIsolation $plan $vm $drives @(Get-VMNetworkAdapter -VM $vm)
}
Assert-Lab
if([string]$vm.State -ne 'Off'){throw 'Arreter la VM de laboratoire avant la validation.'}
$baseline=@(Get-VMSnapshot -VM $vm|Where-Object Id -eq $authorization.BaselineId)
if($baseline.Count -ne 1){throw 'Baseline connue absente.'}
$returnPoint=Checkpoint-VM -VM $vm -SnapshotName ('ReleaseReturn-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')) -Passthru
$session=$null
$run=[guid]::NewGuid().ToString('N')
$evidence=Join-Path $OutputDirectory 'VM';New-Item -ItemType Directory $evidence -Force|Out-Null
try {
 Restore-VMSnapshot -VMSnapshot $baseline[0] -Confirm:$false
 Assert-Lab
 Set-VM -VM $vm -AutomaticCheckpointsEnabled $false
 Enable-VMIntegrationService -VM $vm -Name 'Guest Service Interface'
 Start-VM -VM $vm
 $credential=Import-Clixml (Join-Path $plan.Directory 'GuestCredential.clixml')
 $until=[DateTime]::UtcNow.AddMinutes(3)
 do {try{$session=New-PSSession -VMId $plan.VmId -Credential $credential -ErrorAction Stop}catch{Start-Sleep -Seconds 3}}while(-not $session -and [DateTime]::UtcNow -lt $until)
 if(-not $session){throw 'Connexion a la baseline impossible.'}
 $valid=Invoke-Command -Session $session -ArgumentList $plan.LabId -ScriptBlock {param($id);$pc=Get-CimInstance Win32_ComputerSystem;$pc.Model -eq 'Virtual Machine' -and $pc.Manufacturer -eq 'Microsoft Corporation' -and $env:COMPUTERNAME -eq 'BASTOS-VMLAB' -and (Get-Content D:\BASTOS-VM-KEEP.txt -Raw) -eq $id -and @(Get-Disk).Count -eq 1}
 if(-not $valid){throw 'Identite invitee divergente.'}
 $manifest=Get-Content (Join-Path $CandidateRoot 'BASTOS-App-Manifest.json') -Raw|ConvertFrom-Json
 $files=@($manifest.Files)
 $remote=Invoke-Command -Session $session -ArgumentList (,$files.Path) -ScriptBlock {param($paths);foreach($relative in $paths){$p=Join-Path D:\Application $relative;if(Test-Path -LiteralPath $p -PathType Leaf){[pscustomobject]@{Path=$relative;Hash=(Get-FileHash -LiteralPath $p).Hash}}}}
 $hashes=@{};foreach($item in $remote){$hashes[$item.Path]=$item.Hash}
 foreach($file in $files){
  if($hashes[$file.Path] -eq $file.Sha256){continue}
  if([IO.Path]::IsPathRooted($file.Path) -or $file.Path.Split('\') -contains '..'){throw 'Chemin de paquet refuse.'}
  $from=Join-Path $CandidateRoot $file.Path;if(-not(Test-Path -LiteralPath $from)){$from=Join-Path $RuntimeRoot $file.Path}
  if((Get-FileHash -LiteralPath $from).Hash -ne $file.Sha256){throw ('Fichier candidat divergent : '+$file.Path)}
  $parent=Split-Path -Parent ('D:\Application\'+$file.Path)
  Invoke-Command -Session $session -ArgumentList $parent -ScriptBlock {param($p);New-Item -ItemType Directory $p -Force|Out-Null}
  Copy-Item -ToSession $session -LiteralPath $from -Destination ('D:\Application\'+$file.Path) -Force
 }
 foreach($meta in @('BASTOS-App-Manifest.json','BASTOS-Build.json')){Copy-Item -ToSession $session -LiteralPath (Join-Path $CandidateRoot $meta) -Destination ('D:\Application\'+$meta) -Force}
 Invoke-Command -Session $session -ArgumentList $run -ScriptBlock {param($id);New-Item -ItemType Directory D:\VM-Test-Results -Force|Out-Null;[IO.File]::WriteAllText('D:\VM-Test-Results\ReleaseRun.txt',$id)}
 $harness=Join-Path $SourceRoot 'Tests/VmLab/Harness/Harness.csproj'
 $harnessOut=Join-Path $OutputDirectory 'harness'
 & $DotNetPath publish $harness -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true "-p:BastosSourceRoot=$SourceRoot" -o $harnessOut *> (Join-Path $evidence 'harness-build.log')
 if($LASTEXITCODE -ne 0){throw 'Compilation du banc VM echouee.'}
 Copy-Item -ToSession $session -LiteralPath (Join-Path $harnessOut 'BASTOS-VM-Test.exe') -Destination D:\Application\Bastos.Native\BASTOS-VM-Test.exe -Force
 Write-Output 'VM : preparation Recovery avec le moteur candidat...'
 Invoke-Command -Session $session -ArgumentList $plan.LabId -ScriptBlock {param($id);& D:\Application\Bastos.Native\BASTOS-VM-Test.exe prepare-keep-efi $id *> D:\VM-Test-Results\prepare-console.log;if($LASTEXITCODE -ne 0){Get-Content D:\VM-Test-Results\prepare-console.log -Tail 20;throw 'Preparation refusee.'}}
 $beforeEvidence=Join-Path $evidence 'VM-Test-Results';New-Item -ItemType Directory $beforeEvidence -Force|Out-Null
 Copy-Item -FromSession $session -Path D:\VM-Test-Results\* -Destination $beforeEvidence -Force
 Write-Output 'VM : demarrage Recovery et reinstallation complete...'
 Invoke-Command -Session $session -ArgumentList $plan.LabId -ScriptBlock {param($id);& D:\Application\Bastos.Native\BASTOS-VM-Test.exe boot $id *> D:\VM-Test-Results\boot-console.log;if($LASTEXITCODE -ne 0){throw 'Demarrage Recovery refuse.'}}
 Remove-PSSession $session;$session=$null
 # No shutdown request is sent while Windows Setup or first logon is running.
 $before=Get-Content (Join-Path $beforeEvidence 'disk-before.json') -Raw|ConvertFrom-Json
 $snapshot=$before.DiskSnapshot|ConvertFrom-Json
 $oldWindows=@($before.Partitions|Where-Object Location -eq 'C:')[0].Guid
 $oldEfi=@($snapshot.Disks.WindowsDisk.Partitions|Where-Object GptType -eq 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B')[0].Guid
 $build=Get-Content (Join-Path $CandidateRoot 'BASTOS-Build.json') -Raw|ConvertFrom-Json
 $expected=@{LabId=$plan.LabId;RunId=$run;CandidateSha256=$build.NativeAppSha256;RecoveryGuid=$before.PartitionGuid;OldWindowsGuid=$oldWindows;OldEfiGuid=$oldEfi;KeepEfi=$true;DesktopObserved=$true;RequireFirstLogon=$true}
 $expectedPath=Join-Path $evidence 'Expected.json';$expected|ConvertTo-Json|Set-Content $expectedPath -Encoding UTF8
 $linkPath=Join-Path $evidence 'BASTOS-VmLabProbe.lnk'
 $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($linkPath)
 $link.TargetPath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';$link.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\VM-Lab\VerifyInstalled.ps1"';$link.WorkingDirectory='C:\VM-Lab';$link.WindowStyle=7;$link.Save()
 $until=[DateTime]::UtcNow.AddMinutes(20);$seenRecovery=$false;$copied=$false;$lastError=''
 while([DateTime]::UtcNow -lt $until){
  Start-Sleep -Seconds 3
  Assert-Lab
  $heartbeat=Get-VMIntegrationService -VM $vm -Name Heartbeat
  if([string]$heartbeat.PrimaryStatusDescription -ne 'OK'){$seenRecovery=$true;continue}
  if(-not $seenRecovery){continue}
  try {
   Copy-VMFile -VM $vm -SourcePath $expectedPath -DestinationPath C:\VM-Lab\Expected.json -FileSource Host -CreateFullPath -Force -ErrorAction Stop
   Copy-VMFile -VM $vm -SourcePath (Join-Path $SourceRoot 'Tests/VmLab/Verify-InstalledWindows.ps1') -DestinationPath C:\VM-Lab\VerifyInstalled.ps1 -FileSource Host -CreateFullPath -Force -ErrorAction Stop
   Copy-VMFile -VM $vm -SourcePath $linkPath -DestinationPath 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\BASTOS-VmLabProbe.lnk' -FileSource Host -CreateFullPath -Force -ErrorAction Stop
   $copied=$true;Write-Output 'VM : sonde transmise via Hyper-V, attente de la premiere session...';break
  } catch {$lastError=$_.Exception.Message}
 }
 if(-not $copied){throw ('Transfert de la sonde impossible : '+$lastError)}
 $until=[DateTime]::UtcNow.AddMinutes(12)
 while([string](Get-VM -Id $plan.VmId).State -ne 'Off' -and [DateTime]::UtcNow -lt $until){Start-Sleep -Seconds 5}
 if([string](Get-VM -Id $plan.VmId).State -ne 'Off'){throw 'Sonde de premiere session non terminee : aucune extinction intermediaire forcee.'}
 & (Join-Path $SourceRoot 'Tests/VmLab/Invoke-OfflineVmProbe.ps1') -Action Collect -Scenario KeepEFI -PlanPath $PlanPath -EvidenceRoot $evidence -CandidateRoot $CandidateRoot
 $proof=Get-Content (Join-Path $evidence 'VM-Test-Results/PostInstallProbe.json') -Raw|ConvertFrom-Json
 $receipt=(Get-Content (Join-Path $evidence 'VM-Test-Results/ReleaseRun.txt') -Raw)
 if(-not $proof.Passed -or $receipt -ne $run -or $proof.RunId -ne $run){throw 'Preuve VM absente, negative ou ancienne.'}
 [pscustomobject]@{Passed=$true;RunId=$run;VmId=$plan.VmId;Checks=$proof.Checks}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $evidence 'Result.json') -Encoding UTF8
} finally {
 if($session){Remove-PSSession $session}
 Assert-Lab
 if([string]$vm.State -ne 'Off'){Stop-VM -VM $vm -TurnOff -Confirm:$false}
 Restore-VMSnapshot -VMSnapshot $returnPoint -Confirm:$false
 Assert-Lab
 Write-Output 'VM : etat anterieur restaure, VM arretee.'
}
