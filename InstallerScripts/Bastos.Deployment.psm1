Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -ErrorAction Stop
function Get-BastosAdkVersion {
    $versions=@()
    foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach($entry in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            if($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -eq 'Windows Deployment Tools' -and $entry.PSObject.Properties['DisplayVersion']) {
                $version=$null
                if([version]::TryParse([string]$entry.DisplayVersion,[ref]$version)){$versions += $version}
            }
        }
    }
    return $versions | Sort-Object -Descending | Select-Object -First 1
}
function Get-BastosOscdimgPath {
    foreach($root in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
        if(-not $root){continue}
        foreach($arch in @('amd64','x86')) {
            $path=Join-Path $root "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
            if(Test-Path -LiteralPath $path -PathType Leaf){return $path}
        }
    }
    return $null
}
function Assert-BastosDeploymentSignature {
    param([string]$Path)
    $sig=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {throw "Signature Microsoft invalide : $Path"}
    return $sig
}
function Initialize-BastosMsiReader {
    if('BastosMsiReadOnly' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BastosMsiReadOnly {
 [DllImport("msi.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] public static extern int MsiQueryProductStateW(string product);
 [DllImport("msi.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] public static extern uint MsiGetPatchInfoExW(string patch,string product,string sid,uint context,string property,StringBuilder value,ref uint size);
}
'@
}
function Get-BastosMsiPatchState {
    param([string]$PatchCode,[string]$ProductCode)
    Initialize-BastosMsiReader
    $buffer=[Text.StringBuilder]::new(32);$size=[uint32]32
    $code=[BastosMsiReadOnly]::MsiGetPatchInfoExW($PatchCode,$ProductCode,$null,4,'State',$buffer,[ref]$size)
    if($code -ne 0){return 0}
    return [int]$buffer.ToString()
}
function Get-BastosPatchTargets {
    param([string]$Path)
    $installer=$null;$summary=$null
    try {
        $installer=New-Object -ComObject WindowsInstaller.Installer
        $summary=$installer.GetType().InvokeMember('SummaryInformation','GetProperty',$null,$installer,@($Path,0))
        $revision=[string]$summary.GetType().InvokeMember('Property','GetProperty',$null,$summary,@(9))
        $template=[string]$summary.GetType().InvokeMember('Property','GetProperty',$null,$summary,@(7))
        $guidPattern='\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}'
        $patchCode=[regex]::Match($revision,'^'+$guidPattern).Value
        $targets=@($template -split ';' | Where-Object {$_ -match ('^'+$guidPattern+'$')})
        if(-not $patchCode -or $targets.Count -eq 0){throw "Metadonnees MSP invalides : $Path"}
        Initialize-BastosMsiReader
        $installed=@($targets | Where-Object {[BastosMsiReadOnly]::MsiQueryProductStateW($_) -eq 5})
        return [pscustomobject]@{PatchCode=$patchCode;Products=$installed}
    } finally {
        if($summary){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary)}
        if($installer){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)}
    }
}
function Get-BastosAdkEvidence {
    param([object[]]$RequiredPatches=@(),[string]$ArchiveHash='')
    $version=Get-BastosAdkVersion;$path=Get-BastosOscdimgPath
    if(-not $version -or -not $path){throw 'ADK_NOT_READY : version des Outils de deploiement ou Oscdimg absent.'}
    $profile=if($version -eq [version]'10.1.26100.9457'){'CurrentRelease'}elseif($version -eq [version]'10.1.26100.2454'){'PatchedBase'}else{throw "ADK_VERSION_UNSUPPORTED : version $version non validee. Utilise ADK 10.1.26100.9457 ou la base 10.1.26100.2454 corrigee."}
    $sig=Assert-BastosDeploymentSignature -Path $path
    if($profile -eq 'PatchedBase') {
        if($ArchiveHash -ne 'DC19725A2FB0CCE44C32AC14059A85A25257B9534BA21C93B479F4F09FB5AF38'){throw 'ADK_PATCH_UNCONFIRMED : archive KB5101684 non identifiee par son empreinte de reference.'}
        if($RequiredPatches.Count -eq 0){throw 'ADK_PATCH_UNCONFIRMED : aucun composant applicable du correctif KB5101684 atteste.'}
        foreach($patch in $RequiredPatches) {
            if((Get-BastosMsiPatchState -PatchCode $patch.PatchCode -ProductCode $patch.ProductCode) -notin @(1,2)) {
                throw "ADK_PATCH_UNCONFIRMED : Windows Installer ne confirme pas le correctif $($patch.PatchCode) pour $($patch.ProductCode)."
            }
        }
    }
    return @{
        InstalledVersion=$version.ToString(); Oscdimg=$path; OscdimgLength=[long](Get-Item -LiteralPath $path).Length
        OscdimgSha256=(Get-BastosFileSha256 -Path $path); SignatureStatus=[string]$sig.Status; SignerSubject=$sig.SignerCertificate.Subject
        ReadinessProfile=$profile; PatchId=if($profile -eq 'PatchedBase'){'KB5101684'}else{''}; RequiredPatches=@($RequiredPatches)
        PatchStatus=if($profile -eq 'PatchedBase'){'WindowsInstallerVerified'}else{'DifferentRelease'}
        PatchArchiveSha256=$ArchiveHash
    }
}
function Get-BastosBootStamp {
    Import-Module (Join-Path $PSHOME 'Modules\CimCmdlets\CimCmdlets.psd1') -ErrorAction Stop
    $system=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if(-not $system.LastBootUpTime){throw 'Impossible de verifier le dernier demarrage Windows.'}
    return $system.LastBootUpTime.ToUniversalTime().Ticks.ToString()
}
function Save-BastosAdkRestart {
    param([string]$Path)
    $value=@{BootStamp=(Get-BastosBootStamp);RequestedUtc=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($Path,($value|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
function Assert-BastosAdkRestartComplete {
    param([string]$Path)
    if(-not $Path -or -not (Test-Path -LiteralPath $Path)){return}
    try {
        $receipt=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not $receipt.BootStamp -or [string]$receipt.BootStamp -eq (Get-BastosBootStamp)){throw 'ADK_RESTART_REQUIRED : redemarre Windows avant de continuer.'}
    } catch {throw "ADK_RESTART_REQUIRED : redemarrage non confirme. $($_.Exception.Message)"}
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}
function Assert-BastosAdkEvidence {
    param([string]$EvidencePath)
    $required=@();$previous=$null
    if($EvidencePath) {
        $previous=Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if(-not $previous.Success -or $previous.SchemaVersion -ne 1){throw 'Rapport ADK absent, incomplet ou en echec.'}
        if($previous.PSObject.Properties['RestartReceiptPath']){Assert-BastosAdkRestartComplete -Path $previous.RestartReceiptPath}
        $required=@($previous.RequiredPatches)
    }
    $archiveHash=if($previous){[string]$previous.PatchArchiveSha256}else{''}
    $actual=Get-BastosAdkEvidence -RequiredPatches $required -ArchiveHash $archiveHash
    if($previous -and ($previous.OscdimgSha256 -ne $actual.OscdimgSha256 -or $previous.InstalledVersion -ne $actual.InstalledVersion -or
        -not [string]::Equals([IO.Path]::GetFullPath($previous.Oscdimg),[IO.Path]::GetFullPath($actual.Oscdimg),[StringComparison]::OrdinalIgnoreCase))) {throw 'Les outils ADK ont change depuis leur verification.'}
    return $actual
}
Export-ModuleMember -Function Get-BastosAdkVersion,Get-BastosOscdimgPath,Assert-BastosDeploymentSignature,Get-BastosMsiPatchState,Get-BastosPatchTargets,Get-BastosAdkEvidence,Assert-BastosAdkEvidence,Get-BastosBootStamp,Save-BastosAdkRestart,Assert-BastosAdkRestartComplete
