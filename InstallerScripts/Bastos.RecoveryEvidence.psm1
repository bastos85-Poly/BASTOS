Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-BastosEvidenceText {
    param([string]$Root,[string]$Relative,[int]$MaximumBytes=1048576)
    $current=[IO.Path]::GetFullPath($Root)
    foreach($component in $Relative.Replace('\','/').Split('/')){
        if($component -in @('.','..') -or [IO.Path]::IsPathRooted($component)){throw 'Chemin de preuve invalide.'}
        if(([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Dossier de preuve redirige.'}
        $current=Join-Path $current $component
    }
    if(([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ([IO.FileInfo]$current).Length -gt $MaximumBytes){throw 'Preuve redirigee ou trop volumineuse.'}
    return [IO.File]::ReadAllText($current)
}

# Microsoft BCD provider: APPLICATION / OBJECT_LIST / subtype 2.
# https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/Win7Samples/winbase/bootconfigurationdata/bcdsamplelib/Constants.cs
function Get-BastosBootSequence {
    $opened=([wmiclass]'root\WMI:BcdStore').OpenStore('')
    if(-not $opened.ReturnValue){throw 'Ouverture du magasin BCD refusee.'}
    # WMI returns embedded ManagementBaseObject values without callable methods.
    # Bind the keyed instances explicitly before invoking instance methods.
    $store=[wmi]'root\WMI:BcdStore.FilePath=""'
    $manager=$store.OpenObject('{9dea862c-5cdd-4e70-acc1-f32b344d4795}')
    if(-not $manager.ReturnValue){throw 'Gestionnaire de demarrage BCD inaccessible.'}
    $object=[wmi]'root\WMI:BcdObject.Id="{9dea862c-5cdd-4e70-acc1-f32b344d4795}",StoreFilePath=""'
    $elements=$object.EnumerateElements()
    if(-not $elements.ReturnValue){throw 'Enumeration des elements BCD impossible.'}
    $sequence=@($elements.Elements|Where-Object Type -eq ([uint32]0x24000002))
    if($sequence.Count -gt 1){throw 'Sequence BCD ambigue.'}
    if($sequence.Count -eq 1){return @($sequence[0].Ids)}
    return @()
}
function Get-BastosRecoveryRoot {
    param([Parameter(Mandatory)]$Layout)
    $parts=@($Layout.RecoveryPartitions)
    if($parts.Count -ne 1 -or -not $parts[0].DriveLetter){throw 'RECOVERY_EVIDENCE_MISSING : partition Recovery unique et accessible requise.'}
    $letter=[string]$parts[0].DriveLetter
    Assert-BastosPartitionTarget -Expected $parts[0] -DriveLetter $letter
    $volume=Get-Volume -DriveLetter $letter -ErrorAction Stop
    if($volume.FileSystemLabel -ne 'BASTOS_RECOVERY' -or $volume.FileSystem -ne 'NTFS'){throw 'RECOVERY_EVIDENCE_INVALID : volume Recovery different du volume attendu.'}
    return "${letter}:\"
}
function Read-BastosBootEntry {
    param([string]$BootId)
    $entry=@(& "$env:SystemRoot\System32\bcdedit.exe" /enum $BootId /v 2>&1)
    if($LASTEXITCODE -ne 0){throw 'RECOVERY_BCD_UNCONFIRMED : relecture BCD impossible.'}
    return ($entry -join "`r`n")
}
function Remove-BastosBootSequence {
    & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue '{bootmgr}' bootsequence 2>&1|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Neutralisation du demarrage refusee par Windows.'}
}
function Read-BastosRecoveryEvidence {
    param([Parameter(Mandatory)]$Layout,[switch]$Boot)
    $root=Get-BastosRecoveryRoot $Layout
    $bootId=(Read-BastosEvidenceText $root 'BASTOS-BOOT-ID.txt').Trim()
    $parsed=[guid]::Empty
    if(-not [guid]::TryParse($bootId,[ref]$parsed) -or $parsed -eq [guid]::Empty){throw 'RECOVERY_EVIDENCE_INVALID : identifiant BCD invalide.'}
    $evidence=@{Root=$root;StorageSnapshot=(New-BastosStorageSnapshot $Layout);RecoveryPartitionGuid=[string]$Layout.RecoveryPartitions[0].Guid;BootId=$bootId;BootSequenceIds=@();BootEntry=''}
    if($Boot){
        $evidence.BootSequenceIds=@(Get-BastosBootSequence)
        $evidence.BootEntry=Read-BastosBootEntry -BootId $bootId
    }
    return $evidence
}
function Disable-BastosOwnedBoot {
    param([Parameter(Mandatory)]$Layout,[Parameter(Mandatory)][string]$OperationId)
    $root=Get-BastosRecoveryRoot $Layout
    $activeFile=Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'
    if(-not [IO.File]::Exists($activeFile)){
        if(@(Get-BastosBootSequence).Count -eq 0){return $true}
        throw 'Sequence BCD presente sans tentative identifiable ; aucun demarrage modifie.'
    }
    $attempt=(Read-BastosEvidenceText $root 'BASTOS-ACTIVE-ATTEMPT.txt').Trim()
    if($attempt -notmatch '^Attempt-[0-9a-fA-F]{32}$'){throw 'Tentative de demarrage non identifiable ; aucun autre demarrage modifie.'}
    # Limit rollback to the active attempt owned by this operation.
    $state=Read-BastosEvidenceText $root ("BASTOS-Diagnostics/Attempts/$attempt/State.json") 4194304|ConvertFrom-Json
    if(-not $state.PSObject.Properties['OperationId'] -or $state.OperationId -ne $OperationId -or $state.AttemptId -ne $attempt){throw 'Cette tentative appartient a une autre operation ; aucun demarrage modifie.'}
    $bootId=(Read-BastosEvidenceText $root 'BASTOS-BOOT-ID.txt').Trim()
    $sequence=@(Get-BastosBootSequence)
    if($sequence.Count -gt 0){
        if($sequence.Count -ne 1 -or $sequence[0] -ne $bootId){throw 'La sequence BCD a change ; aucun autre demarrage modifie.'}
        Remove-BastosBootSequence
        if(@(Get-BastosBootSequence).Count -ne 0){throw 'Neutralisation du demarrage non confirmee.'}
    }
    foreach($name in @('BASTOS-ACTIVE-ATTEMPT.txt','BASTOS-AUTO-REINSTALL.token','BASTOS-BOOT-MODE.txt')){
        $file=Join-Path $root $name
        if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
    }
    return $true
}
function Get-BastosRecoveryCachePlan {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$IsoPath,
        [int]$ImageIndex,[string]$EditionId,[string]$LauncherPath,[string]$ProbePath,[string]$CleanupProfile='')
    # An unavailable or stale proof always falls back to a complete rebuild.
    $iso=Get-Item -LiteralPath $IsoPath -ErrorAction Stop
    $isoHash=(Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $plan=[ordered]@{Mode='Full';RequiredFreeBytes=([long]$iso.Length+2GB);IsoSha256=$isoHash;CleanupProfile=$CleanupProfile;Reason='Media absent ou preuves du cache non conformes.'}
    try{
        $state=Read-BastosEvidenceText -Root $Root -Relative 'BASTOS-MEDIA-STATE.json' | ConvertFrom-Json
        $savedProfile=if($state.PSObject.Properties['CleanupProfile']){[string]$state.CleanupProfile}else{''}
        if($savedProfile -ne $CleanupProfile){return [pscustomobject]$plan}
        if($state.Schema -lt 8 -or $state.Schema -gt 9 -or $state.IsoSha256 -ne $isoHash -or
            (Read-BastosEvidenceText -Root $Root -Relative 'BASTOS-ISO.sha256').Trim() -ne $isoHash -or
            -not $state.InstallWimSanitized -or [int]$state.SanitizedImageIndex -ne $ImageIndex -or
            $state.WindowsEditionId -ne $EditionId){return [pscustomobject]$plan}
        if($state.PSObject.Properties['WindowsCacheRevision'] -and $state.WindowsCacheRevision -ne 1){return [pscustomobject]$plan}
        if($state.Schema -eq 9 -and -not $state.PSObject.Properties['WindowsCacheRevision']){return [pscustomobject]$plan}
        # Reject redirected cache files and their parent directories before hashing.
        foreach($relative in @('setup.exe','boot\boot.sdi','sources\install.wim')){
            $current=[IO.Path]::GetFullPath($Root)
            if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){return [pscustomobject]$plan}
            foreach($part in $relative.Split('\')){
                $current=Join-Path $current $part
                if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){return [pscustomobject]$plan}
            }
            if(-not [IO.File]::Exists($current)){return [pscustomobject]$plan}
        }
        if($state.InstallWimSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            (Get-FileHash -LiteralPath (Join-Path $Root 'sources\install.wim') -Algorithm SHA256 -ErrorAction Stop).Hash -ne $state.InstallWimSha256){return [pscustomobject]$plan}
        # This compatibility revision deliberately accepts the unchanged schema-8
        # sanitizer output. Future sanitizer changes must increment the revision.
        $plan.Mode='Boot';$plan.Reason='Image Windows verifiee ; demarrage a reconstruire.'
        $bootBytes=0L
        if($state.PSObject.Properties['SourceBootWimBytes']){$bootBytes=[long]$state.SourceBootWimBytes}
        $boot=Join-Path $Root 'sources\boot.wim'
        if(Test-Path -LiteralPath $boot -PathType Leaf){
            $item=Get-Item -LiteralPath $boot -Force
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){return [pscustomobject]@{Mode='Full';RequiredFreeBytes=([long]$iso.Length+2GB);IsoSha256=$isoHash;Reason='Image de demarrage redirigee.'}}
            $bootBytes=[Math]::Max($bootBytes,[long]$item.Length)
        }
        if($bootBytes -le 0 -or $bootBytes -gt [long]$iso.Length){$bootBytes=[long]$iso.Length}
        $plan.RequiredFreeBytes=$bootBytes+2GB
        if($state.RecoveryLauncherSha256 -eq (Get-FileHash -LiteralPath $LauncherPath -Algorithm SHA256 -ErrorAction Stop).Hash -and
            $state.RecoveryProbeSha256 -eq (Get-FileHash -LiteralPath $ProbePath -Algorithm SHA256 -ErrorAction Stop).Hash -and
            (($state.Schema -eq 8 -and -not $state.PSObject.Properties['BootCacheRevision']) -or ($state.PSObject.Properties['BootCacheRevision'] -and $state.BootCacheRevision -eq 1)) -and
            $state.BootWimSha256 -match '^[A-Fa-f0-9]{64}$' -and
            (Get-FileHash -LiteralPath $boot -Algorithm SHA256 -ErrorAction Stop).Hash -eq $state.BootWimSha256){
            $plan.Mode='Reuse';$plan.RequiredFreeBytes=2GB;$plan.Reason='Images Windows et demarrage verifiees et reutilisables.'
        }
    }catch{
        # A failure after Windows validation may still safely retain that image.
        $plan.Reason+=' '+$_.Exception.Message
    }
    return [pscustomobject]$plan
}
function Get-BastosDriverInventory {
    param([Parameter(Mandatory)][string]$Directory,[switch]$Hash)
    $base=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($base)
    while($pending.Count){
        $folder=$pending.Pop()
        if((Get-Item -LiteralPath $folder -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Dossier de pilotes redirige.'}
        foreach($entry in Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Fichier de pilotes redirige.'}
            if($entry.PSIsContainer){$pending.Push($entry.FullName)}else{
                [pscustomobject]@{Path=$entry.FullName.Substring($base.Length+1);Bytes=[long]$entry.Length;Sha256=$(if($Hash){(Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash}else{''})}
            }
        }
    }
}
function Test-BastosDriverBackup {
    param([Parameter(Mandatory)][string]$Directory)
    $manifest=Read-BastosEvidenceText -Root $Directory -Relative 'Manifest.json' -MaximumBytes 16777216 | ConvertFrom-Json
    if($manifest.Schema -ne 1 -or $manifest.Architecture -ne 'AMD64'){throw 'Sauvegarde de pilotes incompatible.'}
    $actual=@(Get-BastosDriverInventory -Directory (Join-Path $Directory 'Packages') -Hash)
    if($actual.Count -ne @($manifest.Files).Count){throw 'Nombre de fichiers pilotes divergent.'}
    $byPath=@{}
    foreach($entry in $manifest.Files){
        if($byPath.ContainsKey([string]$entry.Path)){throw 'Chemin pilote duplique.'}
        $byPath[[string]$entry.Path]=$entry
    }
    $bytes=0L;$infCount=0
    foreach($entry in $actual){
        if(-not $byPath.ContainsKey($entry.Path) -or $byPath[$entry.Path].Sha256 -ne $entry.Sha256 -or [long]$byPath[$entry.Path].Bytes -ne $entry.Bytes){throw 'Empreinte de pilote divergente.'}
        $bytes+=$entry.Bytes;if([IO.Path]::GetExtension($entry.Path) -ieq '.inf'){$infCount++}
    }
    if($bytes -ne [long]$manifest.TotalBytes -or $infCount -ne [int]$manifest.InfCount){throw 'Inventaire de pilotes incomplet.'}
    return $manifest
}
function Assert-BastosDriverSetupVersion {
    param([string]$SetupPath)
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($SetupPath)
    if($version.FileMajorPart -ne 10 -or $version.FileBuildPart -lt 26100){throw 'La conservation des pilotes exige Windows 11 24H2 ou ulterieur. Choisissez une ISO recente ou decochez cette option.'}
}
function Write-BastosDriverSelection {
    param([string]$Root,[bool]$Selected)
    $file=Join-Path $Root 'BASTOS-DRIVERS.enabled'
    if(Test-Path -LiteralPath $file){if((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Marqueur pilotes redirige.'}}
    $temp=$file+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,$(if($Selected){"1`r`n"}else{"0`r`n"}),[Text.Encoding]::ASCII)
        if([IO.File]::Exists($file)){[IO.File]::Replace($temp,$file,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$file)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function New-BastosDriverBackup {
    param([Parameter(Mandatory)][string]$Root,[bool]$Selected,[string]$SetupPath)
    if(-not $Selected){Write-BastosDriverSelection -Root $Root -Selected $false;return}
    Assert-BastosDriverSetupVersion -SetupPath $SetupPath
    $driverRoot=Join-Path ([IO.Path]::GetFullPath($Root)) 'BASTOS-Drivers'
    New-Item -ItemType Directory -Path $driverRoot -Force -ErrorAction Stop|Out-Null
    if((Get-Item -LiteralPath $driverRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Racine pilotes redirigee.'}
    $active=Join-Path $driverRoot 'Active'
    if(Test-Path -LiteralPath $active){if((Get-Item -LiteralPath $active -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Sauvegarde active redirigee.'}}
    $drivers=@(Get-WindowsDriver -Online -ErrorAction Stop)
    $estimate=0L
    foreach($directory in @($drivers|ForEach-Object {Split-Path -Parent $_.OriginalFileName}|Sort-Object -Unique)){
        foreach($entry in Get-BastosDriverInventory -Directory $directory){$estimate+=$entry.Bytes}
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($driverRoot))
    if($drive.AvailableFreeSpace -lt ($estimate+2GB)){throw 'Espace insuffisant sur D: pour exporter les pilotes en conservant la marge de 2 Go.'}
    $stage=Join-Path $driverRoot ('Staging-'+[guid]::NewGuid().ToString('N'))
    $previous=Join-Path $driverRoot ('Previous-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $stage 'Packages') -Force|Out-Null
    $published=$false
    try{
        if($drivers.Count){Export-WindowsDriver -Online -Destination (Join-Path $stage 'Packages') -ErrorAction Stop|Out-Null}
        $files=@(Get-BastosDriverInventory -Directory (Join-Path $stage 'Packages') -Hash|Sort-Object Path)
        $infCount=@($files|Where-Object {[IO.Path]::GetExtension($_.Path) -ieq '.inf'}).Count
        if($infCount -lt $drivers.Count){throw 'Export des pilotes incomplet par rapport aux paquets tiers inventories.'}
        $bytes=0L;foreach($file in $files){$bytes+=$file.Bytes}
        $manifest=[ordered]@{Schema=1;Architecture='AMD64';SourceComputer=$env:COMPUTERNAME;CreatedUtc=[DateTime]::UtcNow.ToString('o');InfCount=$infCount;TotalBytes=$bytes;Files=$files}
        [IO.File]::WriteAllText((Join-Path $stage 'Manifest.json'),($manifest|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        $null=Test-BastosDriverBackup -Directory $stage
        if($drive.AvailableFreeSpace -lt 2GB){throw 'Export trop volumineux ; marge de securite insuffisante.'}
        if([IO.Directory]::Exists($active)){[IO.Directory]::Move($active,$previous)}
        try{[IO.Directory]::Move($stage,$active)}catch{if([IO.Directory]::Exists($previous)){[IO.Directory]::Move($previous,$active)};throw}
        Write-BastosDriverSelection -Root $Root -Selected $true
        $published=$true
        return [pscustomobject]$manifest
    }finally{
        # Only our two generated child directories may be removed, never Active.
        $allowed=[IO.Path]::GetFullPath($driverRoot).TrimEnd('\')+'\'
        foreach($candidate in @($stage)+@(if($published){$previous})){
            $resolved=[IO.Path]::GetFullPath($candidate)
            if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^(Staging|Previous)-[0-9a-f]{32}$'){throw 'Nettoyage pilotes hors perimetre refuse.'}
            if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop}
        }
    }
}
Export-ModuleMember -Function Read-BastosRecoveryEvidence,Disable-BastosOwnedBoot,Get-BastosBootSequence,Get-BastosRecoveryCachePlan,New-BastosDriverBackup,Test-BastosDriverBackup
