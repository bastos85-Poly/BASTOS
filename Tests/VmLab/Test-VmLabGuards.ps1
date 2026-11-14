$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.VmLab.psm1') -Force
$count=0
function Check([bool]$Ok,[string]$Name){if(-not $Ok){throw ('FAIL : '+$Name)};$script:count++;'OK : '+$Name}
function Refused([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Name}
$root=Join-Path $env:TEMP ('Bastos-VmLab-Tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$plan=New-BastosVmPlan -LabRoot $root -IsoPath 'C:\Test\Windows.iso'
Check ($plan.Generation -eq 2 -and $plan.MemoryBytes -eq 8GB -and $plan.DiskBytes -eq 180GB) 'Configuration UEFI 8 Go et disque virtuel 180 Go'
Check ($plan.Network -eq 'Disconnected' -and -not $plan.PhysicalDisks -and -not $plan.AutoStart) 'Aucun reseau, disque physique ni demarrage automatique'
Check ((New-BastosVmPlan -LabRoot $root -IsoPath 'C:\Test\Windows.iso').Directory -ne $plan.Directory) 'Dossier unique par laboratoire'
Refused {New-BastosVmPlan -LabRoot 'D:\Laboratoire' -IsoPath 'C:\Test\Windows.iso'} 'Laboratoire sur le lecteur Recovery refuse'
Refused {New-BastosVmPlan -LabRoot 'C:\' -IsoPath 'C:\Test\Windows.iso'} 'Racine de lecteur refusee'
Refused {New-BastosVmPlan -LabRoot '\\server\share\Lab' -IsoPath 'C:\Test\Windows.iso'} 'Partage reseau refuse'
Refused {New-BastosVmPlan -LabRoot $root -IsoPath 'C:\Test\Windows.vhdx'} 'Fichier non ISO refuse'
Refused {Assert-BastosLabPath $root ($root+'-autre\disk.vhdx')} 'Prefixe ressemblant refuse'
Refused {Assert-BastosLabPath $root (Join-Path $root '..\autre\disk.vhdx')} 'Sortie du dossier par points refuses'
Refused {Assert-BastosLabPath $root '\\.\PhysicalDrive0'} 'Disque physique refuse comme chemin'
$vmId=[guid]::NewGuid().ToString();$plan.VmId=$vmId
$vm=[pscustomobject]@{Id=$vmId;Name=$plan.Name;Generation=2}
$drive=[pscustomobject]@{Path=$plan.DiskPath;DiskNumber=$null}
Check (Assert-BastosVmIsolation $plan $vm @($drive)) 'Identite et unique VHDX verifies'
Refused {Assert-BastosVmIsolation $plan $vm @()} 'Aucun disque refuse'
Refused {Assert-BastosVmIsolation $plan $vm @($drive,$drive)} 'Deux disques refuses'
Refused {Assert-BastosVmIsolation $plan $vm @([pscustomobject]@{Path=$plan.DiskPath;DiskNumber=0})} 'Passage disque physique refuse'
Refused {Assert-BastosVmIsolation $plan $vm @([pscustomobject]@{Path='C:\Autre.vhdx';DiskNumber=$null})} 'VHDX externe refuse'
Refused {Assert-BastosVmIsolation $plan $vm @($drive) @([pscustomobject]@{Name='Reseau'})} 'Carte reseau meme deconnectee refusee'
Refused {Assert-BastosVmIsolation $plan ([pscustomobject]@{Id=[guid]::NewGuid().ToString();Name=$plan.Name;Generation=2}) @($drive)} 'Autre VM refusee'
Refused {Assert-BastosVmIsolation $plan ([pscustomobject]@{Id=$vmId;Name='Autre';Generation=2}) @($drive)} 'Nom divergent refuse'
Refused {Assert-BastosVmIsolation $plan ([pscustomobject]@{Id=$vmId;Name=$plan.Name;Generation=1}) @($drive)} 'Generation BIOS refusee'
$plan.PhysicalDisks=$true;Refused {Assert-BastosVmIsolation $plan $vm @($drive)} 'Politique disque physique refusee';$plan.PhysicalDisks=$false
$plan.AutoStart=$true;Refused {Assert-BastosVmIsolation $plan $vm @($drive)} 'Demarrage automatique refuse';$plan.AutoStart=$false
$module=Get-Module Bastos.VmLab
& $module {
    function script:Get-VHD {param($Path);[pscustomobject]@{ParentPath=$global:VmTestParent;VhdType=$global:VmTestVhdType;Size=180GB}}
}
$global:VmTestParent=$plan.DiskPath;$global:VmTestVhdType='Differencing'
$checkpoint=[pscustomobject]@{Path=(Join-Path $plan.Directory 'checkpoint.avhdx');DiskNumber=$null}
Check (Assert-BastosVmIsolation $plan $vm @($checkpoint)) 'Point de controle local avec parent exact accepte'
$global:VmTestParent='C:\Autre.vhdx'
Refused {Assert-BastosVmIsolation $plan $vm @($checkpoint)} 'Parent de point de controle externe refuse'
$global:VmTestParent=$checkpoint.Path
Refused {Assert-BastosVmIsolation $plan $vm @($checkpoint)} 'Cycle de parents refuse'
$global:VmTestParent=$plan.DiskPath;$global:VmTestVhdType='Fixed'
Refused {Assert-BastosVmIsolation $plan $vm @($checkpoint)} 'Type de point de controle non confirme refuse'

$plan.LabId=[guid]::NewGuid().ToString('N')
$null=New-Item -ItemType Directory -Path $plan.Directory -Force
$authPath=Join-Path $plan.Directory 'LabAuthorization.json'
$auth=@{Schema=1;LabId=$plan.LabId;VmId=$plan.VmId;Name=$plan.Name;DiskPath=$plan.DiskPath;BaselineId=[guid]::NewGuid().ToString()}
function Write-Auth {$auth|ConvertTo-Json|Set-Content $authPath -Encoding UTF8}
Write-Auth
Check ((Read-BastosLabAuthorization $plan $authPath).BaselineId -eq $auth.BaselineId) 'Autorisation privee exacte acceptee'
Refused {Read-BastosLabAuthorization $plan (Join-Path $root 'Other.json')} 'Autorisation hors laboratoire refusee'
$auth.VmId=[guid]::NewGuid().ToString();Write-Auth
Refused {Read-BastosLabAuthorization $plan $authPath} 'Autorisation pour autre VM refusee'
$auth.VmId=$plan.VmId;$auth.BaselineId='';Write-Auth
Refused {Read-BastosLabAuthorization $plan $authPath} 'Baseline privee absente refusee'
$auth.BaselineId=[guid]::NewGuid().ToString();$auth.DiskPath='C:\Other.vhdx';Write-Auth
Refused {Read-BastosLabAuthorization $plan $authPath} 'Disque prive divergent refuse'
$auth.DiskPath=$plan.DiskPath;$plan.LabId='00000000000000000000000000000001';$auth.LabId=$plan.LabId;Write-Auth
Refused {Read-BastosLabAuthorization $plan $authPath} 'Identifiant exemple refuse comme autorisation reelle'
& $module {function script:Get-VMIntegrationService {param($VM);@([pscustomobject]@{Id='Microsoft:VM\6C09BB55-D683-4DA0-8931-C9BF705F6480';Name='Nom traduit';Enabled=$false},[pscustomobject]@{Id='Microsoft:VM\84EAAE65-2F2E-45F5-9BB5-0E857DC8EB47';Name='Battement traduit';Enabled=$true})}}
Check ((Get-BastosVmIntegrationComponent $vm '6c09bb55-d683-4da0-8931-c9bf705f6480').Name -eq 'Nom traduit') 'Composant Hyper-V identifie sans nom anglais'
Refused {Get-BastosVmIntegrationComponent $vm ([guid]::NewGuid())} 'Composant Hyper-V inconnu refuse'
$recoveryId=[guid]::NewGuid();$windowsId=[guid]::NewGuid();$dataType='EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'
$recovery=[pscustomobject]@{Guid=$recoveryId;Size=40GB;GptType=$dataType}
$windows=[pscustomobject]@{Guid=$windowsId;Size=140GB;GptType=$dataType}
Check ((Get-BastosVmEvidencePartitions @($recovery,$windows) $recoveryId).Windows.Guid -eq $windowsId) 'Type GPT sans accolades reconnu'
$windows.GptType='{'+$dataType.ToLowerInvariant()+'}'
Check ((Get-BastosVmEvidencePartitions @($recovery,$windows) $recoveryId).Windows.Guid -eq $windowsId) 'Type GPT avec accolades et casse differente reconnu'
$recovery.Size=70GB
Check ((Get-BastosVmEvidencePartitions @($recovery,$windows) $recoveryId).Recovery.Guid -eq $recoveryId) 'Recovery exclue de Windows meme au-dessus de 64 Go'
Refused {Get-BastosVmEvidencePartitions @($windows) $recoveryId} 'Preuve sans Recovery attendue refusee'
$extra=[pscustomobject]@{Guid=[guid]::NewGuid();Size=100GB;GptType=$dataType}
Refused {Get-BastosVmEvidencePartitions @($recovery,$windows,$extra) $recoveryId} 'Deux partitions Windows possibles refusees'
'PASS : '+$count+' controles isolation VM, simulations uniquement.'
