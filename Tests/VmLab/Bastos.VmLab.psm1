Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Assert-BastosLabPath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path)
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path)
    if($base -notmatch '^[A-Za-z]:\\' -or $base.Length -lt 4 -or
       $full -notmatch '^[A-Za-z]:\\' -or -not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'VM_LAB_PATH : chemin hors du dossier de laboratoire.'
    }
    $cursor=$full
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'VM_LAB_LINK : lien de dossier refuse.'}
        }
        $parent=Split-Path -Parent $cursor
        if($parent -eq $cursor){break};$cursor=$parent
    }
    return $full
}

function New-BastosVmPlan {
    param([Parameter(Mandatory)][string]$LabRoot,[Parameter(Mandatory)][string]$IsoPath)
    $root=[IO.Path]::GetFullPath($LabRoot).TrimEnd('\')
    if($root -notmatch '^[A-Za-z]:\\' -or $root.Length -lt 4 -or $root.StartsWith('D:\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'VM_LAB_ROOT : utiliser un dossier local dedie, hors du lecteur Recovery D:.'
    }
    $iso=[IO.Path]::GetFullPath($IsoPath)
    if($iso -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($iso) -ine '.iso') {throw 'VM_LAB_ISO : ISO locale requise.'}
    $token=[guid]::NewGuid().ToString('N')
    $directory=Assert-BastosLabPath $root (Join-Path $root $token)
    [pscustomobject][ordered]@{
        Schema=1;LabId=$token;Name=('BASTOS-TEST-'+$token.Substring(0,8));Root=$root;Directory=$directory
        DiskPath=(Join-Path $directory 'Windows-test.vhdx');IsoPath=$iso
        Generation=2;MemoryBytes=8GB;Processors=4;DiskBytes=180GB
        Network='Disconnected';PhysicalDisks=$false;AutoStart=$false
        Status='Planned';VmId='';CreatedUtc=[DateTime]::UtcNow.ToString('o')
    }
}

function Get-BastosVmReadiness {
    param([Parameter(Mandatory)][string]$LabRoot,[Parameter(Mandatory)][string]$IsoPath)
    $blockers=[Collections.Generic.List[string]]::new()
    $computer=Get-CimInstance Win32_ComputerSystem
    $cpu=@(Get-CimInstance Win32_Processor)[0]
    $feature=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if([string]$feature.State -ne 'Enabled'){$blockers.Add('Hyper-V est desactive. Son activation puis un redemarrage du PC sont necessaires.')}
    if(-not $computer.HypervisorPresent){$blockers.Add('L hyperviseur Windows n est pas actif pour cette session.')}
    if(-not (Get-Command New-VM -ErrorAction SilentlyContinue)){$blockers.Add('Le module de gestion Hyper-V n est pas disponible.')}
    $vmService=Get-Service vmms -ErrorAction SilentlyContinue
    if(-not $vmService -or [string]$vmService.Status -ne 'Running'){$blockers.Add('Le service Hyper-V VMMS n est pas actif.')}
    if([long]$computer.TotalPhysicalMemory -lt 16GB){$blockers.Add('Au moins 16 Go de RAM sur le PC sont requis pour ce banc de 8 Go.')}
    $plan=New-BastosVmPlan -LabRoot $LabRoot -IsoPath $IsoPath
    $letter=[IO.Path]::GetPathRoot($plan.Root).Substring(0,1)
    $volume=Get-Volume -DriveLetter $letter
    if([long]$volume.SizeRemaining -lt 120GB){$blockers.Add('Moins de 120 Go libres pour le disque dynamique et les points de controle.')}
    $iso=Get-Item -LiteralPath $plan.IsoPath -ErrorAction SilentlyContinue
    if(-not $iso -or $iso.PSIsContainer -or $iso.Length -lt 2GB){$blockers.Add('ISO Windows complete absente ou trop petite.')}
    [pscustomobject][ordered]@{
        Schema=1;CheckedUtc=[DateTime]::UtcNow.ToString('o');Ready=($blockers.Count -eq 0)
        HyperVState=[string]$feature.State;HypervisorActive=[bool]$computer.HypervisorPresent
        VirtualizationFirmwareEnabled=[bool]$cpu.VirtualizationFirmwareEnabled
        MemoryBytes=[long]$computer.TotalPhysicalMemory;LabFreeBytes=[long]$volume.SizeRemaining
        IsoPath=$plan.IsoPath;IsoBytes=$(if($iso){[long]$iso.Length}else{0L})
        Blockers=@($blockers);Plan=$plan;ExecutionStatus='NotRun'
        PendingTests=@('Preparation Recovery','Demarrage Recovery','Reinstallation complete','Premier Bureau','Conservation des partitions et refus d un plan divergent')
    }
}

function Assert-BastosVmIsolation {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Vm,[Parameter(Mandatory)][object[]]$Drives,[object[]]$NetworkAdapters=@())
    if($Plan.Schema -ne 1 -or $Plan.Generation -ne 2 -or $Plan.PhysicalDisks -or $Plan.AutoStart -or $Plan.Network -ne 'Disconnected'){
        throw 'VM_LAB_POLICY : configuration de laboratoire refusee.'
    }
    $parsed=[guid]::Empty
    if(-not [guid]::TryParse([string]$Plan.VmId,[ref]$parsed) -or $parsed -eq [guid]::Empty -or
       [string]$Vm.Id -ne [string]$Plan.VmId -or $Vm.Name -cne $Plan.Name -or $Vm.Generation -ne 2){throw 'VM_LAB_ID : machine non reconnue.'}
    $expected=Assert-BastosLabPath $Plan.Root $Plan.DiskPath
    if($Drives.Count -ne 1){throw 'VM_LAB_DISKS : un seul disque virtuel requis.'}
    foreach($drive in $Drives){
        if(($drive.PSObject.Properties['DiskNumber'] -and $null -ne $drive.DiskNumber) -or
           -not $drive.Path){throw 'VM_LAB_DISKS : disque physique refuse.'}
        $path=[IO.Path]::GetFullPath([string]$drive.Path)
        $depth=0
        while($path -ine $expected){
            $null=Assert-BastosLabPath $Plan.Directory $path
            if([IO.Path]::GetExtension($path) -ine '.avhdx' -or $depth -ge 16){throw 'VM_LAB_DISKS : disque externe ou chaine de points de controle refusee.'}
            $child=Get-VHD -Path $path
            if(-not $child.ParentPath -or [string]$child.VhdType -ne 'Differencing' -or $child.Size -ne $Plan.DiskBytes){throw 'VM_LAB_DISKS : point de controle non confirme.'}
            $path=[IO.Path]::GetFullPath([string]$child.ParentPath)
            $depth++
        }
    }
    if($NetworkAdapters.Count -gt 0){throw 'VM_LAB_NETWORK : les cartes reseau doivent etre retirees de cette VM.'}
    return $true
}

function Read-BastosLabAuthorization {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$Path)
    $expected=Assert-BastosLabPath $Plan.Directory (Join-Path $Plan.Directory 'LabAuthorization.json')
    if([IO.Path]::GetFullPath($Path) -ine $expected){throw 'VM_LAB_AUTH : fichier prive hors du laboratoire.'}
    $file=Get-Item -LiteralPath $expected -ErrorAction Stop
    if($file.Length -gt 16KB){throw 'VM_LAB_AUTH : fichier inattendu.'}
    $auth=Get-Content -LiteralPath $expected -Raw|ConvertFrom-Json
    if($auth.Schema -ne 1 -or $auth.LabId -cne $Plan.LabId -or $auth.VmId -cne $Plan.VmId -or $auth.Name -cne $Plan.Name -or
       [IO.Path]::GetFullPath($auth.DiskPath) -ine [IO.Path]::GetFullPath($Plan.DiskPath) -or
       $auth.LabId -notmatch '^[a-fA-F0-9]{32}$' -or $auth.LabId -eq '00000000000000000000000000000001'){
        throw 'VM_LAB_AUTH : identite privee divergente ou exemple non configure.'
    }
    $baseline=[guid]::Empty
    if(-not [guid]::TryParse([string]$auth.BaselineId,[ref]$baseline) -or $baseline -eq [guid]::Empty){throw 'VM_LAB_AUTH : baseline privee absente.'}
    return $auth
}

Export-ModuleMember -Function Assert-BastosLabPath,New-BastosVmPlan,Get-BastosVmReadiness,Assert-BastosVmIsolation,Read-BastosLabAuthorization
