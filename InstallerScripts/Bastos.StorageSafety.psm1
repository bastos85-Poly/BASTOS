Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-BastosGptIdentity {
    param([Parameter(Mandatory)]$Disk)
    $guid=[guid]::Empty
    if([string]$Disk.PartitionStyle -ne 'GPT' -or -not [guid]::TryParse([string]$Disk.Guid,[ref]$guid) -or $guid -eq [guid]::Empty){
        throw 'DISK_IDENTITY_UNAVAILABLE : identite GPT du disque absente. Aucune modification autorisee.'
    }
    return $guid.ToString('D').ToUpperInvariant()
}
function Get-BastosStorageText {
    param($Object,[string]$Name)
    if($Object.PSObject.Properties[$Name]){return ([string]$Object.$Name).Trim().ToUpperInvariant()}
    return ''
}
function Get-BastosPartitionRecord {
    param([Parameter(Mandatory)]$Partition)
    $guid=[guid]::Empty;$type=[guid]::Empty
    if(-not [guid]::TryParse([string]$Partition.Guid,[ref]$guid) -or $guid -eq [guid]::Empty -or
       -not [guid]::TryParse([string]$Partition.GptType,[ref]$type) -or $type -eq [guid]::Empty -or
       [int]$Partition.PartitionNumber -lt 1 -or [long]$Partition.Offset -le 0 -or [long]$Partition.Size -le 0){
        throw 'DISK_LAYOUT_UNREADABLE : une partition ne peut pas etre identifiee. Aucune modification autorisee.'
    }
    [pscustomobject][ordered]@{Number=[int]$Partition.PartitionNumber;Guid=$guid.ToString('D').ToUpperInvariant();Offset=[long]$Partition.Offset;Size=[long]$Partition.Size;GptType=$type.ToString('D').ToUpperInvariant()}
}
function New-BastosStorageSnapshot {
    param([Parameter(Mandatory)]$Layout)
    $all=@(Get-Disk -ErrorAction Stop)
    $roles=[ordered]@{}
    foreach($role in @('WindowsDisk','InstallDisk','TargetDisk')){
        $selected=$Layout.$role
        $disk=@($all|Where-Object Number -eq $selected.Number)
        if($disk.Count -ne 1){throw 'DISK_IDENTITY_CHANGED : le disque selectionne a disparu. Reouvrez les options de partitions.'}
        $disk=$disk[0];$identity=Get-BastosGptIdentity $disk
        if($identity -ne (Get-BastosGptIdentity $selected)){throw 'DISK_IDENTITY_CHANGED : le numero de disque designe maintenant un autre disque.'}
        $matches=@($all|Where-Object { (Get-BastosStorageText $_ 'Guid').Trim('{}') -eq $identity })
        if($matches.Count -ne 1){throw 'DISK_IDENTITY_AMBIGUOUS : plusieurs disques partagent le meme GUID GPT. Aucune modification autorisee.'}
        if($disk.IsOffline -or $disk.IsReadOnly -or [string]$disk.BusType -in @('USB','SD','MMC') -or [long]$disk.Size -le 0){
            throw 'DISK_NOT_WRITABLE : le disque doit etre interne, en ligne et accessible en ecriture.'
        }
        $parts=@(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop|Sort-Object Offset)
        $records=@(foreach($part in $parts){Get-BastosPartitionRecord $part})
        if(@($records|Group-Object Guid|Where-Object Count -gt 1).Count -gt 0 -or @($records|Group-Object Number|Where-Object Count -gt 1).Count -gt 0){throw 'DISK_LAYOUT_AMBIGUOUS : identites de partitions dupliquees.'}
        $end=0L
        foreach($part in $records){
            if($part.Offset -lt $end -or $part.Size -gt ([long]$disk.Size-$part.Offset)){throw 'DISK_LAYOUT_UNREADABLE : partitions superposees ou taille incoherente.'}
            $end=$part.Offset+$part.Size
        }
        $roles[$role]=[ordered]@{
            Number=[int]$disk.Number;Guid=$identity;UniqueId=Get-BastosStorageText $disk 'UniqueId';Serial=Get-BastosStorageText $disk 'SerialNumber'
            Model=Get-BastosStorageText $disk 'FriendlyName';Size=[long]$disk.Size;BusType=([string]$disk.BusType).ToUpperInvariant();Partitions=$records
        }
    }
    return ([ordered]@{Schema=1;Disks=$roles}|ConvertTo-Json -Depth 8 -Compress)
}
function Assert-BastosStorageSnapshot {
    param([Parameter(Mandatory)][string]$Expected,[Parameter(Mandatory)][string]$Actual,[switch]$DisksOnly)
    try {
        $before=$Expected|ConvertFrom-Json;$now=$Actual|ConvertFrom-Json
        if($before.Schema -ne 1 -or $now.Schema -ne 1){throw 'Schema inconnu.'}
        foreach($role in @('WindowsDisk','InstallDisk','TargetDisk')){
            $old=$before.Disks.$role;$current=$now.Disks.$role
            foreach($field in @('Number','Guid','UniqueId','Serial','Model','Size','BusType')){
                if([string]$old.$field -cne [string]$current.$field){throw "Identite du disque modifiee ($role / $field)."}
            }
            if(-not $DisksOnly -and (ConvertTo-Json -InputObject @($old.Partitions) -Depth 5 -Compress) -cne (ConvertTo-Json -InputObject @($current.Partitions) -Depth 5 -Compress)){
                throw "Disposition des partitions modifiee ($role)."
            }
        }
    } catch {throw "DISK_PLAN_CHANGED : le disque ou ses partitions ne correspondent plus au plan valide. Reouvrez Compte, nom du PC, nettoyage et partitions puis verifiez et enregistrez le nouveau plan. $($_.Exception.Message)"}
}
function Assert-BastosPartitionTarget {
    param([Parameter(Mandatory)]$Expected,[string]$DriveLetter)
    $now=Get-Partition -DiskNumber $Expected.DiskNumber -PartitionNumber $Expected.PartitionNumber -ErrorAction Stop
    $before=Get-BastosPartitionRecord $Expected;$current=Get-BastosPartitionRecord $now
    if(($before|ConvertTo-Json -Compress) -cne ($current|ConvertTo-Json -Compress)){throw 'DISK_PARTITION_CHANGED : la partition cible a change. Aucune nouvelle ecriture autorisee.'}
    if($DriveLetter){
        $mapped=@(Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop)
        if($mapped.Count -ne 1 -or $mapped[0].DiskNumber -ne $Expected.DiskNumber -or [string]$mapped[0].Guid -ne [string]$Expected.Guid){
            throw 'DISK_LETTER_CHANGED : la lettre du lecteur designe une autre partition. Aucune nouvelle ecriture autorisee.'
        }
    }
}
Export-ModuleMember -Function Get-BastosGptIdentity,New-BastosStorageSnapshot,Assert-BastosStorageSnapshot,Assert-BastosPartitionTarget
