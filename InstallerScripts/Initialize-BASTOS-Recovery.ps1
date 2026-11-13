[CmdletBinding()]
param(
    [ValidateSet('Status','ListEditions','ValidateIso','PreparePartition','Provision','BootOnce','DiagnosticBoot','PreviewPlan','InspectResult','DisarmBoot')][string]$Action = 'Status',
    [string]$IsoPath,
    [ValidateRange(0,99)][int]$EditionIndex = 0,
    [string]$AnswerFilePath,
    [string]$ResultPath,
    [string]$ProgressPath,
    [string]$CancellationPath,
    [int]$RecoverySizeGB = 40,
    [ValidateSet('Novice','Avance')][string]$RecoveryMode = 'Novice',
    [ValidateSet('WindowsOnly','BastosAutonomous')][string]$PostInstallMode = 'WindowsOnly',
    [switch]$UseEmbeddedProfile,
    [int]$TargetDiskNumber = -1,
    [int]$WindowsTargetDiskNumber = -1,
    [string]$OptionsPath,
    [string]$OperationId = '',
    [switch]$GenerateAnswerFile,
    [string]$WindowsLocale = 'fr-FR',
    [string]$KeyboardLayout = '040C:0000040C',
    [string]$LocalUserName = 'BastOS',
    [switch]$VerifyBoot
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.Cancellation.psm1') -Force -ErrorAction Stop
$script:RecoveryWritesStarted=$false
Import-Module (Join-Path $PSScriptRoot 'Bastos.RecoveryEvidence.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.Rufus.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.StorageSafety.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'BASTOS-RecoveryValidation.psm1') -Force -ErrorAction Stop
$script:RufusOptions=Read-BastosRufusOptions -Path $OptionsPath
if($script:RufusOptions -and $PostInstallMode -ne 'WindowsOnly'){throw 'Le menu Rufus utilise le profil Windows officiel sans surcouche autonome.'}
# Pin the Windows PowerShell modules instead of resolving a PowerShell 7 module
# inherited from the process that launched BASTOS.
$env:PSModulePath=(Join-Path $PSHOME 'Modules')+[IO.Path]::PathSeparator+$env:PSModulePath
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$recoveryLabel = 'BASTOS_RECOVERY'
$bootDescription = if($PostInstallMode -eq 'BastosAutonomous'){'Installation autonome BASTOS'}else{'Reinstallation BASTOS'}
$script:ProgressPercent = 0
$script:ProgressPhase = 'Initialisation'
$script:ProgressStep = 0
$script:ProgressTotalSteps = 10
$script:ArmingRoot = $null
$script:ArmingAttemptRoot = $null
$script:BootSequenceArmed = $false

function Write-RecoveryProgress {
    param([ValidateRange(0,100)][int]$Percent,[Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string]$Message,[int]$Step=0,[int]$TotalSteps=10)
    $script:ProgressPercent=$Percent
    $script:ProgressPhase=$Phase
    $script:ProgressStep=$Step
    $script:ProgressTotalSteps=$TotalSteps
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message -Step $Step -TotalSteps $TotalSteps
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-BastosMicrosoftSetupSignature {
    param([Parameter(Mandatory)][string]$Path)
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    $retailSignature=$signature.Status -eq 'Valid' -and $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match '(?i)Microsoft'
    $insiderSignature=$false
    if(-not $retailSignature -and $signature.Status -eq 'UnknownError' -and
        $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match '(?i)^CN=Microsoft Corporation,' -and
        $signature.SignerCertificate.Issuer -match '(?i)^CN=Microsoft Development PCA 2014,' -and
        $signature.StatusMessage -match '(?i)(racine.+(pas|non).+approuv|root.+not trusted|untrusted root)'){
        $chain=[Security.Cryptography.X509Certificates.X509Chain]::new()
        try{
            $chain.ChainPolicy.VerificationFlags=[Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
            $chain.ChainPolicy.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chainBuilt=$chain.Build($signature.SignerCertificate)
            $root=if($chain.ChainElements.Count -gt 0){$chain.ChainElements[$chain.ChainElements.Count-1].Certificate}else{$null}
            $insiderSignature=$chainBuilt -and $root -and
                $root.Subject -match '(?i)^CN=Microsoft Development Root Certificate Authority 2014,' -and
                $root.Thumbprint -eq 'F8DB7E1C16F1FFD4AAAD4AAD8DFF0F2445184AEB'
        }finally{$chain.Dispose()}
    }
    if(-not $retailSignature -and -not $insiderSignature){
        throw "Le programme d installation de l ISO ne possede pas une signature Microsoft valide ($($signature.Status))."
    }
    if($insiderSignature){return 'Insider'}
    return 'Retail'
}
function Save-Result {
    param([bool]$Success,[string]$Message,[hashtable]$Extra = @{})
    $payload = [ordered]@{
        Success=$Success;Message=$Message;Action=$Action;TimestampUtc=[DateTime]::UtcNow.ToString('o')
        Percent=$script:ProgressPercent;Phase=$script:ProgressPhase;Step=$script:ProgressStep;TotalSteps=$script:ProgressTotalSteps
    }
    foreach($key in $Extra.Keys){$payload[$key]=$Extra[$key]}
    if($ResultPath){
        if($OperationId){Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $Success -Message $Message -Data $payload}
        else{Write-BastosJsonFile -Path $ResultPath -Data $payload -Depth 6}
    }
    [pscustomobject]$payload
}
function Get-DiskIdentity {
    param([Parameter(Mandatory)]$Disk)
    [void](Get-BastosGptIdentity $Disk)
    return ([string]$Disk.Guid).Trim().ToUpperInvariant()
}
function Assert-RecoveryStorageCheckpoint {
    $current=Get-RecoverySelection
    $actual=New-BastosStorageSnapshot -Layout $current
    $expected=$script:StorageBaseline
    if($script:RufusOptions -and $script:RufusOptions.DiskSafetySnapshot){$expected=$script:RufusOptions.DiskSafetySnapshot}
    Assert-BastosStorageSnapshot -Expected $expected -Actual $actual -DisksOnly:(-not $script:RufusOptions)
    return $current
}
function Assert-RecoveryWriteTarget {
    param([Parameter(Mandatory)]$Partition,[string]$Letter)
    $null=Assert-RecoveryStorageCheckpoint
    Assert-BastosPartitionTarget -Expected $Partition -DriveLetter $Letter
}
function Get-RecoveryPartitions {
    @(
        Get-Volume -FileSystemLabel $recoveryLabel -ErrorAction SilentlyContinue |
            Get-Partition -ErrorAction SilentlyContinue
    )
}
function Get-RecoverySelection {
    $systemLetter=$env:SystemDrive.TrimEnd(':')
    if(-not $systemLetter){throw 'Le lecteur Windows actif ne peut pas etre identifie.'}
    $os=Get-Partition -DriveLetter $systemLetter -ErrorAction Stop
    $currentWindowsDisk=Get-Disk -Number $os.DiskNumber -ErrorAction Stop
    $efi=@(Get-Partition -DiskNumber $currentWindowsDisk.Number|Where-Object GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}')
    if($currentWindowsDisk.PartitionStyle -ne 'GPT'){throw 'Le disque Windows actuel doit utiliser GPT/UEFI.'}
    if($currentWindowsDisk.IsOffline -or $currentWindowsDisk.IsReadOnly){throw 'Le disque Windows actuel est hors ligne ou en lecture seule.'}
    if($efi.Count -ne 1){throw "BASTOS exige exactement une partition EFI sur le disque Windows; trouve : $($efi.Count)."}

    if($RecoveryMode -eq 'Novice'){
        if(($TargetDiskNumber -ge 0 -and $TargetDiskNumber -ne $currentWindowsDisk.Number) -or
            ($WindowsTargetDiskNumber -ge 0 -and $WindowsTargetDiskNumber -ne $currentWindowsDisk.Number)){
            throw 'Mode novice : les choix manuels sont refuses. BASTOS_RECOVERY et Windows utilisent toujours le disque contenant actuellement C:.'
        }
        $targetDisk=$currentWindowsDisk
        $installDisk=$currentWindowsDisk
        $selectionSource='AutomaticWindowsDisk'
    }else{
        if($TargetDiskNumber -lt 0){throw 'Mode avance : choisis explicitement le disque qui recevra BASTOS_RECOVERY.'}
        if($WindowsTargetDiskNumber -lt 0){throw 'Mode avance : choisis explicitement le disque qui recevra Windows.'}
        $targetDisk=Get-Disk -Number $TargetDiskNumber -ErrorAction Stop
        $installDisk=Get-Disk -Number $WindowsTargetDiskNumber -ErrorAction Stop
        $selectionSource='ManualAdvanced'
    }

    foreach($candidate in @($targetDisk,$installDisk)){
        if($candidate.PartitionStyle -ne 'GPT'){throw "Le disque $($candidate.Number) doit utiliser GPT."}
        if($candidate.IsOffline -or $candidate.IsReadOnly){throw "Le disque $($candidate.Number) est hors ligne ou en lecture seule."}
        if([string]$candidate.BusType -in @('USB','SD','MMC')){throw "Le disque $($candidate.Number) est amovible; une cible interne SATA, NVMe, SAS ou RAID est requise."}
    }

    $allRecovery=@(Get-RecoveryPartitions)
    if($allRecovery.Count -gt 1){throw "Plusieurs partitions BASTOS_RECOVERY ont ete detectees ($($allRecovery.Count)). La selection est ambigue; aucune operation n est autorisee."}
    $targetRecovery=@($allRecovery|Where-Object DiskNumber -eq $targetDisk.Number)
    if($allRecovery.Count -eq 1 -and $targetRecovery.Count -eq 0){
        throw "BASTOS_RECOVERY existe deja sur le disque $($allRecovery[0].DiskNumber). Selectionne ce disque en mode avance ou retire cette ancienne partition avant d en creer une autre."
    }
    if($script:RufusOptions){
        if($RecoveryMode -ne 'Novice' -or $targetRecovery.Count -ne 1){throw 'Le menu Rufus exige D: BASTOS_RECOVERY deja presente sur le disque Windows.'}
        $kept=Get-Partition -DriveLetter D -ErrorAction Stop
        $dVolume=Get-Volume -DriveLetter D -ErrorAction Stop
        if($dVolume.FileSystemLabel -ne $recoveryLabel -or $dVolume.FileSystem -ne 'NTFS' -or $kept.DiskNumber -ne $currentWindowsDisk.Number -or
            ([guid]$kept.Guid) -ne ([guid]$targetRecovery[0].Guid)){
            throw 'D: ne correspond pas a la partition BASTOS_RECOVERY du disque Windows. Aucune modification autorisee.'
        }
        if($script:RufusOptions.RecoveryPartitionGuid -and ([guid]$kept.Guid) -ne ([guid]$script:RufusOptions.RecoveryPartitionGuid)){
            throw 'La partition a conserver a change depuis la validation du menu.'
        }
        if($script:RufusOptions.WindowsDiskIdentity -and ([guid](Get-DiskIdentity $currentWindowsDisk)) -ne ([guid]$script:RufusOptions.WindowsDiskIdentity)){
            throw 'Le disque Windows a change depuis la validation du menu.'
        }
        if($Action -ne 'PreviewPlan' -and (-not $script:RufusOptions.RecoveryPartitionGuid -or -not $script:RufusOptions.WindowsDiskIdentity)){
            throw 'Le plan du disque doit etre valide dans le menu avant la preparation.'
        }
    }
    $recoveryReserve=if([int]$targetDisk.Number -eq [int]$installDisk.Number){if($targetRecovery.Count -eq 1){[long]$targetRecovery[0].Size}else{[long]$RecoverySizeGB*1GB}}else{0L}
    if(([long]$installDisk.Size-$recoveryReserve) -lt 64GB){throw "Le disque $($installDisk.Number) ne laisserait pas les 64 Go minimum requis pour Windows apres reservation de BASTOS_RECOVERY."}

    [pscustomobject]@{
        WindowsDisk=$currentWindowsDisk
        WindowsDiskIdentity=Get-DiskIdentity -Disk $currentWindowsDisk
        InstallDisk=$installDisk
        InstallDiskIdentity=Get-DiskIdentity -Disk $installDisk
        OsPartition=$os
        EfiPartitions=$efi
        TargetDisk=$targetDisk
        TargetDiskIdentity=Get-DiskIdentity -Disk $targetDisk
        RecoveryPartitions=$targetRecovery
        TargetIsWindowsDisk=([int]$targetDisk.Number -eq [int]$currentWindowsDisk.Number)
        InstallIsCurrentWindowsDisk=([int]$installDisk.Number -eq [int]$currentWindowsDisk.Number)
        RecoveryIsInstallDisk=([int]$targetDisk.Number -eq [int]$installDisk.Number)
        SelectionSource=$selectionSource
    }
}
function Get-FreeDriveLetter { $used=@(Get-Volume|Where-Object DriveLetter|ForEach-Object{[string]$_.DriveLetter});foreach($letter in @('R','S','T','U','V','W')){if($letter -notin $used){return $letter}};throw 'Aucune lettre temporaire disponible entre R et W.' }
function Test-BastosWindows11Metadata {
    param([Parameter(Mandatory)]$Image)
    if([string]::IsNullOrWhiteSpace([string]$Image.EditionId)){return $false}
    if([string]$Image.InstallationType -ne 'Client'){return $false}
    if([string]$Image.Architecture -notin @('9','amd64','x64')){return $false}
    $parsedVersion=[version]'0.0'
    if(-not [version]::TryParse([string]$Image.Version,[ref]$parsedVersion)){return $false}
    return $parsedVersion.Major -eq 10 -and $parsedVersion.Build -ge 22000
}
function Get-BastosInstallImageRelativePath {
    param([Parameter(Mandatory)][string]$Root)
    $found=@(@('sources\install.wim','sources\install.esd')|Where-Object{Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf})
    if($found.Count -ne 1){throw 'ISO incomplet ou ambigu : un seul install.wim ou install.esd est requis.'}
    return $found[0]
}
function Get-BastosWindows11Catalog {
    param([Parameter(Mandatory)][string]$ImagePath)
    # Read the same embedded WIM/ESD catalogue used by the ISO builder.
    # This needs no elevation or writable image mount. DISM validates the
    # selected image again during Provision before modifying the media.
    $stream=[IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $length=[int][Math]::Min([long](32MB),$stream.Length)
        [void]$stream.Seek(-$length,[IO.SeekOrigin]::End)
        $buffer=New-Object byte[] $length
        $read=0
        while($read -lt $length){$n=$stream.Read($buffer,$read,$length-$read);if($n -eq 0){break};$read+=$n}
        $text=[Text.Encoding]::Unicode.GetString($buffer,0,$read)
        $start=$text.LastIndexOf('<?xml',[StringComparison]::OrdinalIgnoreCase)
        if($start -lt 0){$start=$text.LastIndexOf('<WIM>',[StringComparison]::OrdinalIgnoreCase)}
        $end=$text.LastIndexOf('</WIM>',[StringComparison]::OrdinalIgnoreCase)
        if($start -lt 0 -or $end -lt $start){throw 'Catalogue WIM/ESD illisible.'}
        [xml]$metadata=$text.Substring($start,$end+6-$start)
        $images=@(foreach($node in @($metadata.WIM.IMAGE)){
            $windows=$node.WINDOWS
            $version=$windows.VERSION
            $image=[pscustomobject]@{
                ImageIndex=[int]$node.GetAttribute('INDEX');ImageName=[string]$node.NAME
                EditionId=[string]$windows.EDITIONID;InstallationType=[string]$windows.INSTALLATIONTYPE
                Architecture=[string]$windows.ARCH;Version=('{0}.{1}.{2}.{3}' -f $version.MAJOR,$version.MINOR,$version.BUILD,$version.SPBUILD)
                Languages=[string[]]@($windows.LANGUAGES.LANGUAGE);DefaultUILanguage=[string]$windows.LANGUAGES.DEFAULT
            }
            if(Test-BastosWindows11Metadata -Image $image){$image}
        })
        if($images.Count -eq 0){throw 'Cet ISO ne contient aucune edition Windows 11 Client x64 compatible.'}
        return $images
    }finally{$stream.Dispose()}
}
function Assert-BastosEditionSelection {
    param([Parameter(Mandatory)][string]$IsoHash,[Parameter(Mandatory)]$Options)
    foreach($key in @('WindowsImageIndex','WindowsEditionId','WindowsImageName','EditionIsoPath','EditionIsoSha256')){
        if(-not $Options.PSObject.Properties[$key]){throw 'Choisis l edition Windows dans Compte, nom du PC, nettoyage et partitions avant de preparer.'}
    }
    if([int]$Options.WindowsImageIndex -lt 1 -or [int]$Options.WindowsImageIndex -gt 99 -or
        [string]::IsNullOrWhiteSpace([string]$Options.WindowsEditionId) -or [string]::IsNullOrWhiteSpace([string]$Options.WindowsImageName)){
        throw 'Aucune edition Windows selectionnee dans les options.'
    }
    if([string]$Options.EditionIsoSha256 -ne $IsoHash -or
        [IO.Path]::GetFullPath([string]$Options.EditionIsoPath) -ne [IO.Path]::GetFullPath($IsoPath)){
        throw 'L ISO a change depuis le choix de l edition. Ouvre de nouveau les options et choisis son edition.'
    }
}
function Assert-BastosPreparedImageSelection {
    param([Parameter(Mandatory)]$Image,[Parameter(Mandatory)]$Options)
    # DISM detailed metadata can expose DISPLAYNAME as ImageName rather than
    # the embedded NAME shown in the menu (e.g. without the suffix "2024").
    # The exact ISO SHA-256 was already validated. Index + EditionId identify
    # the selected image; presentation text must not reject the same edition.
    if([int]$Image.ImageIndex -ne [int]$Options.WindowsImageIndex -or
        ([string]$Image.EditionId).Trim() -ne ([string]$Options.WindowsEditionId).Trim()){
        throw ("Edition Windows divergente : index {0} [{1}] attendu, index {2} [{3}] detecte. Ouvre de nouveau les options." -f
            $Options.WindowsImageIndex,$Options.WindowsEditionId,$Image.ImageIndex,$Image.EditionId)
    }
    if([string]::IsNullOrWhiteSpace([string]$Options.WindowsUILanguage) -or [string]$Options.WindowsUILanguage -notin @($Image.Languages|ForEach-Object{[string]$_})){
        throw 'Choisis une langue presente dans l edition de cet ISO dans Compte, nom du PC, nettoyage et partitions.'
    }
}
function Get-BastosWindows11Image {
    param([Parameter(Mandatory)][string]$ImagePath)
    # Get-WindowsImage sans -Index ne renvoie que le resume du catalogue :
    # EditionId n'y est pas garanti. Relire chaque index en mode detaille.
    $catalog=@(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop)
    $details=@(
        foreach($entry in $catalog){
            Get-WindowsImage -ImagePath $ImagePath -Index ([int]$entry.ImageIndex) -ErrorAction Stop
        }
    )
    # Version est exposée comme texte par DISM sous Windows PowerShell 5.1.
    # Il faut la convertir explicitement : "10.0.26100...".Major vaut sinon
    # $null et rejetait à tort l authentique index Professional.
    $supported=@($details|Where-Object{Test-BastosWindows11Metadata -Image $_})
    if($supported.Count -eq 0){throw 'Cet ISO ne contient aucune edition Windows 11 Client x64 compatible.'}
    if($EditionIndex -gt 0){
        $requested=@($supported|Where-Object ImageIndex -eq $EditionIndex)
        if($requested.Count -ne 1){throw "Index Windows $EditionIndex absent ou incompatible dans cet ISO."}
        return $requested[0]
    }
    if($supported.Count -eq 1){return $supported[0]}
    throw 'Plusieurs editions Windows sont disponibles. Precise EditionIndex pour la validation sans interface.'
}

function Invoke-RecoveryMediaCopy {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [int]$StartPercent=35,
        [int]$EndPercent=64
    )
    $sourceFiles=@(Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction Stop)
    [double]$totalBytes=($sourceFiles|Measure-Object -Property Length -Sum).Sum
    # Un chemin racine entre guillemets tel que "E:\" perturbe l analyse de
    # ligne de commande native : Robocopy absorbe alors la destination et rend
    # le code fatal 16. Le suffixe "." conserve la racine sans guillemet final
    # précédé d une barre oblique.
    $safeSource=$Source.TrimEnd('\')+'\.'
    $safeDestination=$Destination.TrimEnd('\')+'\.'
    $argumentLine='"{0}" "{1}" /E /R:2 /W:2 /XJ /NFL /NDL /NP' -f $safeSource,$safeDestination
    $copyLog=Join-Path $env:TEMP ('BASTOS-Robocopy-'+[guid]::NewGuid().ToString('N')+'.log')
    $copyError=Join-Path $env:TEMP ('BASTOS-Robocopy-'+[guid]::NewGuid().ToString('N')+'.err')
    Write-RecoveryProgress -Percent $StartPercent -Phase 'Copie du média Windows' -Message ('Démarrage de la copie de {0:N1} Go.' -f ($totalBytes/1GB)) -Step 5
    try{
        $process=Start-Process -FilePath 'robocopy.exe' -ArgumentList $argumentLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $copyLog -RedirectStandardError $copyError
        while(-not $process.WaitForExit(750)){
            [double]$copiedBytes=(Get-ChildItem -LiteralPath $Destination -Recurse -File -Force -ErrorAction SilentlyContinue|Measure-Object -Property Length -Sum).Sum
            $ratio=if($totalBytes -gt 0){[Math]::Min(1,$copiedBytes/$totalBytes)}else{0}
            $percent=[int][Math]::Round($StartPercent+(($EndPercent-$StartPercent)*$ratio))
            $copiedText='{0:N1} Go sur {1:N1} Go' -f ($copiedBytes/1GB),($totalBytes/1GB)
            Write-RecoveryProgress -Percent $percent -Phase 'Copie du média Windows' -Message "Copie et contrôle du contenu de l ISO : $copiedText." -Step 5
        }
        $process.WaitForExit()
        if($process.ExitCode -ge 8){
            $detail=@(Get-Content -LiteralPath $copyLog -ErrorAction SilentlyContinue|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Last 4) -join ' '
            if([string]::IsNullOrWhiteSpace($detail)){$detail='aucun détail supplémentaire fourni'}
            throw "La copie temporaire de l ISO a echoue (Robocopy $($process.ExitCode)) : $detail. L ancien media reste intact."
        }
    }finally{
        Remove-Item -LiteralPath $copyLog,$copyError -Force -ErrorAction SilentlyContinue
    }
}
function Sync-BastosAutonomousMediaPayload {
    param(
        [Parameter(Mandatory)][string]$ApplicationRoot,
        [Parameter(Mandatory)][string]$MediaRoot
    )
    $source=[IO.Path]::GetFullPath($ApplicationRoot).TrimEnd('\')
    $media=[IO.Path]::GetFullPath($MediaRoot).TrimEnd('\')
    if(-not(Test-Path -LiteralPath $source -PathType Container)){throw "Source BASTOS absente : $source"}
    if(-not(Test-Path -LiteralPath (Join-Path $media 'sources') -PathType Container)){throw "Media Windows incomplet : $media"}
    $criticalFiles=@(
        'VERSION.txt','INSTALLER-MANIFEST.sha256','BASTOS-Architecture.psm1','BASTOS-SetupDiagnostics.psm1','BASTOS-Start.cmd',
        'Start-BASTOS-Autonomous-FirstLogon.ps1','Initialize-BASTOS-Autonomous-FirstLogon.ps1','Initialize-BASTOS-PreLogon.ps1',
        'Invoke-BASTOS-Specialize.ps1','Apply-Machine.ps1','BASTOS-ErrorHandler.cmd','BASTOS-SetupComplete.cmd','BASTOS-LocalOnly-OOBE.cmd'
    )
    foreach($relative in $criticalFiles){
        if(-not(Test-Path -LiteralPath (Join-Path $source $relative) -PathType Leaf)){throw "Runtime BASTOS incomplet avant synchronisation : $relative"}
    }
    $answerTemplatePath=Join-Path $source 'autounattend.xml'
    $answerTemplateText=[IO.File]::ReadAllText($answerTemplatePath)
    if($answerTemplateText -notmatch '__BASTOS_USERNAME__' -or
       $answerTemplateText -match '(?i)BASTOS-Setup-Temporary' -or $answerTemplateText -notmatch '<LocalAccounts>'){
        throw 'Le modele autounattend source ne contient pas le compte local sans mot de passe attendu.'
    }
    $preLogonSourceText=[IO.File]::ReadAllText((Join-Path $source 'Initialize-BASTOS-PreLogon.ps1'))
    if($preLogonSourceText -notmatch 'LogonUser' -or $preLogonSourceText -notmatch 'PasswordVerified' -or
       $preLogonSourceText -notmatch "standardName='BastOS'" -or $preLogonSourceText -notmatch 'Disable-BuiltInAdministrator' -or
       $preLogonSourceText -match 'Rename-BuiltInAdministrator'){
        throw 'Le script pre-connexion source ne garantit pas le compte local BastOS distinct de SID-500.'
    }
    $setupCompleteSourceText=[IO.File]::ReadAllText((Join-Path $source 'BASTOS-SetupComplete.cmd'))
    if($setupCompleteSourceText -notmatch 'Initialize-BASTOS-PreLogon\.ps1' -or
       $setupCompleteSourceText -notmatch 'BASTOS_PRELOGON_EXIT'){
        throw 'SetupComplete ne lance pas la validation preconnexion BastOS.'
    }

    $payloadRoot=Join-Path $media 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
    New-Item -ItemType Directory -Path $payloadRoot -Force|Out-Null
    $arguments=@(
        $source,$payloadRoot,'/E','/COPY:DAT','/DCOPY:DAT','/R:2','/W:1','/XJ','/FFT','/NP','/NFL','/NDL',
        '/XD','Logs','Backups','.codex-backup-*','/XF','*.ok'
    )
    & "$env:SystemRoot\System32\robocopy.exe" @arguments|Out-Null
    $copyExit=$LASTEXITCODE
    if($copyExit -ge 8){throw "Synchronisation du payload Windows echouee (Robocopy $copyExit)."}

    [IO.File]::WriteAllText((Join-Path $payloadRoot 'BASTOS-AccountFlow.txt'),$(if($PostInstallMode -eq 'WindowsOnly'){'RufusLocal'}else{'LegacyAutoLogon'}),[Text.Encoding]::ASCII)
    $setupScripts=Join-Path $media 'sources\$OEM$\$$\Setup\Scripts'
    New-Item -ItemType Directory -Path $setupScripts -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'BASTOS-ErrorHandler.cmd') -Destination (Join-Path $setupScripts 'ErrorHandler.cmd') -Force
    Copy-Item -LiteralPath (Join-Path $source 'BASTOS-SetupComplete.cmd') -Destination (Join-Path $setupScripts 'SetupComplete.cmd') -Force
    # Le modele a la racine du Recovery est lu par BootOnce. Le remplacer ici
    # elimine l ancien autounattend avec le compte BastOS temporaire.
    Copy-Item -LiteralPath $answerTemplatePath -Destination (Join-Path $media 'autounattend.xml') -Force
    if((Get-FileHash -LiteralPath $answerTemplatePath -Algorithm SHA256).Hash -ne
       (Get-FileHash -LiteralPath (Join-Path $media 'autounattend.xml') -Algorithm SHA256).Hash){
        throw 'Le modele autounattend racine diverge apres synchronisation.'
    }

    $verifiedFiles=@()
    foreach($relative in $criticalFiles){
        $sourcePath=Join-Path $source $relative
        $targetPath=Join-Path $payloadRoot $relative
        if(-not(Test-Path -LiteralPath $targetPath -PathType Leaf)){throw "Payload Windows incomplet apres synchronisation : $relative"}
        $sourceHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $targetHash=(Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        if($sourceHash -ne $targetHash){throw "Payload Windows divergent apres synchronisation : $relative"}
        $verifiedFiles+=[pscustomobject]@{Path=$relative;Sha256=$targetHash}
    }
    $errorHandlerHash=(Get-FileHash -LiteralPath (Join-Path $setupScripts 'ErrorHandler.cmd') -Algorithm SHA256).Hash
    if($errorHandlerHash -ne (Get-FileHash -LiteralPath (Join-Path $source 'BASTOS-ErrorHandler.cmd') -Algorithm SHA256).Hash){throw 'ErrorHandler Windows divergent apres synchronisation.'}
    $setupCompleteHash=(Get-FileHash -LiteralPath (Join-Path $setupScripts 'SetupComplete.cmd') -Algorithm SHA256).Hash
    if($setupCompleteHash -ne (Get-FileHash -LiteralPath (Join-Path $source 'BASTOS-SetupComplete.cmd') -Algorithm SHA256).Hash){throw 'SetupComplete Windows divergent apres synchronisation.'}
    $version=(Get-Content -LiteralPath (Join-Path $source 'VERSION.txt') -Raw -Encoding UTF8).Trim()
    $state=[ordered]@{
        Schema=1;BastosVersion=$version;ApplicationRoot=$source;PayloadRoot=$payloadRoot
        InstallerManifestSha256=(Get-FileHash -LiteralPath (Join-Path $source 'INSTALLER-MANIFEST.sha256') -Algorithm SHA256).Hash
        ErrorHandlerSha256=$errorHandlerHash;SetupCompleteSha256=$setupCompleteHash;RobocopyExitCode=$copyExit;Files=$verifiedFiles;VerifiedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $media 'BASTOS-AUTONOMOUS-PAYLOAD.json'),($state|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $payloadRoot 'BASTOS-AUTONOMOUS-PAYLOAD.json'),($state|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [pscustomobject]$state
}
function Remove-BastosEmbeddedPantherAnswers {
    param([Parameter(Mandatory)][string]$InstallWimPath,[ValidateRange(1,99)][int]$ImageIndex = 1,[switch]$CleanBastos,[string]$CleanupReportPath)

    $resolvedWim=[IO.Path]::GetFullPath($InstallWimPath)
    if(-not(Test-Path -LiteralPath $resolvedWim -PathType Leaf)){throw "install.wim absent : $resolvedWim"}
    $originalMetadata=Get-BastosWimMetadata -ImagePath $resolvedWim
    $originalImage=$originalMetadata.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']/WINDOWS/EDITIONID")
    if(-not $originalImage){throw 'Le catalogue source est incomplet avant nettoyage : ISO refusee.'}
    Assert-BastosWimSelection -Metadata $originalMetadata -ImageIndex $ImageIndex -EditionId $originalImage.InnerText
    # Avoid mounting/committing an intact Microsoft image for a no-op cleanup.
    if(-not $CleanBastos -and -not (Test-BastosWimCachedAnswers -ImagePath $resolvedWim -ImageIndex $ImageIndex)){
        return (Get-FileHash -LiteralPath $resolvedWim -Algorithm SHA256).Hash
    }
    $mountPath=Join-Path $env:TEMP ('BASTOS-InstallWim-Sanitize-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $mountPath -Force|Out-Null
    $wimItem=Get-Item -LiteralPath $resolvedWim -Force
    $wasReadOnly=$wimItem.IsReadOnly
    $mounted=$false
    try{
        if($wasReadOnly){$wimItem.IsReadOnly=$false}
        Mount-WindowsImage -ImagePath $resolvedWim -Index $ImageIndex -Path $mountPath -CheckIntegrity -ErrorAction Stop|Out-Null
        $mounted=$true
        $cleanReport=$null
        if($CleanBastos){
            if($originalImage.InnerText -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)'){throw 'Le profil propre avec trois epingles exige Windows Pro, Entreprise ou Education.'}
            $cleanupModule=Import-Module (Join-Path $PSScriptRoot 'Bastos.InstallationOptions.psm1') -PassThru -ErrorAction Stop
            $cleanReport=& $cleanupModule {param($path) Invoke-BastosOfflineMinimalApps -ImagePath $path} $mountPath
        }
        foreach($relative in @('Windows\Panther\unattend.xml','Windows\Panther\Unattend\Unattend.xml')){
            $cachedAnswer=Join-Path $mountPath $relative
            if(Test-Path -LiteralPath $cachedAnswer){Remove-Item -LiteralPath $cachedAnswer -Force -ErrorAction Stop}
            if(Test-Path -LiteralPath $cachedAnswer){throw "Réponse OOBE embarquée impossible à supprimer : $relative"}
        }
        $legacyMarkers=@(Get-ChildItem -LiteralPath (Join-Path $mountPath 'Windows\Panther') -File -Recurse -ErrorAction SilentlyContinue|
            Select-String -SimpleMatch 'BASTOS-Setup-Temporary' -ErrorAction SilentlyContinue)
        if($legacyMarkers.Count -gt 0){throw 'Le mot de passe temporaire historique reste présent dans Windows\Panther.'}
        Dismount-WindowsImage -Path $mountPath -Save -CheckIntegrity -ErrorAction Stop|Out-Null
        $mounted=$false
        # DISM can discard WINDOWS fields while committing an IoT image.
        # Preserve the original edition/languages independently of changed file counts.
        Restore-BastosWimWindowsMetadata -ImagePath $resolvedWim -ImageIndex $ImageIndex -OriginalMetadata $originalMetadata
        if($CleanBastos -and $CleanupReportPath){[IO.File]::WriteAllText($CleanupReportPath,($cleanReport|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
        Assert-BastosWimSelection -Metadata (Get-BastosWimMetadata -ImagePath $resolvedWim) -ImageIndex $ImageIndex -EditionId $originalImage.InnerText
        (Get-FileHash -LiteralPath $resolvedWim -Algorithm SHA256).Hash
    }finally{
        if($mounted){
            try{Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop|Out-Null;$mounted=$false}
            catch{Write-Warning ('Montage non libere, dossier conserve : '+$mountPath)}
        }
        if(Test-Path -LiteralPath $resolvedWim -PathType Leaf){(Get-Item -LiteralPath $resolvedWim -Force).IsReadOnly=$wasReadOnly}
        $resolvedMount=[IO.Path]::GetFullPath($mountPath);$allowedMount=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
        if(-not $resolvedMount.StartsWith($allowedMount,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedMount) -notmatch '^BASTOS-InstallWim-Sanitize-[0-9a-f]{32}$'){throw 'Nettoyage du montage hors perimetre refuse.'}
        if(-not $mounted -and (Test-Path -LiteralPath $resolvedMount)){Remove-Item -LiteralPath $resolvedMount -Recurse -Force -ErrorAction Stop}
    }
}
function Invoke-BcdEdit { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments);$output=& "$env:SystemRoot\System32\bcdedit.exe" @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw "BCDEdit a echoue : $($output -join ' ')"};@($output) }
function Test-RecoveryBootImageCompatibility {
    param(
        [Parameter(Mandatory)][string]$BootWimPath,
        [Parameter(Mandatory)][string]$ProbePath
    )
    $applyPath=Join-Path $env:TEMP ('BASTOS-BootWim-Verify-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $applyPath -Force|Out-Null
    try{
        $dismOutput=@(& "$env:SystemRoot\System32\dism.exe" /English /Apply-Image "/ImageFile:$BootWimPath" /Index:2 "/ApplyDir:$applyPath" /CheckIntegrity 2>&1)
        $dismExit=$LASTEXITCODE
        if($dismExit -ne 0){throw "Application de verification boot.wim impossible (DISM $dismExit) : $(@($dismOutput|Select-Object -Last 8) -join ' ')"}
        $system32=Join-Path $applyPath 'Windows\System32'
        $versionPath=Join-Path $system32 'BASTOS-OneClick.version'
        $launcherPath=Join-Path $system32 'BASTOS-Start.cmd'
        $embeddedProbePath=Join-Path $system32 'BASTOS-Recovery-Probe.exe'
        $shellPath=Join-Path $system32 'winpeshl.ini'
        foreach($requiredPath in @($versionPath,$launcherPath,$embeddedProbePath,$shellPath)){
            if(-not(Test-Path -LiteralPath $requiredPath -PathType Leaf)){throw "boot.wim compatible refuse : fichier absent $requiredPath"}
        }
        $version=(Get-Content -LiteralPath $versionPath -Raw).Trim()
        $launcher=Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
        $shell=Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
        $embeddedLauncherBytes=[IO.File]::ReadAllBytes($launcherPath)
        $embeddedLauncherAscii=[Text.Encoding]::ASCII.GetString($embeddedLauncherBytes)
        if($embeddedLauncherBytes.Count -eq 0 -or $embeddedLauncherBytes.Where({$_ -gt 127},'First').Count -gt 0 -or
           $embeddedLauncherAscii -match '(?<!\r)\n' -or $embeddedLauncherAscii -match '\r(?!\n)' -or $embeddedLauncherAscii -notmatch '\r\n'){
            throw 'boot.wim compatible refuse : lanceur WinPE non ASCII ou sans fins de ligne CRLF.'
        }
        if($version -ne '16' -or $shell -notmatch '(?i)BASTOS-Start\.cmd' -or
            $launcher -notmatch 'BASTOS-ACTIVE-ATTEMPT' -or $launcher -notmatch '--validate-partition' -or
            $launcher -notmatch ':HARDEN_OFFLINE_WINDOWS' -or
            $launcher -notmatch 'Precontrole compte local Bastos' -or
            $launcher -notmatch 'Windows\\Panther\\Unattend\\Unattend\.xml' -or
            $launcher -notmatch 'set /p BASTOS_ACCOUNT_MARKER=' -or
            $launcher -match 'findstr[^\r\n]+BASTOS-LocalAccount' -or
            $launcher -match '(?im)^\s*findstr(?:\.exe)?\s' -or
            $launcher -match '(?im)^\s*fc(?:\.exe)?\s+/b' -or
            $launcher -notmatch 'BASTOS_EXPECTED_COMPUTER_NAME' -or
            $launcher -notmatch 'DefaultDomainName.*BASTOS_EXPECTED_COMPUTER_NAME' -or
            $launcher -match 'DefaultDomainName.*BASTOS_OFFLINE_COMPUTER_NAME' -or
            $launcher -match 'ChildCompletion.+/v setup\.exe.+/d 3' -or
            $launcher -notmatch 'BASTOS_ACCOUNT_SOURCE_SIZE' -or
            $launcher -notmatch 'ms-cxh:localonly' -or
            $launcher -match 'ancien AutoLogon OOBE encore present'){
            throw "boot.wim compatible refuse : flux specialize/BastOS absent (version $version)."
        }
        if((Get-FileHash -LiteralPath $embeddedProbePath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $ProbePath -Algorithm SHA256).Hash){
            throw 'boot.wim compatible refuse : sonde native differente.'
        }
        [pscustomobject]@{
            Compatible=$true
            Mode='EmbeddedLauncherV16-SpecializeAware-BastOS'
            EmbeddedLauncherSha256=(Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
            EmbeddedProbeSha256=(Get-FileHash -LiteralPath $embeddedProbePath -Algorithm SHA256).Hash
        }
    }finally{
        $resolved=[IO.Path]::GetFullPath($applyPath)
        $tempRoot=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
        if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'BASTOS-BootWim-Verify-*'){
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
function Update-RecoveryBootImage {
    param(
        [Parameter(Mandatory)][string]$BootWimPath,
        [Parameter(Mandatory)][string]$LauncherPath,
        [Parameter(Mandatory)][string]$ProbePath,
        [switch]$AllowCompatibleLauncher
    )
    if(-not(Test-Path -LiteralPath $LauncherPath -PathType Leaf)){throw 'Le lanceur WinPE BASTOS-Start.cmd est absent.'}
    if(-not(Test-Path -LiteralPath $ProbePath -PathType Leaf)){throw 'La sonde native BASTOS-Recovery-Probe.exe est absente.'}
    $launcherBytes=[IO.File]::ReadAllBytes($LauncherPath)
    $launcherText=[Text.Encoding]::ASCII.GetString($launcherBytes)
    if($launcherBytes.Count -eq 0 -or $launcherBytes.Where({$_ -gt 127},'First').Count -gt 0){
        throw 'Le lanceur WinPE doit etre un batch ASCII non vide.'
    }
    if($launcherText -match '(?<!\r)\n' -or $launcherText -match '\r(?!\n)' -or $launcherText -notmatch '\r\n'){
        throw 'Le lanceur WinPE doit utiliser exclusivement des fins de ligne Windows CRLF. Reinstallation refusee avant redemarrage.'
    }
    $mountPath=Join-Path $env:TEMP ('BASTOS-BootWim-'+[guid]::NewGuid().ToString('N'))
    $mounted=$false
    $shortNameRegistryPath='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $shortNameOriginal=$null
    $shortNameAdjusted=$false
    $mountFailure=$null
    $hadSuccessfulMount=$false
    try{
        # Certains profils d optimisation desactivent globalement les noms courts
        # NTFS. Les WIM Microsoft contiennent encore des metadonnees 8.3 et DISM
        # echoue alors avec 0x80070780. Passer temporairement au mode par volume
        # permet le montage sur C:, dont l etat volume reste active, sans modifier
        # durablement le choix de l utilisateur.
        $shortNameOriginal=[int](Get-ItemPropertyValue -LiteralPath $shortNameRegistryPath -Name 'NtfsDisable8dot3NameCreation' -ErrorAction Stop)
        if($shortNameOriginal -eq 1){
            & fsutil.exe 8dot3name set 2 | Out-Null
            if($LASTEXITCODE -ne 0){throw "Impossible d ouvrir la compatibilite NTFS 8.3 pour DISM (code $LASTEXITCODE)."}
            $shortNameAdjusted=$true
        }
        New-Item -ItemType Directory -Path $mountPath -Force|Out-Null
        (Get-Item -LiteralPath $BootWimPath -Force).IsReadOnly=$false
        Mount-WindowsImage -ImagePath $BootWimPath -Index 2 -Path $mountPath -CheckIntegrity|Out-Null
        $mounted=$true
        $hadSuccessfulMount=$true
        $system32=Join-Path $mountPath 'Windows\System32'
        foreach($command in @('cmd.exe','find.exe','dism.exe','reg.exe','diskpart.exe','bcdedit.exe','wpeutil.exe','wpeinit.exe','robocopy.exe')){
            if(-not(Test-Path -LiteralPath (Join-Path $system32 $command) -PathType Leaf)){throw "boot.wim incomplet : commande WinPE obligatoire absente : $command"}
        }
        Copy-Item -LiteralPath $LauncherPath -Destination (Join-Path $system32 'BASTOS-Start.cmd') -Force
        $embeddedLauncherText=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $system32 'BASTOS-Start.cmd')))
        if($embeddedLauncherText -match '(?<!\r)\n' -or $embeddedLauncherText -match '\r(?!\n)' -or $embeddedLauncherText -notmatch '\r\n'){
            throw 'Le lanceur injecte dans boot.wim a perdu ses fins de ligne CRLF.'
        }
        Copy-Item -LiteralPath $ProbePath -Destination (Join-Path $system32 'BASTOS-Recovery-Probe.exe') -Force
        # WinPE lance directement le batch visible. La sonde native reste un outil
        # de detection des volumes et disques, mais n est plus un maillon du shell.
        # Ainsi, toute erreur du batch reste affichee et journalisee au lieu de
        # fermer la console puis de rendre un code opaque a Winpeshl.
        $winpeshl="[LaunchApps]`r`n%SYSTEMROOT%\System32\cmd.exe, /d /k %SYSTEMROOT%\System32\BASTOS-Start.cmd`r`n"
        [IO.File]::WriteAllText((Join-Path $system32 'winpeshl.ini'),$winpeshl,[Text.Encoding]::ASCII)
        $startnet="@echo off`r`ncall `"%SYSTEMROOT%\System32\BASTOS-Start.cmd`"`r`nset `"BASTOS_START_EXIT=%ERRORLEVEL%`"`r`necho BASTOS-Start.cmd code %BASTOS_START_EXIT% >X:\BASTOS-Start-Exit.txt`r`nwpeutil reboot`r`nexit /b %BASTOS_START_EXIT%`r`n"
        [IO.File]::WriteAllText((Join-Path $system32 'startnet.cmd'),$startnet,[Text.Encoding]::ASCII)
        [IO.File]::WriteAllText((Join-Path $system32 'BASTOS-OneClick.version'),'16',[Text.Encoding]::ASCII)
        Dismount-WindowsImage -Path $mountPath -Save -CheckIntegrity|Out-Null
        $mounted=$false
    }catch{
        $mountFailure=$_
    }finally{
        if($mounted){Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue|Out-Null}
        if($shortNameAdjusted -and $null -ne $shortNameOriginal){
            & fsutil.exe 8dot3name set $shortNameOriginal 2>$null | Out-Null
        }
        Remove-Item -LiteralPath $mountPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if($mountFailure){
        if($PostInstallMode -eq 'WindowsOnly' -or -not $AllowCompatibleLauncher -or $hadSuccessfulMount){throw $mountFailure}
        try{
            $compatibility=Test-RecoveryBootImageCompatibility -BootWimPath $BootWimPath -ProbePath $ProbePath
        }catch{
            throw "Mise a jour de boot.wim impossible ($($mountFailure.Exception.Message)) et lanceur compatible non confirme : $($_.Exception.Message)"
        }
        return [pscustomobject]@{
            Updated=$false
            CompatibilityMode=$compatibility.Mode
            EmbeddedLauncherSha256=$compatibility.EmbeddedLauncherSha256
        }
    }
    [pscustomobject]@{
        Updated=$true
        CompatibilityMode='ExactLauncher'
        EmbeddedLauncherSha256=(Get-FileHash -LiteralPath $LauncherPath -Algorithm SHA256).Hash
    }
}
function Set-BastosRufusMediaProfile {
    param([Parameter(Mandatory)][string]$MediaRoot,[Parameter(Mandatory)][string]$ApplicationRoot)
    $payload=Join-Path $MediaRoot 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
    $scripts=Join-Path $MediaRoot 'sources\$OEM$\$$\Setup\Scripts'
    New-Item -ItemType Directory -Path $payload,$scripts -Force|Out-Null
    # WindowsOnly must outlive the temporary Recovery volume. Stage the full
    # verified application on C: through $OEM$ instead of linking back to D:.
    $buildPath=Join-Path $ApplicationRoot 'BASTOS-Build.json'
    $manifestPath=Join-Path $ApplicationRoot 'BASTOS-App-Manifest.json'
    $build=Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne [string]$build.AppManifestSha256){throw 'Manifeste de l application source invalide.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($item in $manifest.Files){
        $relative=([string]$item.Path).Replace('/','\')
        if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or @($relative.Split('\')|Where-Object{$_ -in @('.','..')}).Count){throw "Chemin de manifeste interdit : $relative"}
        $sourceFile=Join-Path $ApplicationRoot $relative
        if((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne [string]$item.Sha256){throw "Application source alteree : $relative"}
        $targetFile=Join-Path $payload $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetFile) -Force|Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        if((Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash -ne [string]$item.Sha256){throw "Application Windows divergente : $relative"}
    }
    Copy-Item -LiteralPath $manifestPath,$buildPath -Destination $payload -Force
    $finalizer=Join-Path $ApplicationRoot 'Finalize-BASTOS-TemporaryRecovery.ps1'
    if(-not(Test-Path -LiteralPath $finalizer -PathType Leaf)){throw 'Module de finalisation de Recovery absent du paquet.'}
    Copy-Item -LiteralPath $finalizer -Destination (Join-Path $payload 'Finalize-BASTOS-TemporaryRecovery.ps1') -Force
    if((Get-FileHash -LiteralPath $finalizer -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $payload 'Finalize-BASTOS-TemporaryRecovery.ps1') -Algorithm SHA256).Hash){throw 'Module de finalisation copie avec erreur.'}
    [IO.File]::WriteAllText((Join-Path $payload 'BASTOS-AccountFlow.txt'),'RufusLocal',[Text.Encoding]::ASCII)
    $shortcutWorker=Join-Path $ApplicationRoot 'New-BASTOS-DesktopShortcut.ps1'
    Copy-Item -LiteralPath $shortcutWorker -Destination (Join-Path $payload 'New-BASTOS-DesktopShortcut.ps1') -Force
    if((Get-FileHash -LiteralPath $shortcutWorker).Hash -ne (Get-FileHash -LiteralPath (Join-Path $payload 'New-BASTOS-DesktopShortcut.ps1')).Hash){throw 'Worker raccourci BASTOS divergent.'}
    Copy-Item -LiteralPath (Join-Path $ApplicationRoot 'BASTOS-ErrorHandler.cmd') -Destination (Join-Path $scripts 'ErrorHandler.cmd') -Force
    if((Get-FileHash (Join-Path $scripts 'ErrorHandler.cmd')).Hash -ne (Get-FileHash (Join-Path $ApplicationRoot 'BASTOS-ErrorHandler.cmd')).Hash){throw 'Gestionnaire erreur Windows divergent.'}
    Copy-Item -LiteralPath (Join-Path $ApplicationRoot 'BASTOS-SetupComplete.cmd') -Destination (Join-Path $scripts 'SetupComplete.cmd') -Force
}



function New-RecoveryAnswerFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][ValidateRange(1,99)][int]$ProImageIndex,
        [string]$EditionId = 'Professional',
        [string]$ImageUILanguage = '',
        [ValidateSet('WindowsOnly','BastosAutonomous')][string]$PostInstallMode = 'WindowsOnly',
        [string]$MachineWorkerPath = (Join-Path $PSScriptRoot 'Invoke-BASTOS-Specialize.ps1')
    )
    if(-not(Test-Path -LiteralPath $SourcePath -PathType Leaf)){throw 'Le fichier autounattend.xml de l ISO est absent.'}
    [xml]$answer=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
    $ns=[Xml.XmlNamespaceManager]::new($answer.NameTable)
    $ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
    $unattendNamespace='urn:schemas-microsoft-com:unattend'
    $wcmNamespace='http://schemas.microsoft.com/WMIConfig/2002/State'

    # Reconstruire specialize avec un nom de machine stable. Le compte utilisateur
    # est cree nativement pendant oobeSystem afin d eviter tout compte de domaine.
    $computerName=([string]$env:COMPUTERNAME).Trim().ToUpperInvariant()
    if([string]::IsNullOrWhiteSpace($computerName) -or $computerName.Length -gt 15 -or $computerName -match '[^A-Z0-9-]' -or $computerName -notmatch '[A-Z]' -or $computerName -like 'MININT-*' -or $computerName -match '(?i)KernelOS|KernelPan|KRNLGame|KOS[ -]?Post'){
        $computerName='BASTOS-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()
    }
    foreach($specializeSettings in @($answer.SelectNodes('//u:settings[@pass="specialize"]',$ns))){
        [void]$specializeSettings.ParentNode.RemoveChild($specializeSettings)
    }
    $specializeFragment=$answer.CreateDocumentFragment()
    $specializeFragment.InnerXml=('<settings xmlns="urn:schemas-microsoft-com:unattend" pass="specialize"><component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><ComputerName>{0}</ComputerName></component></settings>' -f [Security.SecurityElement]::Escape($computerName))
    $oobeSettings=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]',$ns)
    if(-not $oobeSettings){throw 'La passe oobeSystem est absente du fichier de reponses.'}
    [void]$oobeSettings.ParentNode.InsertBefore($specializeFragment.FirstChild,$oobeSettings)

    # Microsoft deconseille SkipMachineOOBE. Les ecrans sont automatises avec
    # les reglages Hide* documentes et le compte local cree par UserAccounts.
    $oobeNode=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:OOBE',$ns)
    if(-not $oobeNode){throw 'Le composant Microsoft-Windows-Shell-Setup/OOBE est absent du fichier de reponses.'}
    foreach($settingName in @('SkipMachineOOBE','SkipUserOOBE')){
        foreach($settingNode in @($oobeNode.SelectNodes("u:$settingName",$ns))){[void]$oobeNode.RemoveChild($settingNode)}
    }

    $setup=$answer.SelectSingleNode('//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]',$ns)
    if(-not $setup){throw 'Le composant Microsoft-Windows-Setup est absent du fichier de reponses.'}
    foreach($old in @($setup.SelectNodes('u:DiskConfiguration | u:ImageInstall',$ns))){[void]$setup.RemoveChild($old)}
    $dynamicUpdate=$setup.SelectSingleNode('u:DynamicUpdate',$ns)
    $userData=$setup.SelectSingleNode('u:UserData',$ns)
    if(-not $dynamicUpdate -or -not $userData){throw 'Le fichier de reponses ne contient pas les reperes de securite attendus.'}
    # The explicit image index selects the edition; a key copied from another
    # edition must never override the choice (Home, Pro, Enterprise or IoT).
    foreach($productKey in @($userData.SelectNodes('u:ProductKey',$ns))){[void]$userData.RemoveChild($productKey)}
    # WinPE still prompts for a key if ProductKey is absent. Like Rufus WUE,
    # keep an empty Key instead of retaining a key for a different edition.
    # /IMAGE/INDEX remains authoritative; this neither supplies nor activates a key.
    $productKeyFragment=$answer.CreateDocumentFragment()
    $productKeyFragment.InnerXml='<ProductKey xmlns="urn:schemas-microsoft-com:unattend"><Key/><WillShowUI>Never</WillShowUI></ProductKey>'
    [void]$userData.AppendChild($productKeyFragment.FirstChild)
    $diskFragment=$answer.CreateDocumentFragment()
    $diskFragment.InnerXml='<DiskConfiguration xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><Disk wcm:action="add"><DiskID>0</DiskID><WillWipeDisk>false</WillWipeDisk><ModifyPartitions><ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>NTFS</Format><Label>Windows</Label></ModifyPartition></ModifyPartitions></Disk><WillShowUI>Never</WillShowUI></DiskConfiguration>'
    [void]$setup.InsertBefore($diskFragment.FirstChild,$dynamicUpdate)
    $imageFragment=$answer.CreateDocumentFragment()
    # L index de l edition est detecte dans le WIM reel, independamment
    # de la langue du nom affiche dans l ISO.
    $imageFragment.InnerXml=('<ImageInstall xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><OSImage><InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>{0}</Value></MetaData></InstallFrom><InstallTo><DiskID>0</DiskID><PartitionID>1</PartitionID></InstallTo><WillShowUI>Never</WillShowUI></OSImage></ImageInstall>' -f $ProImageIndex)
    [void]$setup.InsertBefore($imageFragment.FirstChild,$userData)
    if($answer.OuterXml -match '__BASTOS_[A-Z_]+__'){throw 'Le fichier de reponses Recovery contient encore un choix BASTOS non resolu.'}
    $oobeShell=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]',$ns)
    if(-not $oobeShell){throw 'Le composant Shell-Setup OOBE est absent.'}
    $registeredOwner=$oobeShell.SelectSingleNode('u:RegisteredOwner',$ns)
    if(-not $registeredOwner){$registeredOwner=$answer.CreateElement('RegisteredOwner',$unattendNamespace);[void]$oobeShell.PrependChild($registeredOwner)}
    $localAccountName='BastOS'
    $localDisplayName='BastOS'
    $registeredOwner.InnerText=$localDisplayName
    $userAccounts=$oobeShell.SelectSingleNode('u:UserAccounts',$ns)
    if(-not $userAccounts){$userAccounts=$answer.CreateElement('UserAccounts',$unattendNamespace);[void]$oobeShell.AppendChild($userAccounts)}
    foreach($oldChild in @($userAccounts.ChildNodes)){[void]$userAccounts.RemoveChild($oldChild)}
    $localAccountsFragment=$answer.CreateDocumentFragment()
    $localAccountsFragment.InnerXml=('<LocalAccounts xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><LocalAccount wcm:action="add"><Password><Value></Value><PlainText>true</PlainText></Password><Description>Compte local BastOS sans mot de passe</Description><DisplayName>{1}</DisplayName><Group>Administrators</Group><Name>{0}</Name></LocalAccount></LocalAccounts>' -f [Security.SecurityElement]::Escape($localAccountName),[Security.SecurityElement]::Escape($localDisplayName))
    [void]$userAccounts.AppendChild($localAccountsFragment.FirstChild)
    $localAccountValue=$userAccounts.SelectSingleNode('u:LocalAccounts/u:LocalAccount/u:Password/u:Value',$ns)
    $localAccountNode=$userAccounts.SelectSingleNode('u:LocalAccounts/u:LocalAccount/u:Name',$ns)
    $windowsPeFullName=$answer.SelectSingleNode('//u:settings[@pass="windowsPE"]//u:UserData/u:FullName',$ns)
    if($windowsPeFullName){$windowsPeFullName.InnerText=$localDisplayName}
    $inputLocale=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:InputLocale',$ns)
    $uiLanguage=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UILanguage',$ns)
    $hideOnline=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideOnlineAccountScreens',$ns)
    $hideLocal=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideLocalAccountScreen',$ns)
    $hideWireless=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:OOBE/u:HideWirelessSetupInOOBE',$ns)
    if(-not $localAccountValue -or $localAccountValue.InnerText -ne '' -or -not $localAccountNode -or $localAccountNode.InnerText -cne $localAccountName){throw 'Le compte local Recovery sans mot de passe est invalide.'}
    # AutoLogon cible le compte local normal cree par oobeSystem. Le nom reel de
    # la machine est explicite afin de ne jamais reutiliser Domain=. ou un domaine
    # perime provenant d une ancienne image.
    foreach($autoLogon in @($answer.SelectNodes('//u:settings[@pass="oobeSystem"]//u:AutoLogon',$ns))){
        [void]$autoLogon.ParentNode.RemoveChild($autoLogon)
    }
    $autoLogon=$answer.CreateElement('AutoLogon',$unattendNamespace)
    $autoLogonPassword=$answer.CreateElement('Password',$unattendNamespace)
    $autoLogonValue=$answer.CreateElement('Value',$unattendNamespace)
    $autoLogonPlainText=$answer.CreateElement('PlainText',$unattendNamespace);$autoLogonPlainText.InnerText='true'
    [void]$autoLogonPassword.AppendChild($autoLogonValue)
    [void]$autoLogonPassword.AppendChild($autoLogonPlainText)
    $autoLogonEnabled=$answer.CreateElement('Enabled',$unattendNamespace);$autoLogonEnabled.InnerText='true'
    $autoLogonCount=$answer.CreateElement('LogonCount',$unattendNamespace);$autoLogonCount.InnerText='1'
    $autoLogonUsername=$answer.CreateElement('Username',$unattendNamespace);$autoLogonUsername.InnerText=$localAccountName
    $autoLogonDomain=$answer.CreateElement('Domain',$unattendNamespace);$autoLogonDomain.InnerText=$computerName
    [void]$autoLogon.AppendChild($autoLogonPassword)
    [void]$autoLogon.AppendChild($autoLogonDomain)
    [void]$autoLogon.AppendChild($autoLogonEnabled)
    [void]$autoLogon.AppendChild($autoLogonCount)
    [void]$autoLogon.AppendChild($autoLogonUsername)
    [void]$oobeShell.InsertBefore($autoLogon,$userAccounts)
    if($autoLogonValue.InnerText -ne '' -or $autoLogonDomain.InnerText -cne $computerName -or $autoLogonDomain.InnerText -eq '.' -or $autoLogonEnabled.InnerText -ne 'true' -or $autoLogonCount.InnerText -ne '1' -or $autoLogonUsername.InnerText -cne $localAccountName){
        throw 'AutoLogon Recovery sans mot de passe n a pas pu etre verrouille.'
    }
    if(-not $inputLocale -or [string]::IsNullOrWhiteSpace($inputLocale.InnerText)){throw 'Le clavier choisi est absent du fichier Recovery.'}
    if(-not $uiLanguage -or [string]::IsNullOrWhiteSpace($uiLanguage.InnerText)){throw 'La langue choisie est absente du fichier Recovery.'}
    if(-not $hideOnline -or $hideOnline.InnerText -ne 'true' -or -not $hideLocal -or $hideLocal.InnerText -ne 'true' -or -not $hideWireless -or $hideWireless.InnerText -ne 'true'){throw 'Le fichier Recovery ne garantit pas un OOBE sans interaction reseau ou compte Microsoft.'}
    if($answer.OuterXml -match '(?i)SkipMachineOOBE|SkipUserOOBE'){throw 'Le fichier Recovery contient encore un contournement OOBE deconseille par Microsoft.'}
    if($PostInstallMode -eq 'WindowsOnly'){
        if($answer.OuterXml -match '(?i)Apply-Machine|Apply-User|Complete-BASTOS|BASTOS-Specialize|Initialize-BASTOS-Autonomous'){
            throw 'Le fichier Recovery Windows seul contient encore une personnalisation BASTOS interdite.'
        }
    }else{
        if($answer.OuterXml -match '(?i)KernelOS|KernelPan|KRNLGame|KOS[ -]?Post'){
            throw 'Le profil autonome contient une commande KernelOS/KRNLGame interdite.'
        }
        $stableComputerName=$answer.SelectSingleNode('//u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:ComputerName',$ns)
        if(-not $stableComputerName -or $stableComputerName.InnerText -match '[*?]'){
            throw 'Le profil autonome exige un nom de machine stable.'
        }
        if($answer.OuterXml -notmatch [regex]::Escape('Start-BASTOS-Autonomous-FirstLogon.ps1')){
            throw 'Le profil autonome ne contient pas le lanceur obligatoire de premier logon.'
        }
        $sourceRoot=Split-Path -Parent $MachineWorkerPath
        if([string]::IsNullOrWhiteSpace($sourceRoot)){$sourceRoot=$PSScriptRoot}
        foreach($preLogonFile in @('BASTOS-LocalOnly-OOBE.cmd','BASTOS-SetupComplete.cmd')){
            if(-not(Test-Path -LiteralPath (Join-Path $sourceRoot $preLogonFile) -PathType Leaf)){
                throw "Le filet pre-connexion obligatoire est absent : $preLogonFile"
            }
        }
        if(-not(Test-Path -LiteralPath $MachineWorkerPath -PathType Leaf)){
            throw 'Le worker machine local Invoke-BASTOS-Specialize.ps1 est absent.'
        }
    }
    # Regional formats and keyboard remain user choices. UI language must exist
    # in the selected image; requesting fr-FR from an en-US-only ISO is invalid.
    if($ImageUILanguage){foreach($uiNode in $answer.SelectNodes('//u:UILanguage',$ns)){$uiNode.InnerText=$ImageUILanguage}}
    if($PostInstallMode -eq 'WindowsOnly'){
        Set-BastosRufusAccountFlow -Document $answer -Options $script:RufusOptions -EditionId $EditionId -FirstLogonScriptPath (Join-Path (Split-Path -Parent $DestinationPath) 'sources\$OEM$\$1\ProgramData\BASTOS-ISO\Rufus-FirstLogon.ps1')
        # The image language is authoritative even when the user's regional format differs.
        if($ImageUILanguage){
            foreach($uiNode in $answer.SelectNodes('//u:UILanguage',$ns)){$uiNode.InnerText=$ImageUILanguage}
            $expectedPath=Join-Path (Split-Path -Parent $DestinationPath) 'sources\$OEM$\$1\ProgramData\BASTOS-ISO\Installation-Expected.json'
            $expected=Get-Content -LiteralPath $expectedPath -Raw -Encoding UTF8|ConvertFrom-Json
            $expected.UILanguage=$ImageUILanguage
            [IO.File]::WriteAllText($expectedPath,($expected|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
    }
    $settings=[Xml.XmlWriterSettings]::new();$settings.Encoding=[Text.UTF8Encoding]::new($false);$settings.Indent=$true
    $writer=[Xml.XmlWriter]::Create($DestinationPath,$settings)
    try{$answer.Save($writer)}finally{$writer.Dispose()}
}
function New-BastosDeploymentPlan {
    param(
        [Parameter(Mandatory)][int]$InstallDiskNumber,
        [Parameter(Mandatory)][object[]]$Partitions,
        [int[]]$PreservedPartitionNumbers=@(),
        [bool]$CreateEfi=$false,
        [int]$OsPartitionNumber=-1
    )
    $preserved=@($PreservedPartitionNumbers|Sort-Object -Unique)
    # Les partitions auxiliaires sont supprimées avant Windows. Si une identité
    # change pendant les premiers contrôles WinPE, l ancien Windows reste donc
    # encore intact et BASTOS peut s arrêter sans aggraver la situation.
    $deleteParts=@(
        $Partitions |
            Where-Object{$_.PartitionNumber -notin $preserved} |
            Sort-Object @{Expression={if([int]$_.PartitionNumber -eq $OsPartitionNumber){1}else{0}}},@{Expression='PartitionNumber';Descending=$true}
    )
    $available=@(1..128|Where-Object{$_ -notin $preserved})
    $offset=0;$newEfiNumber=$null
    if($CreateEfi){$newEfiNumber=[int]$available[0];$offset=1}
    $newMsrNumber=[int]$available[$offset]
    $newWindowsNumber=[int]$available[$offset+1]
    if($newMsrNumber -eq $newWindowsNumber -or $newWindowsNumber -in $preserved){throw 'Impossible de calculer un numero de partition Windows sur ce disque.'}
    $lines=[Collections.Generic.List[string]]::new()
    # Le numéro du disque est résolu de nouveau dans WinPE à partir du GUID GPT.
    # Il ne doit jamais être figé depuis le Windows qui vient d être quitté.
    $lines.Add('select disk __BASTOS_TARGET_DISK__')
    foreach($deletePart in $deleteParts){$lines.Add("select partition $($deletePart.PartitionNumber)");$lines.Add('delete partition override')}
    if($CreateEfi){$lines.Add('create partition efi size=260');$lines.Add('format fs=fat32 quick label=System')}
    $lines.Add('create partition msr size=16')
    $lines.Add('create partition primary')
    $lines.Add('format fs=ntfs quick label=Windows')
    $lines.Add('assign letter=W')
    $deleteEntries=@(
        foreach($deletePart in $deleteParts){
            [pscustomobject]@{
                PartitionNumber=[int]$deletePart.PartitionNumber
                Offset=[long]$deletePart.Offset
                GptType=([string]$deletePart.GptType).Trim('{}').ToLowerInvariant()
                Guid=([string]$deletePart.Guid).Trim().ToLowerInvariant()
                IsWindows=([int]$deletePart.PartitionNumber -eq $OsPartitionNumber)
            }
        }
    )
    $createLines=[Collections.Generic.List[string]]::new()
    if($CreateEfi){$createLines.Add('create partition efi size=260');$createLines.Add('format fs=fat32 quick label=System')}
    $createLines.Add('create partition msr size=16')
    $createLines.Add('create partition primary')
    $createLines.Add('format fs=ntfs quick label=Windows')
    $createLines.Add('assign letter=W')
    [pscustomobject]@{
        Lines=@($lines);DeletePartitions=$deleteParts;DeleteEntries=$deleteEntries;CreateLines=@($createLines)
        NewEfiPartitionNumber=$newEfiNumber;NewMsrPartitionNumber=$newMsrNumber;NewWindowsPartitionNumber=$newWindowsNumber
    }
}

function Resolve-BastosNativePartitionNumbers {
    param(
        [Parameter(Mandatory)][string]$ProbePath,
        [Parameter(Mandatory)][int]$DiskNumber,
        [Parameter(Mandatory)][object[]]$Partitions
    )
    if(-not(Test-Path -LiteralPath $ProbePath -PathType Leaf)){throw 'La sonde native de partitions est absente.'}
    $resolved=[Collections.Generic.List[object]]::new()
    $usedNumbers=[Collections.Generic.HashSet[int]]::new()
    foreach($partition in $Partitions){
        $guid=([string]$partition.Guid).Trim('{}').ToLowerInvariant()
        $type=([string]$partition.GptType).Trim('{}').ToLowerInvariant()
        $offset=[long]$partition.Offset
        if($guid -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' -or
           $type -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' -or $offset -lt 0){
            throw 'Identite GPT de partition invalide avant le redemarrage.'
        }
        # Get-Partition can report the GPT entry number while DiskPart/WinPE
        # enumerate physical partitions in a different order. Use the exact
        # probe shipped in boot.wim to resolve the numbers it will see there.
        $preferred=[int]$partition.PartitionNumber
        $candidates=@($preferred)+@(1..128|Where-Object{$_ -ne $preferred})
        $nativeNumber=0
        foreach($candidate in $candidates){
            $oldPreference=$ErrorActionPreference
            try{
                $ErrorActionPreference='Continue'
                $global:LASTEXITCODE=-1
                & $ProbePath --validate-partition $DiskNumber $candidate $offset $type $guid 2>&1 | Out-Null
                $probeExit=$LASTEXITCODE
            }finally{$ErrorActionPreference=$oldPreference}
            if($probeExit -eq 0){$nativeNumber=$candidate;break}
        }
        if($nativeNumber -eq 0){throw "Partition GPT introuvable par la sonde WinPE sur le disque $DiskNumber (GUID $guid). Aucun redemarrage programme."}
        if(-not $usedNumbers.Add($nativeNumber)){throw "Numero de partition WinPE ambigu sur le disque $DiskNumber : $nativeNumber."}
        $resolved.Add([pscustomobject]@{
            DiskNumber=$DiskNumber;PartitionNumber=$nativeNumber;Offset=$offset
            GptType=$type;Guid=$guid;Size=[long]$partition.Size
        })
    }
    return @($resolved.ToArray())
}

try {
    if($Action -eq 'ListEditions'){
        if(-not $IsoPath -or -not(Test-Path -LiteralPath $IsoPath -PathType Leaf) -or [IO.Path]::GetExtension($IsoPath) -ne '.iso'){throw 'Selectionne un fichier ISO Windows existant.'}
        $isoItem=Get-Item -LiteralPath $IsoPath
        $originalLength=$isoItem.Length;$originalTicks=$isoItem.LastWriteTimeUtc.Ticks
        $diskImage=Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop
        $ownedMount=-not $diskImage.Attached
        try{
            if($ownedMount){$diskImage=Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop}
            $isoVolume=$diskImage|Get-Volume|Where-Object DriveLetter|Select-Object -First 1
            if(-not $isoVolume){throw 'Volume ISO illisible.'}
            $isoRoot="$($isoVolume.DriveLetter):\"
            [void](Assert-BastosMicrosoftSetupSignature -Path (Join-Path $isoRoot 'setup.exe'))
            $sourceImage=Join-Path $isoRoot (Get-BastosInstallImageRelativePath -Root $isoRoot)
            $images=@(Get-BastosWindows11Catalog -ImagePath $sourceImage)
            $isoHash=(Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
            $isoItem=Get-Item -LiteralPath $IsoPath
            if($isoItem.Length -ne $originalLength -or $isoItem.LastWriteTimeUtc.Ticks -ne $originalTicks){throw 'L ISO a change pendant sa lecture. Relance le choix de l edition.'}
            Save-Result -Success $true -Message 'Editions Windows lues. Aucun media ni aucune partition modifies.' -Extra @{
                IsoPath=[IO.Path]::GetFullPath($IsoPath);IsoSha256=$isoHash
                Images=@($images|Select-Object ImageIndex,ImageName,EditionId,Languages,DefaultUILanguage)
            }|Out-Null
            exit 0
        }finally{if($ownedMount){Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue|Out-Null}}
    }
    if($Action -eq 'ValidateIso'){
        if(-not $IsoPath -or -not(Test-Path -LiteralPath $IsoPath -PathType Leaf)){throw 'ISO absente.'}
        $isoHash=(Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
        $diskImage=Get-DiskImage -ImagePath $IsoPath
        $ownedMount=-not $diskImage.Attached
        try{
            if($ownedMount){$diskImage=Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop}
            $isoVolume=$diskImage|Get-Volume|Where-Object DriveLetter|Select-Object -First 1
            if(-not $isoVolume){throw 'Volume ISO illisible.'}
            $isoRoot="$($isoVolume.DriveLetter):\"
            foreach($requiredFile in @('setup.exe','boot\boot.sdi','sources\boot.wim')){
                if(-not(Test-Path -LiteralPath (Join-Path $isoRoot $requiredFile) -PathType Leaf)){throw "ISO incomplete : $requiredFile"}
            }
            $channel=Assert-BastosMicrosoftSetupSignature -Path (Join-Path $isoRoot 'setup.exe')
            $sourceInstallRelative=Get-BastosInstallImageRelativePath -Root $isoRoot
            $selectedImage=Get-BastosWindows11Image -ImagePath (Join-Path $isoRoot $sourceInstallRelative)
            Save-Result -Success $true -Message ("ISO validee : $($selectedImage.ImageName), index $($selectedImage.ImageIndex). Aucune partition modifiee.") -Extra @{IsoSha256=$isoHash;WindowsEditionId=[string]$selectedImage.EditionId;ImageIndex=[int]$selectedImage.ImageIndex;SigningChannel=$channel}|Out-Null
            exit 0
        }finally{if($ownedMount){Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue|Out-Null}}
    }
    $layout=Get-RecoverySelection
    $script:StorageBaseline=New-BastosStorageSnapshot -Layout $layout
    if($script:RufusOptions){
        if($script:RufusOptions.DiskSafetySnapshot){
            Assert-BastosStorageSnapshot -Expected $script:RufusOptions.DiskSafetySnapshot -Actual $script:StorageBaseline
        }elseif($Action -in @('Provision','BootOnce','DiagnosticBoot')){
            throw 'DISK_PLAN_MISSING : reouvrez Compte, nom du PC, nettoyage et partitions puis verifiez et enregistrez le plan avant de continuer.'
        }
    }
    if($Action -eq 'InspectResult'){
        $evidence=Read-BastosRecoveryEvidence -Layout $layout -Boot:$VerifyBoot
        Save-Result -Success $true -Message 'Preuves Recovery relues sans modification.' -Extra $evidence|Out-Null
        exit 0
    }
    if($Action -eq 'DisarmBoot'){
        if(-not $OperationId -or -not(Test-Administrator)){throw 'Neutralisation refusee : operation identifiee et droits administrateur requis.'}
        $disabled=Disable-BastosOwnedBoot -Layout $layout -OperationId $OperationId
        Save-Result -Success $disabled -Message 'Demarrage de cette operation neutralise.'|Out-Null
        exit 0
    }
    if($Action -eq 'PreparePartition'){
        if(-not(Test-Administrator)){throw 'Des droits administrateur sont requis pour preparer BASTOS_RECOVERY.'}
        if($script:RufusOptions){throw 'PreparePartition doit etre lance avant les options de reinstallation.'}
        $layout=Assert-RecoveryStorageCheckpoint
        $existing=@($layout.RecoveryPartitions)
        if($existing.Count -eq 1){
            $partition=$existing[0]
            $volume=$partition|Get-Volume -ErrorAction Stop
            if($partition.DriveLetter -ne 'D' -or $volume.FileSystem -ne 'NTFS' -or $volume.FileSystemLabel -ne $recoveryLabel -or
                [long]$partition.Size -lt 35GB -or [long]$partition.Size -gt 45GB){
                throw 'BASTOS_RECOVERY existe mais sa lettre, son format ou sa taille ne correspond pas au parcours. Aucune modification.'
            }
            Save-Result -Success $true -Message 'D: BASTOS_RECOVERY est deja presente. Choisis ensuite le compte, le clavier et les partitions.' -Extra @{
                RecoveryExists=$true;PartitionCreated=$false;DiskNumber=$partition.DiskNumber;PartitionNumber=$partition.PartitionNumber
            }|Out-Null
            exit 0
        }
        if(Get-Volume -DriveLetter D -ErrorAction SilentlyContinue){throw 'D: est deja utilise. Aucune partition Windows ne sera reduite.'}
        $required=[long]$RecoverySizeGB*1GB
        $method='UseUnallocatedSpace'
        if([long]$layout.TargetDisk.LargestFreeExtent -lt $required){
            if(-not $layout.TargetIsWindowsDisk){throw 'Le disque cible ne contient pas 40 Go non alloues.'}
            $supported=Get-PartitionSupportedSize -DiskNumber $layout.WindowsDisk.Number -PartitionNumber $layout.OsPartition.PartitionNumber -ErrorAction Stop
            $newOsSize=[long]$layout.OsPartition.Size-$required
            if($newOsSize -lt ([long]$supported.SizeMin+2GB)){
                throw 'Windows ne permet pas de reduire C: de 40 Go avec la marge de securite de 2 Go. Aucune partition modifiee.'
            }
            $method='ShrinkWindows'
        }
        Write-RecoveryProgress -Percent 10 -Phase 'Partition Recovery' -Message 'Verification finale du disque Windows et de D:.' -Step 1
        $layout=Assert-RecoveryStorageCheckpoint
        if(Get-Volume -DriveLetter D -ErrorAction SilentlyContinue){throw 'D: est devenu occupe. Aucune partition Windows ne sera reduite.'}
        Lock-BastosCancellation -CancellationPath $CancellationPath -Reason 'reduction ou creation de la partition Recovery'
        $script:RecoveryWritesStarted=$true
        if($method -eq 'ShrinkWindows'){
            Assert-RecoveryWriteTarget -Partition $layout.OsPartition
            Resize-Partition -DiskNumber $layout.WindowsDisk.Number -PartitionNumber $layout.OsPartition.PartitionNumber -Size $newOsSize -ErrorAction Stop
            $layout=Assert-RecoveryStorageCheckpoint
        }
        Write-RecoveryProgress -Percent 65 -Phase 'Partition Recovery' -Message 'Creation de D: BASTOS_RECOVERY.' -Step 2
        $partition=New-Partition -DiskNumber $layout.TargetDisk.Number -Size $required -DriveLetter D -ErrorAction Stop
        Assert-RecoveryWriteTarget -Partition $partition
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $recoveryLabel -Confirm:$false -Force -ErrorAction Stop|Out-Null
        $verified=Get-Partition -DriveLetter D -ErrorAction Stop
        $volume=Get-Volume -DriveLetter D -ErrorAction Stop
        if($verified.DiskNumber -ne $layout.TargetDisk.Number -or ([guid]$verified.Guid) -ne ([guid]$partition.Guid) -or
            $volume.FileSystem -ne 'NTFS' -or $volume.FileSystemLabel -ne $recoveryLabel){
            throw 'La creation de D: n a pas pu etre verifiee. Consulte le Journal avant de reessayer.'
        }
        Write-RecoveryProgress -Percent 100 -Phase 'Partition Recovery prete' -Message 'D: est cree. Le choix de l edition et la copie de l ISO se feront ensuite.' -Step 3
        Save-Result -Success $true -Message 'D: BASTOS_RECOVERY est creee. Choisis ensuite le compte, le clavier et les partitions; la copie de l ISO aura lieu avant le lancement.' -Extra @{
            RecoveryExists=$true;PartitionCreated=$true;DiskNumber=$verified.DiskNumber;PartitionNumber=$verified.PartitionNumber;Method=$method
        }|Out-Null
        exit 0
    }
    if($Action -eq 'PreviewPlan'){
        if(-not $script:RufusOptions){throw 'Options requises pour afficher le plan.'}
        $partition=@($layout.RecoveryPartitions)[0]
        $preserved=@([int]$partition.PartitionNumber)
        $createEfi=[bool]$script:RufusOptions.KeepOnlyRecoveryPartition
        if(-not $createEfi){$preserved+=@([int]$layout.EfiPartitions[0].PartitionNumber)}
        $parts=@(Get-Partition -DiskNumber $layout.InstallDisk.Number)
        $plan=New-BastosDeploymentPlan -InstallDiskNumber $layout.InstallDisk.Number -Partitions $parts -PreservedPartitionNumbers $preserved -CreateEfi $createEfi -OsPartitionNumber $layout.OsPartition.PartitionNumber
        $rows=@(foreach($part in ($parts|Sort-Object PartitionNumber)){
            $letter=if([int][char]$part.DriveLetter -ne 0){([string]$part.DriveLetter)+':'}else{[string]$part.Type}
            $decision=if($part.PartitionNumber -in $preserved){'CONSERVER'}else{'EFFACER'}
            '{0}  Partition {1}  {2}  {3:N2} Go' -f $decision,$part.PartitionNumber,$letter,([long]$part.Size/1GB)
        })
        $description=('Disque Windows '+$layout.InstallDisk.Number+' - '+$layout.InstallDisk.FriendlyName+' - '+([long]$layout.InstallDisk.Size/1GB).ToString('N2')+' Go'+"
Identifiant GPT : "+$layout.InstallDiskIdentity+"`r`n"+($rows -join "`r`n")+"`r`n"+$(if($createEfi){'EFI, MSR et Windows seront recrees.'}else{'EFI conservee ; MSR et Windows seront recrees.'})+"`r`nAucun autre disque ne sera efface.")
        $null=Assert-RecoveryStorageCheckpoint
        $previewVolume=Get-Volume -DriveLetter D -ErrorAction Stop
        $partitionRows=@(foreach($part in ($parts|Sort-Object PartitionNumber)){
            $location=if([int][char]$part.DriveLetter -ne 0){([string]$part.DriveLetter)+':'}else{[string]$part.Type}
            [ordered]@{Number=[int]$part.PartitionNumber;Guid=[string]$part.Guid;Location=$location;SizeBytes=[long]$part.Size;Decision=$(if($part.PartitionNumber -in $preserved){'CONSERVER'}else{'EFFACER'})}
        })
        $cachePlan=$null
        if($IsoPath){
            $cachePlan=Get-BastosRecoveryCachePlan -Root 'D:\' -IsoPath $IsoPath -CleanupProfile $(if($script:RufusOptions.UseCleanBastosInstallation){'minimal-2'}else{''}) -ImageIndex $script:RufusOptions.WindowsImageIndex -EditionId $script:RufusOptions.WindowsEditionId -LauncherPath (Join-Path $PSScriptRoot 'BASTOS-Start.cmd') -ProbePath (Join-Path $PSScriptRoot 'Bastos.Recovery\BASTOS-Recovery-Probe.exe')
        }
        Save-Result -Success $true -Message $description -Extra @{
            CachePlan=$cachePlan
            DiskSafetySnapshot=$script:StorageBaseline;RecoveryPartitionGuid=[string]$partition.Guid;WindowsDiskIdentity=$layout.InstallDiskIdentity
            TargetDescription=('D: BASTOS_RECOVERY — '+([long]$partition.Size/1GB).ToString('N2')+' Go — disque '+$layout.InstallDisk.Number)
            DeletedPartitions=@($plan.DeleteEntries);PreservedPartitionNumbers=$preserved;CreateEfi=$createEfi
            Partitions=$partitionRows;RecoverySizeBytes=[long]$previewVolume.Size;RecoveryFreeBytes=[long]$previewVolume.SizeRemaining
            DiskDescription=('Disque '+$layout.InstallDisk.Number+' — '+$layout.InstallDisk.FriendlyName+' — '+([long]$layout.InstallDisk.Size/1GB).ToString('N2')+' Go — GPT / UEFI')
        }|Out-Null
        exit 0
    }
    if($Action -eq 'Status'){
        $existing=@($layout.RecoveryPartitions)
        $required=[long]$RecoverySizeGB*1GB
        $canProvision=$false
        $provisionMethod='ExistingRecovery'
        $capacityCheck='ExistingRecovery'
        $maximumShrinkBytes=$null
        if($existing.Count -eq 1){
            $canProvision=$true
        }elseif([long]$layout.TargetDisk.LargestFreeExtent -ge $required){
            $capacityCheck='UnallocatedSpace'
            $canProvision=$true
            $provisionMethod='UseUnallocatedSpace'
        }elseif($layout.TargetIsWindowsDisk){
            $capacityCheck='ExactShrinkLimit'
            try{
                $supported=Get-PartitionSupportedSize -DiskNumber $layout.WindowsDisk.Number -PartitionNumber $layout.OsPartition.PartitionNumber -ErrorAction Stop
                $maximumShrinkBytes=[Math]::Max(0L,([long]$layout.OsPartition.Size-[long]$supported.SizeMin))
                $canProvision=$maximumShrinkBytes -ge ($required+2GB)
            }catch{
                # Get-PartitionSupportedSize exige parfois une elevation meme en
                # lecture seule. Ne jamais convertir une valeur absente en succes.
                # Cette estimation conserve 8 Go libres; Provision refera ensuite
                # la validation exacte sous elevation avant toute reduction.
                $capacityCheck='ConservativeFreeSpaceEstimate'
                $osVolume=Get-Volume -DriveLetter $layout.OsPartition.DriveLetter -ErrorAction Stop
                $canProvision=[long]$osVolume.SizeRemaining -ge ($required+8GB)
            }
            $provisionMethod='ShrinkWindows'
        }else{
            $capacityCheck='UnallocatedSpace'
            $canProvision=[long]$layout.TargetDisk.LargestFreeExtent -ge $required
            $provisionMethod='UseUnallocatedSpace'
        }
        # Le menu des options Windows exige D:. Refuser avant toute écriture si
        # cette lettre appartient déjà à un autre volume.
        $driveD=Get-Volume -DriveLetter D -ErrorAction SilentlyContinue
        if($existing.Count -eq 0 -and $driveD){$canProvision=$false;$capacityCheck='DriveDInUse'}
        $modeText=if($RecoveryMode -eq 'Novice'){
            "Le disque $($layout.WindowsDisk.Number) contenant C: est detecte automatiquement pour Windows et BASTOS_RECOVERY"
        }else{
            "Mode avance : Windows sera installe sur le disque $($layout.InstallDisk.Number) et BASTOS_RECOVERY sur le disque $($layout.TargetDisk.Number)"
        }
        $message=if($existing.Count -eq 1){
            "$modeText. BASTOS_RECOVERY est deja presente sur le disque $($layout.TargetDisk.Number)."
        }elseif($canProvision -and $provisionMethod -eq 'UseUnallocatedSpace'){
            "$modeText. 40 Go d espace non alloue seront utilises sur le disque $($layout.TargetDisk.Number); C: ne sera pas reduit."
        }elseif($canProvision -and $layout.TargetIsWindowsDisk){
            "$modeText. 40 Go seront reserves uniquement sur le disque Windows $($layout.WindowsDisk.Number)."
        }elseif($capacityCheck -eq 'DriveDInUse'){
            "$modeText. La lettre D: est deja utilisee; BASTOS_RECOVERY ne peut pas etre creee avant sa liberation. Aucun disque ne sera modifie."
        }elseif($capacityCheck -eq 'ExactShrinkLimit' -and $null -ne $maximumShrinkBytes){
            "$modeText. Windows autorise $([Math]::Round($maximumShrinkBytes/1GB,1)) Go de reduction de C:, mais 42 Go sont requis avec la marge de securite. Utilise la methode USB ou reserve 40 Go non alloues lors d une installation propre."
        }elseif($layout.TargetIsWindowsDisk){
            "$modeText. La partition Windows ne peut pas etre reduite de 40 Go avec la marge de securite requise."
        }else{
            "$modeText. Le disque $($layout.TargetDisk.Number) ne contient pas 40 Go d espace non alloue; aucune partition de donnees ne sera reduite automatiquement."
        }
        Save-Result -Success $canProvision -Message $message -Extra @{
            RecoveryMode=$RecoveryMode;SelectionSource=$layout.SelectionSource;SafetyValidated=$true
            CurrentWindowsDiskNumber=$layout.WindowsDisk.Number;CurrentWindowsDiskModel=$layout.WindowsDisk.FriendlyName;CurrentWindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsDiskNumber=$layout.WindowsDisk.Number;WindowsDiskModel=$layout.WindowsDisk.FriendlyName;WindowsDiskSize=$layout.WindowsDisk.Size;WindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsTargetDiskNumber=$layout.InstallDisk.Number;WindowsTargetDiskModel=$layout.InstallDisk.FriendlyName;WindowsTargetDiskSize=$layout.InstallDisk.Size;WindowsTargetDiskIdentity=$layout.InstallDiskIdentity
            TargetDiskNumber=$layout.TargetDisk.Number;TargetDiskModel=$layout.TargetDisk.FriendlyName;TargetDiskSize=$layout.TargetDisk.Size;TargetDiskIdentity=$layout.TargetDiskIdentity
            TargetIsWindowsDisk=$layout.TargetIsWindowsDisk;InstallIsCurrentWindowsDisk=$layout.InstallIsCurrentWindowsDisk;RecoveryIsInstallDisk=$layout.RecoveryIsInstallDisk
            DiskNumber=$layout.TargetDisk.Number;DiskModel=$layout.TargetDisk.FriendlyName;DiskSize=$layout.TargetDisk.Size
            CapacityCheck=$capacityCheck;MaximumShrinkBytes=$maximumShrinkBytes;RequiredShrinkBytes=($required+2GB)
            OsPartitionNumber=$layout.OsPartition.PartitionNumber;EfiPartitionNumber=$layout.EfiPartitions[0].PartitionNumber
            RecoveryExists=($existing.Count -eq 1);CanProvision=$canProvision;ProvisionMethod=$provisionMethod;RequiredBytes=$required
        }|Out-Null
        exit 0
    }
    if(-not(Test-Administrator)){throw 'Cette operation doit etre lancee avec les droits administrateur.'}
    if($Action -eq 'DiagnosticBoot'){
        $recovery=@($layout.RecoveryPartitions)
        if($recovery.Count -ne 1){throw "Test Recovery refuse : exactement une partition BASTOS_RECOVERY est requise; trouve : $($recovery.Count)."}
        $partition=$recovery[0]
        $temporary=$false
        Assert-RecoveryWriteTarget -Partition $partition
        if(-not $partition.DriveLetter){$letter=Get-FreeDriveLetter;Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $letter;$temporary=$true}else{$letter=[string]$partition.DriveLetter}
        try{
            $root="${letter}:\"
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
            foreach($required in @('BASTOS-BOOT-ID.txt','BASTOS-ISO.sha256','sources\boot.wim','Application\VERSION.txt')){
                if(-not(Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)){throw "Test Recovery refuse : fichier obligatoire absent : $required"}
            }
            $bootId=(Get-Content -LiteralPath (Join-Path $root 'BASTOS-BOOT-ID.txt') -Raw).Trim()
            if($bootId -notmatch '^\{[0-9a-fA-F-]{36}\}$'){throw 'Test Recovery refuse : identifiant UEFI invalide.'}
            $verified=@(Invoke-BcdEdit /enum $bootId /v) -join "`r`n"
            foreach($expected in @($bootId,'sources\boot.wim','windows\system32\boot\winload.efi')){
                if($verified -notmatch [regex]::Escape($expected)){throw "Test Recovery refuse : entree UEFI incomplete : $expected"}
            }
            # Ne jamais reutiliser un plan de suppression d une tentative
            # precedente. WinPE validera ce manifeste diagnostic frais sans
            # lire ni armer les fichiers du plan destructif.
            if(-not $layout.InstallIsCurrentWindowsDisk -or -not $layout.RecoveryIsInstallDisk){
                throw 'Test Recovery refuse : Windows et BASTOS_RECOVERY doivent se trouver sur le meme disque en mode novice.'
            }
            $currentEfi=@($layout.EfiPartitions)
            if($currentEfi.Count -ne 1){throw "Test Recovery refuse : exactement une partition EFI est requise; trouve : $($currentEfi.Count)."}
            $efiPartition=$currentEfi[0]
            $probePath=Join-Path $PSScriptRoot 'Bastos.Recovery\BASTOS-Recovery-Probe.exe'
            $nativeParts=@(Resolve-BastosNativePartitionNumbers -ProbePath $probePath -DiskNumber $layout.InstallDisk.Number -Partitions @(Get-Partition -DiskNumber $layout.InstallDisk.Number))
            $nativeRecovery=@($nativeParts|Where-Object{[guid]$_.Guid -eq [guid]$partition.Guid -and [long]$_.Offset -eq [long]$partition.Offset})
            $nativeWindows=@($nativeParts|Where-Object{[guid]$_.Guid -eq [guid]$layout.OsPartition.Guid -and [long]$_.Offset -eq [long]$layout.OsPartition.Offset})
            $nativeEfi=@($nativeParts|Where-Object{[guid]$_.Guid -eq [guid]$efiPartition.Guid -and [long]$_.Offset -eq [long]$efiPartition.Offset})
            if($nativeRecovery.Count -ne 1 -or $nativeWindows.Count -ne 1 -or $nativeEfi.Count -ne 1){throw 'Test Recovery refuse : correspondance WinPE des partitions ambigue.'}
            $diagnosticRecords=[ordered]@{
                'BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt'=[string]$layout.InstallDiskIdentity
                'BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt'=('{0}|{1}|{2}|{3}' -f $nativeRecovery[0].PartitionNumber,$partition.Offset,([string]$partition.GptType).Trim('{}').ToLowerInvariant(),([string]$partition.Guid).Trim('{}').ToLowerInvariant())
                'BASTOS-DIAGNOSTIC-WINDOWS-PARTITION.txt'=('{0}|{1}|{2}|{3}' -f $nativeWindows[0].PartitionNumber,$layout.OsPartition.Offset,([string]$layout.OsPartition.GptType).Trim('{}').ToLowerInvariant(),([string]$layout.OsPartition.Guid).Trim('{}').ToLowerInvariant())
                'BASTOS-DIAGNOSTIC-EFI-PARTITION.txt'=('{0}|{1}|{2}|{3}' -f $nativeEfi[0].PartitionNumber,$efiPartition.Offset,([string]$efiPartition.GptType).Trim('{}').ToLowerInvariant(),([string]$efiPartition.Guid).Trim('{}').ToLowerInvariant())
            }
            foreach($record in $diagnosticRecords.GetEnumerator()){
                [IO.File]::WriteAllText((Join-Path $root $record.Key),$record.Value,[Text.Encoding]::ASCII)
            }
            $diagnosticId='Diagnostic-'+[guid]::NewGuid().ToString('N')
            $incompatible=@(
                (Join-Path $root 'BASTOS-AUTO-REINSTALL.token'),
                (Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'),
                (Join-Path $root 'BASTOS-Diagnostic-Result.log'),
                (Join-Path $root 'BASTOS-BOOT-MODE.txt')
            )
            Remove-Item -LiteralPath $incompatible -Force -ErrorAction SilentlyContinue
            if(@($incompatible|Where-Object{Test-Path -LiteralPath $_}).Count -ne 0){throw 'Test Recovery refuse : une autorisation BootOnce precedente n a pas pu etre neutralisee.'}
            [IO.File]::WriteAllText((Join-Path $root 'BASTOS-DIAGNOSTIC-ONLY.token'),$diagnosticId,[Text.Encoding]::ASCII)
            [IO.File]::WriteAllText((Join-Path $root 'BASTOS-BOOT-MODE.txt'),('DIAGNOSTIC|'+$diagnosticId),[Text.Encoding]::ASCII)
            & "$env:SystemRoot\System32\bcdedit.exe" /displayorder $bootId /remove 2>&1|Out-Null
            Invoke-BcdEdit /set '{bootmgr}' displaybootmenu no|Out-Null
            Invoke-BcdEdit /timeout 0|Out-Null
            Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        Invoke-BcdEdit /bootsequence $bootId|Out-Null
            Save-Result -Success $true -Message 'Le test Recovery non destructif est programme avec une photographie fraiche des partitions.' -Extra @{BootId=$bootId;DiagnosticOnly=$true;FreshPartitionManifest=$true;RecoveryPartitionNumber=$partition.PartitionNumber}|Out-Null
            exit 0
        }finally{
            if($temporary){Remove-PartitionAccessPath -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath "${letter}:\" -ErrorAction SilentlyContinue}
        }
    }
    if($Action -eq 'Provision'){
        Write-RecoveryProgress -Percent 2 -Phase 'Préparation' -Message 'Vérification de l ISO et des paramètres de réinstallation.' -Step 1
        if(-not $IsoPath -or -not(Test-Path -LiteralPath $IsoPath -PathType Leaf) -or [IO.Path]::GetExtension($IsoPath) -ne '.iso'){throw 'Choisis une ISO BASTOS valide avant de preparer la recuperation.'}
        if($GenerateAnswerFile){
            if(-not $AnswerFilePath){throw 'RECOVERY_PROFILE_FAILED : chemin du profil absent.'}
            $profileArgs=@{OfficialIsoPath=$IsoPath;OutputPath=$AnswerFilePath;WindowsLocale=$WindowsLocale;KeyboardLayout=$KeyboardLayout;LocalUserName=$LocalUserName;PostInstallMode=$PostInstallMode}
            if($OptionsPath){$profileArgs.OptionsPath=$OptionsPath}
            & (Join-Path $PSScriptRoot 'New-BASTOS-Official-Unattend.ps1') @profileArgs|Out-Null
            if(-not(Test-Path -LiteralPath $AnswerFilePath -PathType Leaf)){throw 'RECOVERY_PROFILE_FAILED : profil de reinstallation absent apres creation.'}
        }
        Write-RecoveryProgress -Percent 5 -Phase 'Empreinte ISO' -Message 'Calcul de l empreinte SHA256 de l ISO sélectionnée.' -Step 2
        $isoHash=(Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
        if($script:RufusOptions){
            Assert-BastosEditionSelection -IsoHash $isoHash -Options $script:RufusOptions
            if($EditionIndex -gt 0 -and $EditionIndex -ne [int]$script:RufusOptions.WindowsImageIndex){throw 'Index Windows incoherent avec les options.'}
            $EditionIndex=[int]$script:RufusOptions.WindowsImageIndex
        }
        $requiredMediaFiles=@('setup.exe','boot\boot.sdi','sources\boot.wim')
        Write-RecoveryProgress -Percent 9 -Phase 'Validation ISO' -Message 'Montage en lecture seule et contrôle de l edition Windows 11.' -Step 3
        $image=Mount-DiskImage -ImagePath $IsoPath -PassThru
        try {
            $isoVolume=$image|Get-Volume
            if(-not $isoVolume.DriveLetter){throw 'Impossible de lire le contenu ISO.'}
            $isoRoot="$($isoVolume.DriveLetter):\"
            $sourceInstallRelative=Get-BastosInstallImageRelativePath -Root $isoRoot
            $requiredMediaFiles+=@($sourceInstallRelative)
            foreach($requiredFile in $requiredMediaFiles){
                if(-not(Test-Path -LiteralPath(Join-Path $isoRoot $requiredFile)-PathType Leaf)){throw "ISO incomplete : $requiredFile absent."}
            }
            $signingChannel=Assert-BastosMicrosoftSetupSignature -Path(Join-Path $isoRoot 'setup.exe')

            $isoBootHash=(Get-FileHash -LiteralPath(Join-Path $isoRoot 'sources\boot.wim')-Algorithm SHA256).Hash
            Write-RecoveryProgress -Percent 10 -Phase 'Verification de l edition Windows' -Message 'Verification du choix enregistre dans les options de reinstallation.' -Step 3
            $proImage=Get-BastosWindows11Image -ImagePath (Join-Path $isoRoot $sourceInstallRelative)
            if($script:RufusOptions){Assert-BastosPreparedImageSelection -Image $proImage -Options $script:RufusOptions}
            $isoInstallHash=(Get-FileHash -LiteralPath(Join-Path $isoRoot $sourceInstallRelative)-Algorithm SHA256).Hash
            $proImageIndex=[int]$proImage.ImageIndex
            Write-RecoveryProgress -Percent 18 -Phase 'Analyse du disque' -Message "$($proImage.ImageName) valide (index $proImageIndex). Analyse sécurisée de la partition Recovery." -Step 4

            $layout=Assert-RecoveryStorageCheckpoint
            # Quand D: est libre, Windows peut l'attribuer provisoirement a l'ISO.
            # Liberer seulement notre propre montage avant de creer Recovery sur D:.
            $remountIsoAfterRecovery=$false
            if(@($layout.RecoveryPartitions).Count -eq 0 -and $isoVolume.DriveLetter -eq 'D'){
                Dismount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null
                $remountIsoAfterRecovery=$true
            }
            # Valider complètement l ISO avant de créer ou réduire une partition.
            if(@($layout.RecoveryPartitions).Count -eq 0 -and (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue)){
                throw 'La lettre D: est deja utilisee. Aucune partition Windows ne sera reduite.'
            }
            Lock-BastosCancellation -CancellationPath $CancellationPath -Reason 'écritures sur la partition Recovery et configuration UEFI'
            $script:RecoveryWritesStarted=$true
            $recoveryPartition=@($layout.RecoveryPartitions)|Select-Object -First 1
            $required=[long]$RecoverySizeGB*1GB
            if(-not $recoveryPartition){
                if([long]$layout.TargetDisk.LargestFreeExtent -ge $required){
                    # Une zone deja non allouee sur le disque Windows n exige
                    # aucune reduction de C: ni deplacement de metadonnees NTFS.
                }elseif($layout.TargetIsWindowsDisk){
                    $supported=Get-PartitionSupportedSize -DiskNumber $layout.WindowsDisk.Number -PartitionNumber $layout.OsPartition.PartitionNumber
                    $newOsSize=[long]$layout.OsPartition.Size-$required
                    if($newOsSize -lt ([long]$supported.SizeMin+2GB)){throw 'La partition Windows ne peut pas etre reduite de 40 Go avec une marge de securite de 2 Go.'}
                    Assert-RecoveryWriteTarget -Partition $layout.OsPartition
                    Resize-Partition -DiskNumber $layout.WindowsDisk.Number -PartitionNumber $layout.OsPartition.PartitionNumber -Size $newOsSize
                }else{
                    if([long]$layout.TargetDisk.LargestFreeExtent -lt $required){throw "Le disque $($layout.TargetDisk.Number) ne contient pas 40 Go d espace non alloue. BASTOS refuse de reduire une partition de donnees automatiquement."}
                }
                $layout=Assert-RecoveryStorageCheckpoint
                $recoveryPartition=New-Partition -DiskNumber $layout.TargetDisk.Number -Size $required -DriveLetter D
                Assert-RecoveryWriteTarget -Partition $recoveryPartition
                Format-Volume -Partition $recoveryPartition -FileSystem NTFS -NewFileSystemLabel $recoveryLabel -Confirm:$false -Force|Out-Null
            }
            if($remountIsoAfterRecovery){
                $image=Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
                $isoVolume=$image|Get-Volume -ErrorAction Stop
                if(-not $isoVolume.DriveLetter -or $isoVolume.DriveLetter -eq 'D'){
                    throw 'L ISO ne peut pas etre relue sans occuper D: BASTOS_RECOVERY.'
                }
                $isoRoot="$($isoVolume.DriveLetter):\"
                if((Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash -ne $isoHash){
                    throw 'ISO modifiee entre la validation et la copie.'
                }
            }
            if($recoveryPartition.DiskNumber -ne $layout.TargetDisk.Number){throw 'La partition Recovery obtenue ne se trouve pas sur le disque valide. Operation interrompue.'}
            if($RecoveryMode -eq 'Novice' -and $recoveryPartition.DiskNumber -ne $layout.WindowsDisk.Number){throw 'Securite novice : BASTOS_RECOVERY doit obligatoirement etre sur le disque Windows.'}
            # Si un espace libre est immédiatement situé après BASTOS_RECOVERY,
            # l'attribuer à cette partition. Cela évite de laisser un petit reliquat
            # inutilisé en fin de disque sans déplacer Windows ni la récupération.
            $recoverySupported=Get-PartitionSupportedSize -DiskNumber $recoveryPartition.DiskNumber -PartitionNumber $recoveryPartition.PartitionNumber
            if(-not $script:RufusOptions -and [long]$recoverySupported.SizeMax -gt ([long]$recoveryPartition.Size + 1MB)){
                Assert-RecoveryWriteTarget -Partition $recoveryPartition
                Resize-Partition -DiskNumber $recoveryPartition.DiskNumber -PartitionNumber $recoveryPartition.PartitionNumber -Size ([long]$recoverySupported.SizeMax)
                $recoveryPartition=Get-Partition -DiskNumber $recoveryPartition.DiskNumber -PartitionNumber $recoveryPartition.PartitionNumber
            }
            Assert-RecoveryWriteTarget -Partition $recoveryPartition
            $letter=[string]$recoveryPartition.DriveLetter
            if(-not $letter){$letter=Get-FreeDriveLetter;Set-Partition -DiskNumber $layout.TargetDisk.Number -PartitionNumber $recoveryPartition.PartitionNumber -NewDriveLetter $letter}
            Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
            $root="${letter}:\";$mediaRoot=$root;$appRoot=Join-Path $root 'Application';New-Item -ItemType Directory -Path $appRoot -Force|Out-Null
            $storedHashPath=Join-Path $root 'BASTOS-ISO.sha256'
            $mediaStatePath=Join-Path $root 'BASTOS-MEDIA-STATE.json'
            $launcherPath=Join-Path $PSScriptRoot 'BASTOS-Start.cmd'
            $probePath=Join-Path $PSScriptRoot 'Bastos.Recovery\BASTOS-Recovery-Probe.exe'
            $launcherHash=(Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
            $probeHash=(Get-FileHash -LiteralPath $probePath -Algorithm SHA256).Hash
            $currentMediaState=$null
            if(Test-Path -LiteralPath $mediaStatePath -PathType Leaf){try{$currentMediaState=Get-Content -LiteralPath $mediaStatePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
            Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
            Write-RecoveryProgress -Percent 34 -Phase 'Sauvegarde des pilotes' -Message 'Export vérifié des pilotes tiers sélectionnés avant la préparation du média.' -Step 5
            $null=New-BastosDriverBackup -Root $root -Selected:([bool]($script:RufusOptions -and $script:RufusOptions.PreserveDrivers)) -SetupPath (Join-Path $isoRoot 'setup.exe')
            $cachePlan=Get-BastosRecoveryCachePlan -Root $root -IsoPath $IsoPath -CleanupProfile $(if($script:RufusOptions -and $script:RufusOptions.UseCleanBastosInstallation){'minimal-2'}else{''}) -ImageIndex $proImageIndex -EditionId ([string]$proImage.EditionId) -LauncherPath $launcherPath -ProbePath $probePath
            if($cachePlan.IsoSha256 -ne $isoHash){throw 'ISO modifiee pendant la preparation.'}
            if($cachePlan.Mode -ne 'Full'){
                try{Assert-BastosWimSelection -Metadata (Get-BastosWimMetadata -ImagePath (Join-Path $root 'sources\install.wim')) -ImageIndex $proImageIndex -EditionId ([string]$proImage.EditionId)}catch{
                    $cachePlan.Mode='Full';$cachePlan.RequiredFreeBytes=([long](Get-Item -LiteralPath $IsoPath).Length+2GB)
                }
            }
            if($cachePlan.Mode -eq 'Boot'){
                # Use the pristine ISO boot image, never accumulate edits on an
                # already patched boot.wim. Stage beside the active file so the
                # final NTFS replacement is atomic and leaves install.wim alone.
                $cachePlan.RequiredFreeBytes=[Math]::Max([long]$cachePlan.RequiredFreeBytes,([long](Get-Item -LiteralPath (Join-Path $isoRoot 'sources\boot.wim')).Length+2GB))
            }
            $recoveryVolume=Get-Volume -DriveLetter $letter
            if([long]$recoveryVolume.SizeRemaining -lt [long]$cachePlan.RequiredFreeBytes){
                throw ('Espace insuffisant sur BASTOS_RECOVERY pour le plan '+$cachePlan.Mode+' et sa marge de securite. Aucun ancien media supprime.')
            }
            if($cachePlan.Mode -eq 'Full'){
                Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
                $stage=Join-Path $root ('BASTOS-Media-Staging-'+[guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $stage -Force|Out-Null
                try {
                    Invoke-RecoveryMediaCopy -Source $isoRoot -Destination $stage -StartPercent 35 -EndPercent 64
                    Write-RecoveryProgress -Percent 66 -Phase 'Vérification du média' -Message 'Contrôle des fichiers Windows copiés et de leurs empreintes.' -Step 6
                    foreach($requiredFile in $requiredMediaFiles){
                        if(-not(Test-Path -LiteralPath(Join-Path $stage $requiredFile)-PathType Leaf)){throw "Copie temporaire incomplete : $requiredFile absent. L ancien media reste intact."}
                    }
                    if((Get-FileHash -LiteralPath(Join-Path $stage 'sources\boot.wim')-Algorithm SHA256).Hash -ne $isoBootHash){throw 'La verification temporaire de boot.wim a echoue. L ancien media reste intact.'}
                    if((Get-FileHash -LiteralPath(Join-Path $stage $sourceInstallRelative)-Algorithm SHA256).Hash -ne $isoInstallHash){throw 'La verification temporaire de l image Windows a echoue. L ancien media reste intact.'}
                    if($sourceInstallRelative -eq 'sources\install.esd'){
                        Write-RecoveryProgress -Percent 68 -Phase 'Conversion ESD vers WIM' -Message 'Conservation des editions et de leurs index pour la reinstallation.' -Step 7
                        $sourceEsd=Join-Path $stage $sourceInstallRelative
                        $destinationWim=Join-Path $stage 'sources\install.wim'
                        $catalog=@(Get-WindowsImage -ImagePath $sourceEsd -ErrorAction Stop|Sort-Object ImageIndex)
                        $nextIndex=1
                        foreach($entry in $catalog){
                            if([int]$entry.ImageIndex -ne $nextIndex){throw 'Catalogue ESD non consecutif : conversion refusee pour proteger le choix d edition.'}
                            Export-WindowsImage -SourceImagePath $sourceEsd -SourceIndex $nextIndex -DestinationImagePath $destinationWim -CompressionType Max -CheckIntegrity -ErrorAction Stop|Out-Null
                            $nextIndex++
                        }
                        $converted=Get-WindowsImage -ImagePath $destinationWim -Index $proImageIndex -ErrorAction Stop
                        if($converted.EditionId -ne $proImage.EditionId -or $converted.ImageName -ne $proImage.ImageName){throw 'L edition exportee ne correspond pas au choix. Preparation interrompue.'}
                        Remove-Item -LiteralPath $sourceEsd -Force
                    }
                    Write-RecoveryProgress -Percent 69 -Phase 'Nettoyage de l image Windows' -Message 'Suppression des anciennes réponses OOBE embarquées dans install.wim.' -Step 7
                    $preparedInstallHash=Remove-BastosEmbeddedPantherAnswers -InstallWimPath (Join-Path $stage 'sources\install.wim') -ImageIndex $proImageIndex -CleanBastos:([bool]($script:RufusOptions -and $script:RufusOptions.UseCleanBastosInstallation)) -CleanupReportPath (Join-Path $stage 'BASTOS-Minimal-Offline.json')
                    $bootUpdate=Update-RecoveryBootImage -BootWimPath (Join-Path $stage 'sources\boot.wim') -LauncherPath $launcherPath -ProbePath $probePath
                    $preparedCompatibilityMode=[string]$bootUpdate.CompatibilityMode
                    $preparedEmbeddedLauncherHash=[string]$bootUpdate.EmbeddedLauncherSha256
                    Write-RecoveryProgress -Percent 76 -Phase 'Environnement de démarrage' -Message 'Le lanceur BASTOS a été intégré à Windows PE.' -Step 7
                    $preparedBootHash=(Get-FileHash -LiteralPath(Join-Path $stage 'sources\boot.wim')-Algorithm SHA256).Hash

                    $protectedNames=@(
                        'Application','ISO Bastos','BASTOS-Diagnostics','BASTOS-USER-DATA','BASTOS-Drivers','BASTOS-DRIVERS.enabled','System Volume Information','$RECYCLE.BIN',
                        'BASTOS-BOOT-ID.txt','BASTOS-BOOT-ENTRY.txt','BASTOS-ISO.sha256','BASTOS-MEDIA-STATE.json',
                        'BASTOS-RECOVERY-SELECTION.json','BASTOS-WINDOWS-DISK-ID.txt','BASTOS-WINDOWS-DISK-CHECK.txt',
                        'BASTOS-LAST-KNOWN-GOOD.json','BASTOS-LAYOUT-DISK0.ok','BASTOS-DEPLOY-DISKPART.txt',
                        'BASTOS-DELETE-PARTITIONS.txt','BASTOS-CREATE-PARTITIONS.txt','BASTOS-RECOVERY-PARTITION.txt',
                        'BASTOS-EFI-PARTITION.txt','BASTOS-WINDOWS-PARTITION.txt','BASTOS-Recovery-Unattend.xml',
                        'BASTOS-AUTO-REINSTALL.token','BASTOS-Recovery.log'
                    )
                    $oldMediaNames=@('boot','efi','sources','support','x64','x86','autorun.inf','bootmgr','bootmgr.efi','setup.exe','autounattend.xml')
                    if(Test-Path -LiteralPath $mediaStatePath -PathType Leaf){
                        try{$oldMediaNames+=@((Get-Content -LiteralPath $mediaStatePath -Raw|ConvertFrom-Json).RootEntries)}catch{}
                    }
                    Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
                    foreach($name in @($oldMediaNames|Sort-Object -Unique)){
                        if([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -ne $name -or $name -in $protectedNames){continue}
                        $oldPath=Join-Path $root $name
                        if(Test-Path -LiteralPath $oldPath){Remove-Item -LiteralPath $oldPath -Recurse -Force}
                    }
                    $stageEntries=@(Get-ChildItem -LiteralPath $stage -Force)
                    foreach($entry in $stageEntries){
                        if($entry.Name -in $protectedNames){throw "L ISO tente de remplacer un element BASTOS protege : $($entry.Name)"}
                        $target=Join-Path $root $entry.Name
                        if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Recurse -Force}
                        Move-Item -LiteralPath $entry.FullName -Destination $root -Force
                    }
                } finally {
                    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
                }
            }elseif($cachePlan.Mode -eq 'Boot'){
                Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
                $activeBoot=Join-Path $root 'sources\boot.wim'
                $stagedBoot=Join-Path $root ('sources\BASTOS-Boot-Staging-'+[guid]::NewGuid().ToString('N')+'.wim')
                try{
                    Copy-Item -LiteralPath (Join-Path $isoRoot 'sources\boot.wim') -Destination $stagedBoot -ErrorAction Stop
                    if((Get-FileHash -LiteralPath $stagedBoot -Algorithm SHA256).Hash -ne $isoBootHash){throw 'Copie temporaire du demarrage non conforme.'}
                    Write-RecoveryProgress -Percent 69 -Phase 'Actualisation du démarrage' -Message 'Image Windows conservée ; seul Windows PE est reconstruit.' -Step 7
                    $bootUpdate=Update-RecoveryBootImage -BootWimPath $stagedBoot -LauncherPath $launcherPath -ProbePath $probePath
                    $preparedBootHash=(Get-FileHash -LiteralPath $stagedBoot -Algorithm SHA256).Hash
                    $preparedInstallHash=[string]$currentMediaState.InstallWimSha256
                    $preparedCompatibilityMode=[string]$bootUpdate.CompatibilityMode
                    $preparedEmbeddedLauncherHash=[string]$bootUpdate.EmbeddedLauncherSha256
                    Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
                    if([IO.File]::Exists($activeBoot)){[IO.File]::Replace($stagedBoot,$activeBoot,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($stagedBoot,$activeBoot)}
                }finally{
                    # A single caller-created file, never a recursive cache purge.
                    if([IO.File]::Exists($stagedBoot)){[IO.File]::Delete($stagedBoot)}
                }
            }else{
                $preparedBootHash=[string]$currentMediaState.BootWimSha256
                $preparedInstallHash=[string]$currentMediaState.InstallWimSha256
                $preparedCompatibilityMode=if($currentMediaState.PSObject.Properties['BootWimCompatibilityMode']){[string]$currentMediaState.BootWimCompatibilityMode}else{'ExactLauncher'}
                $preparedEmbeddedLauncherHash=if($currentMediaState.PSObject.Properties['EmbeddedRecoveryLauncherSha256']){[string]$currentMediaState.EmbeddedRecoveryLauncherSha256}else{$launcherHash}
                Write-RecoveryProgress -Percent 72 -Phase 'Média déjà synchronisé' -Message 'L ISO et le lanceur Recovery sont déjà présents et vérifiés.' -Step 6
            }

            if((Get-FileHash -LiteralPath(Join-Path $root 'sources\boot.wim')-Algorithm SHA256).Hash -ne $preparedBootHash){throw 'Le boot.wim Recovery actif ne correspond pas au lanceur BASTOS verifie.'}
            if((Get-FileHash -LiteralPath(Join-Path $root 'sources\install.wim')-Algorithm SHA256).Hash -ne $preparedInstallHash){throw 'Le install.wim actif ne correspond pas a l image nettoyee et verifiee.'}
            $effectiveAnswerFile=$AnswerFilePath
            # Optional source files can force an edition or product key.
            # Only the prepared copy changes; the source ISO stays intact.
            foreach($editionOverride in @('sources\ei.cfg','sources\PID.txt')){
                $overridePath=Join-Path $root $editionOverride
                if(Test-Path -LiteralPath $overridePath){Remove-Item -LiteralPath $overridePath -Force -ErrorAction Stop}
            }
            if($UseEmbeddedProfile){
                if($PostInstallMode -ne 'BastosAutonomous'){throw 'Le profil integre est reserve aux ISO BASTOS personnalisees.'}
                $effectiveAnswerFile=Join-Path $isoRoot 'autounattend.xml'
            }
            if(-not $effectiveAnswerFile -or -not(Test-Path -LiteralPath $effectiveAnswerFile -PathType Leaf)){
                throw 'Le fichier de réponses automatique associé à l ISO officielle est absent.'
            }
            [xml]$officialAnswer=Get-Content -LiteralPath $effectiveAnswerFile -Raw -Encoding UTF8
            if($officialAnswer.DocumentElement.LocalName -ne 'unattend'){throw 'Le fichier de réponses automatique est invalide.'}
            $preferredUILanguage=if($script:RufusOptions){[string]$script:RufusOptions.WindowsUILanguage}else{$officialAnswer.SelectSingleNode("//*[local-name()='UILanguage']").InnerText}
            $imageUILanguage=Get-BastosImageUILanguage -Metadata (Get-BastosWimMetadata -ImagePath (Join-Path $root 'sources\install.wim')) -ImageIndex $proImageIndex -PreferredLanguage $preferredUILanguage
            Copy-Item -LiteralPath $effectiveAnswerFile -Destination (Join-Path $root 'autounattend.xml') -Force
            New-RecoveryAnswerFile -SourcePath (Join-Path $root 'autounattend.xml') -DestinationPath (Join-Path $root 'BASTOS-Recovery-Unattend.xml') -ProImageIndex $proImageIndex -EditionId ([string]$proImage.EditionId) -ImageUILanguage $imageUILanguage -PostInstallMode $PostInstallMode
            Write-RecoveryProgress -Percent 84 -Phase 'Installation automatique' -Message 'Langue, clavier, compte local et disque cible ont été enregistrés.' -Step 8
            $isoItem=Get-Item -LiteralPath $IsoPath -Force
            $mediaState=[ordered]@{Schema=9;CleanupProfile=$(if($script:RufusOptions -and $script:RufusOptions.UseCleanBastosInstallation){'minimal-2'}else{''});WindowsCacheRevision=1;BootCacheRevision=1;SourceBootWimBytes=[long](Get-Item -LiteralPath (Join-Path $isoRoot 'sources\boot.wim')).Length;AccountFlowVersion=16;AccountStrategy='BastOS-Local-NonSID500';ComputerNameStrategy='SpecializeThenSetupCompleteVerification';PostInstallMode=$PostInstallMode;ProImageIndex=$proImageIndex;WindowsEditionId=[string]$proImage.EditionId;IsoPath=[IO.Path]::GetFullPath($isoItem.FullName);IsoLength=[long]$isoItem.Length;IsoLastWriteUtc=$isoItem.LastWriteTimeUtc.ToString('o');IsoLastWriteUtcTicks=[long]$isoItem.LastWriteTimeUtc.Ticks;IsoSha256=$isoHash;SigningChannel=$signingChannel;SourceBootWimSha256=$isoBootHash;BootWimSha256=$preparedBootHash;RecoveryLauncherSha256=$launcherHash;RecoveryProbeSha256=$probeHash;BootWimCompatibilityMode=$preparedCompatibilityMode;EmbeddedRecoveryLauncherSha256=$preparedEmbeddedLauncherHash;InstallWimSha256=$preparedInstallHash;InstallWimSanitized=$true;SanitizedImageIndex=$proImageIndex;WindowsImageName=[string]$proImage.ImageName;RootEntries=@(Get-ChildItem -LiteralPath $isoRoot -Force|ForEach-Object Name);VerifiedUtc=[DateTime]::UtcNow.ToString('o')}
            [IO.File]::WriteAllText($mediaStatePath,($mediaState|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        } finally {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
        }
        Write-RecoveryProgress -Percent 88 -Phase 'Synchronisation BASTOS' -Message 'Copie de l application et des scripts de restauration.' -Step 9
        Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
        $sourceApplication=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\');$targetApplication=[IO.Path]::GetFullPath($appRoot).TrimEnd('\');if(-not [string]::Equals($sourceApplication,$targetApplication,[StringComparison]::OrdinalIgnoreCase)){& robocopy.exe $PSScriptRoot $appRoot /MIR /R:2 /W:2 /XJ /XD Backups Logs /NFL /NDL /NP|Out-Null;if($LASTEXITCODE -ge 8){throw "La copie de l application a echoue (Robocopy $LASTEXITCODE)."}}
        if($PostInstallMode -eq 'BastosAutonomous'){Sync-BastosAutonomousMediaPayload -ApplicationRoot $appRoot -MediaRoot $root|Out-Null}else{Set-BastosRufusMediaProfile -ApplicationRoot $appRoot -MediaRoot $root}
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-ISO.sha256'),$isoHash,[Text.UTF8Encoding]::new($false))
        Write-RecoveryProgress -Percent 94 -Phase 'Démarrage UEFI' -Message 'Création et contrôle de l entrée de démarrage unique.' -Step 10
        # La commande /enum renvoie parfois 0 alors que l objet est absent (notamment sur Windows francais).
        # Une creation idempotente est plus fiable : l erreur "existe deja" est volontairement ignoree.
        & "$env:SystemRoot\System32\bcdedit.exe" /create '{ramdiskoptions}' /d 'Options ramdisk BASTOS' 2>&1|Out-Null
        Invoke-BcdEdit /set '{ramdiskoptions}' ramdisksdidevice "partition=${letter}:"|Out-Null;Invoke-BcdEdit /set '{ramdiskoptions}' ramdisksdipath '\boot\boot.sdi'|Out-Null
        $bootIdPath=Join-Path $root 'BASTOS-BOOT-ID.txt';$guid=''
        if(Test-Path -LiteralPath $bootIdPath -PathType Leaf){
            $candidate=(Get-Content -LiteralPath $bootIdPath -Raw).Trim()
            if($candidate -match '^\{[0-9a-fA-F-]{36}\}$'){
                # BCDEdit /enum peut retourner 0 tout en affichant "aucun objet"
                # pour un GUID orphelin. Exiger donc que la sortie contienne
                # réellement l'identifiant avant de le réutiliser.
                $candidateOutput=@(& "$env:SystemRoot\System32\bcdedit.exe" /enum $candidate /v 2>&1)
                $candidateText=$candidateOutput -join "`r`n"
                if($LASTEXITCODE -eq 0 -and $candidateText -match [regex]::Escape($candidate)){$guid=$candidate}
            }
        }
        if(-not $guid){$created=Invoke-BcdEdit /create /d $bootDescription /application osloader;$guid=[regex]::Match(($created -join ' '),'\{[0-9a-fA-F-]{36}\}').Value}
        if(-not $guid){throw 'Identifiant de demarrage BASTOS introuvable.'}
        Invoke-BcdEdit /set $guid device "ramdisk=[${letter}:]\sources\boot.wim,{ramdiskoptions}"|Out-Null;Invoke-BcdEdit /set $guid osdevice "ramdisk=[${letter}:]\sources\boot.wim,{ramdiskoptions}"|Out-Null;Invoke-BcdEdit /set $guid path '\windows\system32\boot\winload.efi'|Out-Null;Invoke-BcdEdit /set $guid systemroot '\windows'|Out-Null;Invoke-BcdEdit /set $guid winpe yes|Out-Null;Invoke-BcdEdit /set $guid detecthal yes|Out-Null
        if($signingChannel -eq 'Insider'){
            Invoke-BcdEdit /set $guid flightsigning yes|Out-Null
        }else{
            & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue $guid flightsigning 2>&1|Out-Null
        }
        $bootEntry=@(Invoke-BcdEdit /enum $guid /v)
        $bootEntryText=$bootEntry -join "`r`n"
        foreach($requiredBootValue in @($guid,'sources\boot.wim','windows\system32\boot\winload.efi')){
            if($bootEntryText -notmatch [regex]::Escape($requiredBootValue)){
                throw "L entree BCD BASTOS ne contient pas la valeur attendue : $requiredBootValue"
            }
        }
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-BOOT-ENTRY.txt'),$bootEntryText,[Text.UTF8Encoding]::new($false))
        # L'entree reste utilisable par /bootsequence, sans imposer un menu permanent.
        & "$env:SystemRoot\System32\bcdedit.exe" /displayorder $guid /remove 2>&1|Out-Null
        Invoke-BcdEdit /set '{bootmgr}' displaybootmenu no|Out-Null
        Invoke-BcdEdit /timeout 0|Out-Null
        Set-Content -LiteralPath $bootIdPath -Value $guid -Encoding Ascii
        Set-Partition -DiskNumber $layout.TargetDisk.Number -PartitionNumber $recoveryPartition.PartitionNumber -NoDefaultDriveLetter $false
        Assert-RecoveryWriteTarget -Partition $recoveryPartition -Letter $letter
        $selectionState=[ordered]@{
            Schema=3;OperationId=$OperationId;RecoveryMode=$RecoveryMode;PostInstallMode=$PostInstallMode;SelectionSource=$layout.SelectionSource
            CurrentWindowsDiskNumber=[int]$layout.WindowsDisk.Number;CurrentWindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsTargetDiskNumber=[int]$layout.InstallDisk.Number;WindowsTargetDiskIdentity=$layout.InstallDiskIdentity
            RecoveryDiskNumber=[int]$layout.TargetDisk.Number;RecoveryDiskIdentity=$layout.TargetDiskIdentity
            RecoveryPartitionNumber=[int]$recoveryPartition.PartitionNumber
            RecoveryPartitionGuid=([string]$recoveryPartition.Guid).Trim().ToUpperInvariant()
            RecoveryPartitionOffset=[long]$recoveryPartition.Offset
            RecoveryPartitionSize=[long]$recoveryPartition.Size
            RecoveryPartitionGptType=([string]$recoveryPartition.GptType).Trim().ToUpperInvariant()
            RecoveryIsInstallDisk=[bool]$layout.RecoveryIsInstallDisk;ValidatedUtc=[DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-RECOVERY-SELECTION.json'),($selectionState|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        # Provision prépare seulement le média. Tout armement d'une ancienne
        # tentative doit être neutralisé. Les variantes de disque sont propres
        # à une tentative BootOnce et peuvent contenir un ancien fichier de
        # réponses : elles seront toutes recréées juste avant le prochain boot.
        Get-ChildItem -LiteralPath $root -Filter 'BASTOS-Recovery-Unattend-Disk*.xml' -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath `
            (Join-Path $root 'BASTOS-AUTO-REINSTALL.token'),
            (Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-ONLY.token'),
            (Join-Path $root 'BASTOS-Diagnostic-Result.log'),
            (Join-Path $root 'BASTOS-BOOT-MODE.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-WINDOWS-PARTITION.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-EFI-PARTITION.txt') `
            -Force -ErrorAction SilentlyContinue
        Write-RecoveryProgress -Percent 100 -Phase 'BASTOS_RECOVERY prête' -Message 'Le média, l installation automatique et le démarrage UEFI sont vérifiés.' -Step 10
        Save-Result -Success $true -Message ("BASTOS_RECOVERY est prete : $($proImage.ImageName), index $proImageIndex. Son entree UEFI a ete creee.") -Extra @{
            WindowsEditionId=[string]$proImage.EditionId;ImageIndex=$proImageIndex;ImageName=[string]$proImage.ImageName
            RecoveryMode=$RecoveryMode;SelectionSource=$layout.SelectionSource;SafetyValidated=$true
            CurrentWindowsDiskNumber=$layout.WindowsDisk.Number;CurrentWindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsTargetDiskNumber=$layout.InstallDisk.Number;WindowsTargetDiskIdentity=$layout.InstallDiskIdentity
            TargetDiskNumber=$layout.TargetDisk.Number;TargetDiskIdentity=$layout.TargetDiskIdentity;TargetIsWindowsDisk=$layout.TargetIsWindowsDisk
            RecoveryIsInstallDisk=$layout.RecoveryIsInstallDisk
            DiskNumber=$layout.TargetDisk.Number;RecoveryPartitionNumber=$recoveryPartition.PartitionNumber;BootId=$guid;IsoSha256=$isoHash
        }|Out-Null
        exit 0
    }
    if($Action -eq 'BootOnce'){
        if($RecoveryMode -ne 'Novice'){
            throw 'BASTOS autorise la reinstallation automatique uniquement en mode novice : Windows et BASTOS_RECOVERY doivent etre sur le disque contenant actuellement C:.'
        }
        $recovery=@($layout.RecoveryPartitions)
        if($recovery.Count -ne 1){throw "Reinstallation refusee : exactement une partition BASTOS_RECOVERY est requise sur le disque choisi; trouve : $($recovery.Count)."}
        $partition=$recovery[0]
        $volume=$partition|Get-Volume -ErrorAction Stop
        $temporary=$false
        Assert-RecoveryWriteTarget -Partition $partition
        if(-not $partition.DriveLetter){$letter=Get-FreeDriveLetter;Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $letter;$temporary=$true}else{$letter=[string]$partition.DriveLetter}
        $root="${letter}:\"
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        $bootId=(Get-Content -LiteralPath (Join-Path $root 'BASTOS-BOOT-ID.txt') -Raw).Trim()
        if($bootId -notmatch '^\{[0-9a-fA-F-]{36}\}$'){throw 'Identifiant de demarrage BASTOS invalide.'}
        $selectionPath=Join-Path $root 'BASTOS-RECOVERY-SELECTION.json'
        if(-not(Test-Path -LiteralPath $selectionPath -PathType Leaf)){throw 'Reinstallation refusee : la selection securisee des disques est absente. Synchronise de nouveau BASTOS_RECOVERY.'}
        $selectionState=Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8|ConvertFrom-Json
        if([int]$selectionState.Schema -ne 3){throw 'Reinstallation refusee : la selection securisee des partitions doit etre synchronisee avec la version actuelle de BASTOS.'}
        $savedPostInstallMode=if($selectionState.PSObject.Properties['PostInstallMode']){[string]$selectionState.PostInstallMode}else{'WindowsOnly'}
        if($savedPostInstallMode -ne $PostInstallMode){throw "Reinstallation refusee : le profil prepare est $savedPostInstallMode, mais le demarrage demande $PostInstallMode. Synchronise de nouveau BASTOS_RECOVERY."}
        if([string]$selectionState.CurrentWindowsDiskIdentity -ne $layout.WindowsDiskIdentity){throw 'Reinstallation refusee : l identite du disque Windows actuel a change depuis la synchronisation.'}
        if([string]$selectionState.WindowsTargetDiskIdentity -ne $layout.InstallDiskIdentity){throw 'Reinstallation refusee : l identite du disque choisi pour installer Windows a change.'}
        if([string]$selectionState.RecoveryDiskIdentity -ne $layout.TargetDiskIdentity){throw 'Reinstallation refusee : l identite du disque Recovery a change depuis la synchronisation.'}
        if([int]$selectionState.RecoveryPartitionNumber -ne [int]$partition.PartitionNumber){throw 'Reinstallation refusee : le numero de partition Recovery ne correspond plus a la selection validee.'}
        if([string]$selectionState.RecoveryPartitionGuid -ne ([string]$partition.Guid).Trim().ToUpperInvariant() -or
            [long]$selectionState.RecoveryPartitionOffset -ne [long]$partition.Offset -or
            [long]$selectionState.RecoveryPartitionSize -ne [long]$partition.Size -or
            [string]$selectionState.RecoveryPartitionGptType -ne ([string]$partition.GptType).Trim().ToUpperInvariant()){
            throw 'Reinstallation refusee : le GUID, l offset, la taille ou le type GPT de BASTOS_RECOVERY a change.'
        }
        if($RecoveryMode -eq 'Novice' -and (-not $layout.TargetIsWindowsDisk -or -not $layout.InstallIsCurrentWindowsDisk -or -not $layout.RecoveryIsInstallDisk)){
            throw 'Securite novice : Windows et BASTOS_RECOVERY doivent rester sur le disque contenant actuellement C:.'
        }

        $parts=@(Get-Partition -DiskNumber $layout.InstallDisk.Number)
        $currentEfi=@($layout.EfiPartitions)
        if($currentEfi.Count -ne 1){throw "Reinstallation refusee : exactement une partition EFI est requise sur le disque Windows actuel; trouve : $($currentEfi.Count)."}
        if($volume.Size -lt 35GB -or $volume.Size -gt 45GB){throw "Reinstallation refusee : la taille de BASTOS_RECOVERY doit etre comprise entre 35 et 45 Go; taille detectee : $([math]::Round($volume.Size/1GB,2)) Go."}
        foreach($required in @(
            'BASTOS-BOOT-ID.txt','BASTOS-ISO.sha256','BASTOS-MEDIA-STATE.json','BASTOS-RECOVERY-SELECTION.json',
            'autounattend.xml','sources\boot.wim','sources\install.wim',
            'Application\VERSION.txt','Application\BASTOS-Start.cmd','Application\Bastos.Recovery\BASTOS-Recovery-Probe.exe'
        )){if(-not(Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)){throw "Reinstallation refusee : fichier Recovery obligatoire absent : $required"}}

        # La version installee et verifiee est autoritaire au moment du clic.
        # Mettre a jour D:\Application puis le vrai payload $OEM$ copie par
        # Windows. Une divergence sur un worker critique interdit BootOnce.
        if($PostInstallMode -eq 'BastosAutonomous'){
            $recoveryApplicationRoot=Join-Path $root 'Application'
            Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
            & "$env:SystemRoot\System32\robocopy.exe" $PSScriptRoot $recoveryApplicationRoot /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /FFT /NP /NFL /NDL /XD Logs Backups '.codex-backup-*' /XF '*.ok'|Out-Null
            $applicationCopyExit=$LASTEXITCODE
            if($applicationCopyExit -ge 8){throw "Mise a jour de D:\Application echouee (Robocopy $applicationCopyExit)."}
            Sync-BastosAutonomousMediaPayload -ApplicationRoot $recoveryApplicationRoot -MediaRoot $root|Out-Null
        }else{
            Set-BastosRufusMediaProfile -ApplicationRoot $PSScriptRoot -MediaRoot $root
        }

        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        $null=New-BastosDriverBackup -Root $root -Selected:([bool]($script:RufusOptions -and $script:RufusOptions.PreserveDrivers)) -SetupPath (Join-Path $root 'setup.exe')
        # Le clic Reinstaller est auto-reparateur : si le lanceur persistant a
        # change depuis la derniere synchronisation, repatcher boot.wim avant
        # de programmer le redemarrage. Cela evite tout passage par une console
        # WinPE interactive avec un media ancien.
        $bootWimPath=Join-Path $root 'sources\boot.wim'
        $launcherPath=Join-Path $PSScriptRoot 'BASTOS-Start.cmd'
        $probePath=Join-Path $PSScriptRoot 'Bastos.Recovery\BASTOS-Recovery-Probe.exe'
        $mediaStatePath=Join-Path $root 'BASTOS-MEDIA-STATE.json'
        $mediaState=Get-Content -LiteralPath $mediaStatePath -Raw -Encoding UTF8|ConvertFrom-Json
        $wantedCleanup=if($script:RufusOptions -and $script:RufusOptions.UseCleanBastosInstallation){'minimal-2'}else{''}
        $savedCleanup=if($mediaState.PSObject.Properties['CleanupProfile']){[string]$mediaState.CleanupProfile}else{''}
        if($savedCleanup -ne $wantedCleanup){throw 'Le choix du profil propre a change. Preparez de nouveau Recovery avant de reinstaller.'}
        Assert-BastosWimSelection -Metadata (Get-BastosWimMetadata -ImagePath (Join-Path $root 'sources\install.wim')) -ImageIndex ([int]$mediaState.ProImageIndex) -EditionId ([string]$mediaState.WindowsEditionId)
        if([string]$mediaState.WindowsEditionId -notmatch '^[A-Za-z0-9]+$'){throw 'Identifiant edition Windows invalide.'}
        if((Get-FileHash -LiteralPath (Join-Path $root 'sources\install.wim') -Algorithm SHA256).Hash -ne [string]$mediaState.InstallWimSha256){throw 'Image Windows modifiee depuis sa preparation. Redemarrage refuse.'}
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-IMAGE-SELECTION.txt'),([string]$mediaState.ProImageIndex+'|'+[string]$mediaState.WindowsEditionId),[Text.Encoding]::ASCII)
        $signingChannel=if($mediaState.PSObject.Properties['SigningChannel']){[string]$mediaState.SigningChannel}else{Assert-BastosMicrosoftSetupSignature -Path(Join-Path $root 'setup.exe')}
        if($signingChannel -notin @('Retail','Insider')){throw "Canal de signature Recovery inconnu : $signingChannel"}
        $launcherHash=(Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash
        $probeHash=(Get-FileHash -LiteralPath $probePath -Algorithm SHA256).Hash
        $activeBootHash=(Get-FileHash -LiteralPath $bootWimPath -Algorithm SHA256).Hash
        $bootRefreshRequired=([string]$mediaState.RecoveryLauncherSha256 -ne $launcherHash) -or
            (-not $mediaState.PSObject.Properties['RecoveryProbeSha256']) -or ([string]$mediaState.RecoveryProbeSha256 -ne $probeHash) -or
            ([string]$mediaState.BootWimSha256 -ne $activeBootHash)
        if($bootRefreshRequired){
            $bootUpdate=Update-RecoveryBootImage -BootWimPath $bootWimPath -LauncherPath $launcherPath -ProbePath $probePath -AllowCompatibleLauncher
            $activeBootHash=(Get-FileHash -LiteralPath $bootWimPath -Algorithm SHA256).Hash
            $mediaState.RecoveryLauncherSha256=$launcherHash
            if($mediaState.PSObject.Properties['RecoveryProbeSha256']){$mediaState.RecoveryProbeSha256=$probeHash}else{$mediaState|Add-Member -NotePropertyName RecoveryProbeSha256 -NotePropertyValue $probeHash}
            $mediaState.BootWimSha256=$activeBootHash
            if($mediaState.PSObject.Properties['BootWimCompatibilityMode']){$mediaState.BootWimCompatibilityMode=[string]$bootUpdate.CompatibilityMode}else{$mediaState|Add-Member -NotePropertyName BootWimCompatibilityMode -NotePropertyValue ([string]$bootUpdate.CompatibilityMode)}
            if($mediaState.PSObject.Properties['EmbeddedRecoveryLauncherSha256']){$mediaState.EmbeddedRecoveryLauncherSha256=[string]$bootUpdate.EmbeddedLauncherSha256}else{$mediaState|Add-Member -NotePropertyName EmbeddedRecoveryLauncherSha256 -NotePropertyValue ([string]$bootUpdate.EmbeddedLauncherSha256)}
            $mediaState.VerifiedUtc=[DateTime]::UtcNow.ToString('o')
            [IO.File]::WriteAllText($mediaStatePath,($mediaState|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        }
        # Le montage et la sauvegarde du WIM peuvent réénumérer le stockage.
        # Refaire toute la sélection juste avant de figer le plan destructif.
        $layout=Assert-RecoveryStorageCheckpoint
        $recovery=@($layout.RecoveryPartitions)
        if($recovery.Count -ne 1){throw 'Reinstallation refusee : BASTOS_RECOVERY a disparu pendant la validation.'}
        $partition=$recovery[0]
        $volume=$partition|Get-Volume -ErrorAction Stop
        if([string]$selectionState.WindowsTargetDiskIdentity -ne $layout.InstallDiskIdentity -or
            [string]$selectionState.RecoveryDiskIdentity -ne $layout.TargetDiskIdentity -or
            [string]$selectionState.RecoveryPartitionGuid -ne ([string]$partition.Guid).Trim().ToUpperInvariant() -or
            [long]$selectionState.RecoveryPartitionOffset -ne [long]$partition.Offset -or
            [long]$selectionState.RecoveryPartitionSize -ne [long]$partition.Size){
            throw 'Reinstallation refusee : la disposition des disques a change pendant la validation finale.'
        }
        $parts=@(Get-Partition -DiskNumber $layout.InstallDisk.Number)
        $nativeParts=@(Resolve-BastosNativePartitionNumbers -ProbePath $probePath -DiskNumber $layout.InstallDisk.Number -Partitions $parts)
        $nativeRecoveryParts=if($layout.TargetDisk.Number -eq $layout.InstallDisk.Number){$nativeParts}else{
            @(Resolve-BastosNativePartitionNumbers -ProbePath $probePath -DiskNumber $layout.TargetDisk.Number -Partitions @(Get-Partition -DiskNumber $layout.TargetDisk.Number))
        }
        $nativeRecovery=@($nativeRecoveryParts|Where-Object{[guid]$_.Guid -eq [guid]$partition.Guid -and [long]$_.Offset -eq [long]$partition.Offset})
        if($nativeRecovery.Count -ne 1){throw 'Identite WinPE de BASTOS_RECOVERY introuvable ou ambigue.'}
        $nativeOs=@($nativeParts|Where-Object{[guid]$_.Guid -eq [guid]$layout.OsPartition.Guid -and [long]$_.Offset -eq [long]$layout.OsPartition.Offset})
        if($layout.InstallIsCurrentWindowsDisk -and $nativeOs.Count -ne 1){throw 'Identite WinPE de Windows introuvable ou ambigue.'}
        $currentEfi=@($layout.EfiPartitions)
        $createEfi=(-not $layout.InstallIsCurrentWindowsDisk) -or ($script:RufusOptions -and $script:RufusOptions.KeepOnlyRecoveryPartition)
        $preservedNumbers=@()
        if(-not $createEfi){
            $nativeEfi=@($nativeParts|Where-Object{[guid]$_.Guid -eq [guid]$currentEfi[0].Guid -and [long]$_.Offset -eq [long]$currentEfi[0].Offset})
            if($nativeEfi.Count -ne 1){throw 'Identite WinPE de la partition EFI introuvable ou ambigue.'}
            $preservedNumbers+=@([int]$nativeEfi[0].PartitionNumber)
        }
        if($layout.RecoveryIsInstallDisk){$preservedNumbers+=@([int]$nativeRecovery[0].PartitionNumber)}
        $preservedNumbers=@($preservedNumbers|Sort-Object -Unique)
        $nativeOsNumber=if($nativeOs.Count -eq 1){[int]$nativeOs[0].PartitionNumber}else{-1}
        $deploymentPlan=New-BastosDeploymentPlan -InstallDiskNumber $layout.InstallDisk.Number -Partitions $nativeParts -PreservedPartitionNumbers $preservedNumbers -CreateEfi $createEfi -OsPartitionNumber $nativeOsNumber
        $deleteParts=@($deploymentPlan.DeletePartitions)
        if($layout.InstallIsCurrentWindowsDisk -and ($deleteParts.Count -lt 1 -or $nativeOsNumber -notin @($deleteParts.PartitionNumber))){throw 'Reinstallation refusee : la partition Windows active ne figure pas dans le plan de remplacement.'}
        $newEfiNumber=$deploymentPlan.NewEfiPartitionNumber
        $newMsrNumber=[int]$deploymentPlan.NewMsrPartitionNumber
        $newWindowsNumber=[int]$deploymentPlan.NewWindowsPartitionNumber
        $diskpartLines=@($deploymentPlan.Lines)
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-DEPLOY-DISKPART.txt'),$diskpartLines,[Text.Encoding]::ASCII)
        $deleteLines=@($deploymentPlan.DeleteEntries|ForEach-Object{
            '{0}|{1}|{2}|{3}' -f $_.PartitionNumber,$_.Offset,$_.GptType,$_.Guid
        })
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-DELETE-PARTITIONS.txt'),$deleteLines,[Text.Encoding]::ASCII)
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-CREATE-PARTITIONS.txt'),@($deploymentPlan.CreateLines),[Text.Encoding]::ASCII)
        $recoveryRecord='{0}|{1}|{2}|{3}' -f $nativeRecovery[0].PartitionNumber,$partition.Offset,([string]$partition.GptType).Trim('{}').ToLowerInvariant(),([string]$partition.Guid).Trim('{}').ToLowerInvariant()
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-RECOVERY-PARTITION.txt'),$recoveryRecord,[Text.Encoding]::ASCII)
        $windowsRecord='{0}|{1}|{2}|{3}' -f $nativeOsNumber,$layout.OsPartition.Offset,([string]$layout.OsPartition.GptType).Trim('{}').ToLowerInvariant(),([string]$layout.OsPartition.Guid).Trim('{}').ToLowerInvariant()
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-WINDOWS-PARTITION.txt'),$windowsRecord,[Text.Encoding]::ASCII)
        $efiMarkerPath=Join-Path $root 'BASTOS-EFI-PARTITION.txt'
        if(-not $createEfi){
            $efiPartition=$currentEfi[0]
            $efiRecord='{0}|{1}|{2}|{3}' -f $nativeEfi[0].PartitionNumber,$efiPartition.Offset,([string]$efiPartition.GptType).Trim('{}').ToLowerInvariant(),([string]$efiPartition.Guid).Trim('{}').ToLowerInvariant()
            [IO.File]::WriteAllText($efiMarkerPath,$efiRecord,[Text.Encoding]::ASCII)
        }else{
            Remove-Item -LiteralPath $efiMarkerPath -Force -ErrorAction SilentlyContinue
        }
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-WINDOWS-DISK-ID.txt'),$layout.InstallDiskIdentity,[Text.Encoding]::ASCII)
        [IO.File]::WriteAllLines((Join-Path $root 'BASTOS-WINDOWS-DISK-CHECK.txt'),@('rem Le numero est resolu dans WinPE par GUID GPT.','uniqueid disk','detail disk'),[Text.Encoding]::ASCII)
        $answerPath=Join-Path $root 'BASTOS-Recovery-Unattend.xml'
        if(-not $mediaState.PSObject.Properties['ProImageIndex'] -or [int]$mediaState.ProImageIndex -lt 1){throw 'Index Windows absent : synchronise de nouveau BASTOS_RECOVERY.'}
        $selectedEdition=if($mediaState.PSObject.Properties['WindowsEditionId']){[string]$mediaState.WindowsEditionId}else{'Professional'}
        # Provision a deja genere BASTOS-Recovery-Unattend.xml avec les choix
        # de langue, de compte et de profil resolus. Le autounattend.xml a la
        # racine peut rester le modele ISO et contenir __BASTOS_*__ ; le relire
        # ici faisait echouer BootOnce avant meme l armement du redemarrage.
        if(-not (Test-Path -LiteralPath $answerPath -PathType Leaf)){throw 'Le fichier de reponses Recovery resolu est absent : recree BASTOS_RECOVERY.'}
        $answerSourceText=Get-Content -LiteralPath $answerPath -Raw -Encoding UTF8
        if($answerSourceText -match '__BASTOS_[A-Z_]+__'){throw 'Le fichier de reponses Recovery resolu contient encore un choix BASTOS : recree BASTOS_RECOVERY.'}
        [xml]$sourceAnswer=$answerSourceText
        $preferredUILanguage=if($script:RufusOptions){[string]$script:RufusOptions.WindowsUILanguage}else{$sourceAnswer.SelectSingleNode("//*[local-name()='UILanguage']").InnerText}
        if($script:RufusOptions -and $preferredUILanguage -notin @((Get-BastosWimMetadata -ImagePath (Join-Path $root 'sources\install.wim')).SelectNodes("/WIM/IMAGE[@INDEX='$($mediaState.ProImageIndex)']/WINDOWS/LANGUAGES/LANGUAGE")|ForEach-Object{$_.InnerText})){throw 'La langue choisie ne figure plus dans le media prepare. Reouvre les options.'}
        $imageUILanguage=Get-BastosImageUILanguage -Metadata (Get-BastosWimMetadata -ImagePath (Join-Path $root 'sources\install.wim')) -ImageIndex ([int]$mediaState.ProImageIndex) -PreferredLanguage $preferredUILanguage
        New-RecoveryAnswerFile -SourcePath $answerPath -DestinationPath $answerPath -ProImageIndex ([int]$mediaState.ProImageIndex) -EditionId $selectedEdition -ImageUILanguage $imageUILanguage -PostInstallMode $PostInstallMode
        [xml]$answer=Get-Content -LiteralPath $answerPath -Raw -Encoding UTF8
        $ns=[Xml.XmlNamespaceManager]::new($answer.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
        $selectedLocalAccountValue=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccounts/u:LocalAccount/u:Password/u:Value',$ns)
        $selectedLocalAccountName=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccounts/u:LocalAccount/u:Name',$ns)
        $selectedLocalDisplayName=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:LocalAccounts/u:LocalAccount/u:DisplayName',$ns)
        $selectedAutoLogon=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon',$ns)
        $selectedAutoLogonValue=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Password/u:Value',$ns)
        $selectedAutoLogonDomain=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Domain',$ns)
        $selectedAutoLogonUsername=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Username',$ns)
        $selectedAutoLogonEnabled=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:Enabled',$ns)
        $selectedAutoLogonCount=$answer.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:AutoLogon/u:LogonCount',$ns)
        $selectedComputerName=$answer.SelectSingleNode('//u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:ComputerName',$ns)
        if($PostInstallMode -eq 'WindowsOnly'){
            $accountPayload=Join-Path $root 'sources\$OEM$\$1\ProgramData\BASTOS-ISO'
            $accountProfile=Get-Content -LiteralPath (Join-Path $accountPayload 'Installation-Expected.json') -Raw -Encoding UTF8|ConvertFrom-Json
            $expectedUser=if($script:RufusOptions){[string]$script:RufusOptions.UserName}else{'BastOS'}
            if($accountProfile.UserName -cne $expectedUser){throw 'Le compte du profil ne correspond pas au choix utilisateur.'}
            [void](Test-BastosRufusAccountFlow -Document $answer -Profile $accountProfile)
            $accountWorker=Join-Path $accountPayload 'Initialize-BASTOS-LocalAccount.ps1'
            if((Get-FileHash -LiteralPath $accountWorker -Algorithm SHA256).Hash -ne $accountProfile.AccountWorkerSha256){throw 'Worker compte local absent ou divergent.'}
        }else{
        if(-not $selectedLocalAccountValue -or $selectedLocalAccountValue.InnerText -ne '' -or -not $selectedLocalAccountName -or $selectedLocalAccountName.InnerText -cne 'BastOS' -or -not $selectedLocalDisplayName -or $selectedLocalDisplayName.InnerText -cne 'BastOS'){throw 'Le compte local BastOS Recovery n est pas strictement sans mot de passe.'}
        if(-not $selectedAutoLogon -or -not $selectedAutoLogonValue -or $selectedAutoLogonValue.InnerText -ne '' -or
           -not $selectedAutoLogonUsername -or $selectedAutoLogonUsername.InnerText -cne 'BastOS' -or
           -not $selectedAutoLogonEnabled -or $selectedAutoLogonEnabled.InnerText -ne 'true' -or
           -not $selectedAutoLogonCount -or $selectedAutoLogonCount.InnerText -ne '1' -or
           -not $selectedComputerName -or -not $selectedAutoLogonDomain -or $selectedAutoLogonDomain.InnerText -eq '.' -or
           $selectedAutoLogonDomain.InnerText -cne $selectedComputerName.InnerText){
            throw 'La connexion automatique locale Bastos Recovery est absente ou incoherente.'
        }
        }
        $accountMarkerPath=Join-Path $root 'sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt'
        # Les fichiers provenant d'une ISO peuvent conserver l'attribut lecture seule.
        # Le marqueur est actualise a chaque armement BootOnce : retirer uniquement
        # cet attribut sur le fichier cible avant WriteAllText.
        if(Test-Path -LiteralPath $accountMarkerPath -PathType Leaf){
            $accountMarkerItem=Get-Item -LiteralPath $accountMarkerPath -Force
            if($accountMarkerItem.IsReadOnly){$accountMarkerItem.IsReadOnly=$false}
        }
        [IO.File]::WriteAllText($accountMarkerPath,$(if($script:RufusOptions){$script:RufusOptions.UserName}else{'BastOS'}),[Text.UTF8Encoding]::new($false))
        $diskNodes=@($answer.SelectNodes('//u:DiskConfiguration/u:Disk/u:DiskID | //u:InstallTo/u:DiskID',$ns))
        $partitionNodes=@($answer.SelectNodes('//u:InstallTo/u:PartitionID | //u:ModifyPartition/u:PartitionID',$ns))
        if($diskNodes.Count -lt 2){throw 'Le fichier de reponses Recovery ne contient pas les cibles de disque attendues.'}
        if($partitionNodes.Count -lt 2){throw 'Le fichier de reponses Recovery ne contient pas les cibles de partition attendues.'}
        foreach($node in $partitionNodes){$node.InnerText=[string]$newWindowsNumber}
        foreach($node in $diskNodes){$node.InnerText=[string]$layout.InstallDisk.Number}
        $answer.Save($answerPath)
        # Le numéro du même disque physique peut changer dans WinPE si une clé
        # USB est branchée. Préparer une réponse sûre pour chaque numéro possible;
        # le lanceur choisira uniquement celle correspondant au GUID GPT trouvé.
        Get-ChildItem -LiteralPath $root -Filter 'BASTOS-Recovery-Unattend-Disk*.xml' -File -ErrorAction SilentlyContinue|Remove-Item -Force
        foreach($winPeDiskNumber in 0..31){
            [xml]$variant=Get-Content -LiteralPath $answerPath -Raw -Encoding UTF8
            $variantNs=[Xml.XmlNamespaceManager]::new($variant.NameTable);$variantNs.AddNamespace('u','urn:schemas-microsoft-com:unattend')
            foreach($node in @($variant.SelectNodes('//u:DiskConfiguration/u:Disk/u:DiskID | //u:InstallTo/u:DiskID',$variantNs))){$node.InnerText=[string]$winPeDiskNumber}
            $variant.Save((Join-Path $root ("BASTOS-Recovery-Unattend-Disk$winPeDiskNumber.xml")))
        }
        # D:\Application (ou toute autre lettre attribuee au volume Recovery)
        # reste la source autoritaire. Le redemarrage ne doit jamais la remplacer
        # silencieusement par le cache C:. La mise a jour D <- C est reservee a
        # l action explicite de creation/synchronisation de BASTOS_RECOVERY.
        $recoveryApplicationRoot=Join-Path $root 'Application'
        foreach($requiredSourceFile in @('VERSION.txt','BASTOS-Start.cmd','Bastos.Recovery\BASTOS-Recovery-Probe.exe')){
            if(-not(Test-Path -LiteralPath (Join-Path $recoveryApplicationRoot $requiredSourceFile) -PathType Leaf)){
                throw "Source BASTOS_RECOVERY incomplete ($requiredSourceFile). Synchronise BASTOS_RECOVERY avant de reinstaller."
            }
        }
        if($PostInstallMode -eq 'BastosAutonomous'){
            foreach($requiredAutonomousFile in @(
                'BASTOS-SetupDiagnostics.psm1','Invoke-BASTOS-Specialize.ps1','Start-BASTOS-Autonomous-FirstLogon.ps1','Initialize-BASTOS-Autonomous-FirstLogon.ps1','Initialize-BASTOS-PreLogon.ps1','BASTOS-SetupComplete.cmd','BASTOS-LocalOnly-OOBE.cmd','Remove-BASTOS-LegacyKernelComponents.ps1','Invoke-BASTOS-FirstDesktopEssentials.ps1','Install-BASTOS-SoftwareSelection.ps1','BASTOS-Specialize-WU-Off.ps1','Apply-Machine.ps1','Apply-User.ps1',
                'Complete-BASTOS-UserSetup.ps1','Invoke-BASTOS-PostInstall.ps1','Bastos-Uninstall.exe','Remove-BASTOS-OneDrive.ps1',
                'Remove-BASTOS-Edge.ps1',
                'Bastos.Native\BASTOS-Native.exe','Bastos.Game\BASTOS-Game.exe','Assets\Bastos-Game-Tray.ico'
            )){
                if(-not(Test-Path -LiteralPath (Join-Path $recoveryApplicationRoot $requiredAutonomousFile) -PathType Leaf)){
                    throw "Source autonome BASTOS incomplete ($requiredAutonomousFile). Synchronise de nouveau BASTOS_RECOVERY."
                }
            }
        }
        $savedVersion=(Get-Content -LiteralPath (Join-Path $recoveryApplicationRoot 'VERSION.txt') -Raw).Trim()
        $runtimeVersion=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION.txt') -Raw).Trim()
        if($savedVersion -ne $runtimeVersion){throw "BASTOS_RECOVERY contient la version $savedVersion, mais le cache courant utilise $runtimeVersion. Synchronise BASTOS_RECOVERY avant de reinstaller."}
        if($script:RufusOptions){[IO.File]::WriteAllText((Join-Path $root 'BASTOS-Rufus-Options.json'),($script:RufusOptions|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
        $layoutMarker=[ordered]@{
            Schema=5;RecoveryMode=$RecoveryMode;SelectionSource=$layout.SelectionSource
            CurrentWindowsDiskNumber=[int]$layout.WindowsDisk.Number;CurrentWindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsTargetDiskNumber=[int]$layout.InstallDisk.Number;WindowsTargetDiskIdentity=$layout.InstallDiskIdentity
            RecoveryDiskNumber=[int]$layout.TargetDisk.Number;RecoveryDiskIdentity=$layout.TargetDiskIdentity
            RecoveryIsInstallDisk=[bool]$layout.RecoveryIsInstallDisk;EfiPartitionNumber=if($createEfi){$newEfiNumber}else{[int]$nativeEfi[0].PartitionNumber}
            BastosPartitionNumber=[int]$nativeRecovery[0].PartitionNumber;BastosPartitionGuid=([string]$partition.Guid).Trim().ToUpperInvariant()
            BastosPartitionOffset=[long]$partition.Offset;BastosPartitionSize=[long]$partition.Size
            DeletedPartitions=@($deploymentPlan.DeleteEntries)
            NewMsrPartitionNumber=$newMsrNumber;NewWindowsPartitionNumber=$newWindowsNumber;PreparedUtc=[DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-LAYOUT-DISK0.ok'),($layoutMarker|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        $answerVariants=@(Get-ChildItem -LiteralPath $root -Filter 'BASTOS-Recovery-Unattend-Disk*.xml' -File -ErrorAction SilentlyContinue)
        if($answerVariants.Count -ne 32){throw "Plan WinPE incomplet : $($answerVariants.Count) fichiers de reponses sur 32."}
        foreach($preparedFile in @(
            'BASTOS-DELETE-PARTITIONS.txt','BASTOS-CREATE-PARTITIONS.txt','BASTOS-RECOVERY-PARTITION.txt',
            'BASTOS-WINDOWS-PARTITION.txt',("BASTOS-Recovery-Unattend-Disk$($layout.InstallDisk.Number).xml")
        )){
            if(-not(Test-Path -LiteralPath (Join-Path $root $preparedFile) -PathType Leaf)){throw "Plan WinPE incomplet : $preparedFile"}
        }
        $verifiedBootEntry=@(Invoke-BcdEdit /enum $bootId /v) -join "`r`n"
        foreach($requiredBootValue in @($bootId,'sources\boot.wim','windows\system32\boot\winload.efi')){
            if($verifiedBootEntry -notmatch [regex]::Escape($requiredBootValue)){throw "Entree BCD invalide avant BootOnce : $requiredBootValue"}
        }
        $attemptId='Attempt-'+[guid]::NewGuid().ToString('N')
        $attemptRoot=Join-Path (Join-Path (Join-Path $root 'BASTOS-Diagnostics') 'Attempts') $attemptId
        New-Item -ItemType Directory -Path $attemptRoot -Force|Out-Null
        $attemptState=[ordered]@{
            Schema=1;OperationId=$OperationId;AttemptId=$attemptId;Stage='BootScheduled';Success=$null
            BastosVersion=$runtimeVersion;PostInstallMode=$PostInstallMode
            WindowsDiskIdentity=$layout.InstallDiskIdentity;RecoveryDiskIdentity=$layout.TargetDiskIdentity
            RecoveryPartitionGuid=([string]$partition.Guid).Trim().ToUpperInvariant()
            CreatedUtc=[DateTime]::UtcNow.ToString('o');UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText((Join-Path $attemptRoot 'State.json'),($attemptState|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        # BootOnce et DiagnosticBoot sont deux autorisations exclusives. Un
        # ancien jeton de test ne doit jamais convertir une vraie tentative en
        # diagnostic non destructif dans WinPE.
        $diagnosticStatePaths=@(
            (Join-Path $root 'BASTOS-DIAGNOSTIC-ONLY.token'),
            (Join-Path $root 'BASTOS-Diagnostic-Result.log'),
            (Join-Path $root 'BASTOS-BOOT-MODE.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-WINDOWS-PARTITION.txt'),
            (Join-Path $root 'BASTOS-DIAGNOSTIC-EFI-PARTITION.txt')
        )
        Remove-Item -LiteralPath $diagnosticStatePaths -Force -ErrorAction SilentlyContinue
        if(@($diagnosticStatePaths|Where-Object{Test-Path -LiteralPath $_}).Count -ne 0){throw 'Armement refuse : un ancien etat diagnostic n a pas pu etre supprime.'}
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        $script:ArmingRoot=$root
        $script:ArmingAttemptRoot=$attemptRoot
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-ACTIVE-ATTEMPT.txt'),$attemptId,[Text.Encoding]::ASCII)
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-AUTO-REINSTALL.token'),([DateTime]::UtcNow.ToString('o')),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $root 'BASTOS-BOOT-MODE.txt'),('BOOTONCE|'+$attemptId),[Text.Encoding]::ASCII)
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        Assert-BastosBootAuthorization -Root $root -AttemptId $attemptId
        # Persist a snapshot independently of tokens consumed in WinPE.
        foreach($name in @('BASTOS-ACTIVE-ATTEMPT.txt','BASTOS-AUTO-REINSTALL.token','BASTOS-BOOT-MODE.txt')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $attemptRoot $name) -Force}
        [IO.File]::WriteAllText((Join-Path $attemptRoot 'AuthorizationVerified.txt'),[DateTime]::UtcNow.ToString('o'),[Text.Encoding]::ASCII)
        # Le bootsequence selectionne Recovery une seule fois. Le menu reste
        # masque : aucun choix n est demande entre le clic BASTOS et le Bureau.
        if($signingChannel -eq 'Insider'){
            # Microsoft exige ces deux options pour approuver les binaires de
            # demarrage signes pour Windows Insider Preview.
            Invoke-BcdEdit /set '{bootmgr}' flightsigning yes|Out-Null
            Invoke-BcdEdit /set $bootId flightsigning yes|Out-Null
        }else{
            Invoke-BcdEdit /set '{bootmgr}' flightsigning no|Out-Null
            & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue $bootId flightsigning 2>&1|Out-Null
        }
        & "$env:SystemRoot\System32\bcdedit.exe" /displayorder $bootId /remove 2>&1|Out-Null
        Invoke-BcdEdit /set '{bootmgr}' displaybootmenu no|Out-Null
        Invoke-BcdEdit /timeout 0|Out-Null
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        Invoke-BcdEdit /bootsequence $bootId|Out-Null
        $script:BootSequenceArmed=$true
        $armedBootManager=@(Invoke-BcdEdit /enum '{bootmgr}' /v) -join "`r`n"
        if($armedBootManager -notmatch [regex]::Escape($bootId)){
            throw "Le demarrage unique BASTOS n est pas present dans le gestionnaire de demarrage apres programmation."
        }
        Assert-RecoveryWriteTarget -Partition $partition -Letter $letter
        Assert-BastosBootAuthorization -Root $root -AttemptId $attemptId
        if($temporary){Remove-PartitionAccessPath -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath "${letter}:\"}
        Save-Result -Success $true -Message 'La source BASTOS_RECOVERY a ete verifiee; le prochain demarrage ouvrira la reinstallation.' -Extra @{
            RecoveryMode=$RecoveryMode;SafetyValidated=$true;CurrentWindowsDiskNumber=$layout.WindowsDisk.Number;CurrentWindowsDiskIdentity=$layout.WindowsDiskIdentity
            WindowsTargetDiskNumber=$layout.InstallDisk.Number;WindowsTargetDiskIdentity=$layout.InstallDiskIdentity
            TargetDiskNumber=$layout.TargetDisk.Number;TargetDiskIdentity=$layout.TargetDiskIdentity;TargetIsWindowsDisk=$layout.TargetIsWindowsDisk
            RecoveryIsInstallDisk=$layout.RecoveryIsInstallDisk
            RecoveryPartitionNumber=$partition.PartitionNumber;RecoveryPartitionGuid=([string]$partition.Guid).Trim().ToUpperInvariant()
            RecoveryPartitionOffset=[long]$partition.Offset;BootId=$bootId;SavedVersion=$savedVersion;AttemptId=$attemptId
        }|Out-Null
        exit 0
    }
}catch{
    $failureRecord=$_
    if($_.Exception -is [OperationCanceledException] -and $Action -eq 'Provision' -and -not $script:RecoveryWritesStarted){
        $cleanupVerified=$true
        try{if($IsoPath -and (Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop).Attached){$cleanupVerified=$false}}catch{$cleanupVerified=$false}
        Save-Result -Success $false -Message 'Preparation annulee avant les ecritures Recovery. Des fichiers de profil temporaires peuvent subsister.' -Extra @{
            Cancelled=$cleanupVerified;CancellationScope='RecoveryBeforeWrites';CancellationCleanupVerified=$cleanupVerified;ErrorCode=$(if($cleanupVerified){'RECOVERY_CANCELLED'}else{'CANCELLATION_CLEANUP_UNCONFIRMED'})
        }|Out-Null
        if($cleanupVerified){exit 2}else{exit 1}
    }
    $armingFailure=$_.Exception.Message
    if($script:ArmingRoot){
        foreach($name in @('BASTOS-ACTIVE-ATTEMPT.txt','BASTOS-AUTO-REINSTALL.token','BASTOS-BOOT-MODE.txt')){
            Remove-Item -LiteralPath (Join-Path $script:ArmingRoot $name) -Force -ErrorAction SilentlyContinue
        }
        if($script:BootSequenceArmed){& "$env:SystemRoot\System32\bcdedit.exe" /deletevalue '{bootmgr}' bootsequence 2>&1|Out-Null}
        if($script:ArmingAttemptRoot){try{[IO.File]::WriteAllText((Join-Path $script:ArmingAttemptRoot 'Arming-Failure.txt'),$armingFailure,[Text.UTF8Encoding]::new($false))}catch{}}
    }
    $failurePercent=[Math]::Min(99,[Math]::Max(0,[int]$script:ProgressPercent))
    Write-RecoveryProgress -Percent $failurePercent -Phase 'Échec' -Message $armingFailure -Step $script:ProgressStep -TotalSteps $script:ProgressTotalSteps
    $code=[regex]::Match($armingFailure,'^(DISK_[A-Z_]+|RECOVERY_[A-Z_]+)').Value
    if(-not $code){$code=if($Action -eq 'BootOnce'){'RECOVERY_BOOT_FAILED'}else{'RECOVERY_PREPARATION_FAILED'}}
    Save-Result -Success $false -Message $armingFailure -Extra @{ErrorCode=$code}|Out-Null
    Write-Error $failureRecord
    exit 1
}
