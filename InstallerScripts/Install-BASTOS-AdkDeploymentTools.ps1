[CmdletBinding()]
param([string]$InstallerPath,[string]$PatchPath,[string]$DownloadDirectory,[string]$ProgressPath,[string]$ResultPath,[string]$StatePath,[string]$OperationId='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Bastos.Deployment.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$ProgressPreference='SilentlyContinue'
$officialUri='https://go.microsoft.com/fwlink/?linkid=2289980'
$officialPatchUri='https://aka.ms/Windows_ADK_10.1.26100.2454_Update_KB5101684.zip'
$patchId='KB5101684'
$installerExitCode=0;$rebootRequired=$false;$process=$null
$receiptPath=$null
$evidence=@{}
function Write-BastosAdkProgress {
    param([int]$Percent,[string]$Phase,[string]$Message)
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent $Percent -Phase $Phase -Message $Message
}
function Save-AdkResult([bool]$Success,[string]$Message) {
    $evidence.InstallerExitCode=$installerExitCode;$evidence.RestartRequired=$rebootRequired
    $evidence.RestartReceiptPath=$receiptPath
    Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $Success -Message $Message -Data $evidence
}
function Receive-BastosOfficialFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Phase,
        [int]$StartPercent,
        [int]$EndPercent
    )
    $temporary="$Destination.download"
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $request=[Net.HttpWebRequest]::Create($Uri)
    $request.AllowAutoRedirect=$true; $request.Timeout=120000; $request.ReadWriteTimeout=120000
    $request.UserAgent='BASTOS/7.77 Windows-ADK-Prerequisite'
    $response=$request.GetResponse()
        $finalUri=$response.ResponseUri
    if($finalUri.Scheme -ne 'https' -or $finalUri.UserInfo -or -not $finalUri.IsDefaultPort -or
       -not ($finalUri.DnsSafeHost.EndsWith('.microsoft.com',[StringComparison]::OrdinalIgnoreCase) -or $finalUri.DnsSafeHost.EndsWith('.msedge.net',[StringComparison]::OrdinalIgnoreCase))) {
        $response.Dispose();throw 'Redirection ADK hors des domaines Microsoft autorises.'
    }
    $input=$response.GetResponseStream()
    $output=[IO.File]::Open($temporary,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{
        $total=[int64]$response.ContentLength
        $received=[int64]0
        $buffer=New-Object byte[] (1MB)
        $lastPublished=-1
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $output.Write($buffer,0,$read)
            $received += $read
            $ratio=if($total -gt 0){[math]::Min(1,$received/[double]$total)}else{0}
            $percent=if($total -gt 0){[int][math]::Floor($StartPercent+(($EndPercent-$StartPercent)*$ratio))}else{-1}
            if($percent -ne $lastPublished){
                $receivedText='{0:N1} Mo' -f ($received/1MB)
                $totalText=if($total -gt 0){'{0:N1} Mo' -f ($total/1MB)}else{'taille inconnue'}
                Write-BastosAdkProgress -Percent $percent -Phase $Phase -Message ("Téléchargement : $receivedText sur $totalText")
                $lastPublished=$percent
            }
        }
        $output.Flush()
    } finally {
        $output.Dispose()
        $input.Dispose()
        $response.Dispose()
    }
    if ($total -le 0 -or $received -ne $total) {throw 'Taille du telechargement ADK incorrecte ou non annoncee.'}
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

try {
    if(-not $OperationId){$OperationId=[guid]::NewGuid().ToString('N')}
    if(-not $DownloadDirectory){$DownloadDirectory=Join-Path $env:USERPROFILE 'Downloads\BASTOS-Prerequisites'}
    [IO.Directory]::CreateDirectory($DownloadDirectory)|Out-Null
    $receiptPath=Join-Path $DownloadDirectory 'Restart-required.json'
    Assert-BastosAdkRestartComplete -Path $receiptPath
    $logs=Join-Path $DownloadDirectory ('Logs\'+$OperationId)
    [IO.Directory]::CreateDirectory($logs)|Out-Null
    Write-BastosAdkProgress 2 'Detection ADK' 'Verification des outils Microsoft installes...'
    $existing=Get-BastosOscdimgPath
    if(-not $existing) {
        if(-not $InstallerPath){$InstallerPath=Join-Path $DownloadDirectory 'adksetup.exe'}
        if(-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
            Receive-BastosOfficialFile -Uri $officialUri -Destination $InstallerPath -Phase 'Telechargement ADK' -StartPercent 2 -EndPercent 8
        }
        Assert-BastosDeploymentSignature -Path $InstallerPath | Out-Null
        $setupVersion=[version]([Diagnostics.FileVersionInfo]::GetVersionInfo($InstallerPath).ProductVersion)
        if($setupVersion -notin @([version]'10.1.26100.2454',[version]'10.1.26100.9457')){throw "ADK_VERSION_UNSUPPORTED : installateur $setupVersion non valide."}
        Write-BastosAdkProgress 10 'Installation ADK' 'Installation des seuls outils de deploiement, sans redemarrage automatique...'
        $process=Start-Process -FilePath $InstallerPath -ArgumentList '/quiet','/ceip','off','/features','OptionId.DeploymentTools','/norestart' -PassThru -WindowStyle Hidden
        $process.WaitForExit();$installerExitCode=$process.ExitCode;$process.Dispose();$process=$null
        if($installerExitCode -notin @(0,3010)){throw "Installation ADK en echec (code $installerExitCode)."}
        if($installerExitCode -eq 3010){$rebootRequired=$true;throw 'ADK_RESTART_REQUIRED : redemarre Windows avant de creer ISO.'}
    }
    $version=Get-BastosAdkVersion
    if($version -eq [version]'10.1.26100.9457') {
        $evidence=Get-BastosAdkEvidence
        Save-AdkResult $true 'ADK 10.1.26100.9457 et outil Oscdimg verifies. Le correctif KB5101684 cible la base 2024 ; son application a cette autre revision n est pas revendiquee.'
        exit 0
    }
    if($version -ne [version]'10.1.26100.2454'){throw "ADK_VERSION_UNSUPPORTED : version detectee $version. Mets a jour les outils ADK depuis Microsoft."}
    # A local .ok file is never a proof that a patch is installed.
    if(-not $PatchPath){$PatchPath=Join-Path $DownloadDirectory 'Windows_ADK_10.1.26100.2454_Update_KB5101684.zip'}
    if(-not(Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
        Receive-BastosOfficialFile -Uri $officialPatchUri -Destination $PatchPath -Phase 'Telechargement du correctif ADK' -StartPercent 55 -EndPercent 69
    }
    $archiveHash=Get-BastosFileSha256 -Path $PatchPath
    if($archiveHash -ne 'DC19725A2FB0CCE44C32AC14059A85A25257B9534BA21C93B479F4F09FB5AF38'){throw 'ADK_PATCH_UNCONFIRMED : empreinte de archive KB5101684 incorrecte. Retelecharge le correctif de reference.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $patchRoot=Join-Path $tempBase ('BASTOS-ADK-Patch-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($patchRoot)|Out-Null
    $marker=Join-Path $patchRoot '.bastos-adk-extract'
    [IO.File]::WriteAllText($marker,$OperationId)
    try {
        $archive=[IO.Compression.ZipFile]::OpenRead($PatchPath)
        try {
            foreach($entry in $archive.Entries) {
                $target=[IO.Path]::GetFullPath((Join-Path $patchRoot $entry.FullName))
                if(-not $target.StartsWith($patchRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Chemin hors cible dans archive ADK.'}
            }
        } finally {$archive.Dispose()}
        [IO.Compression.ZipFile]::ExtractToDirectory($PatchPath,$patchRoot)
        $patches=@(Get-ChildItem -LiteralPath $patchRoot -Recurse -File -Filter '*.msp')
        if(-not $patches.Count){throw 'ADK_PATCH_UNCONFIRMED : aucun paquet MSP dans archive.'}
        $required=[Collections.Generic.List[object]]::new()
        $patchRuns=[Collections.Generic.List[object]]::new()
        foreach($msp in $patches) {
            Assert-BastosDeploymentSignature -Path $msp.FullName | Out-Null
            $metadata=Get-BastosPatchTargets -Path $msp.FullName
            $needsInstall=$false
            foreach($product in $metadata.Products) {
                $required.Add([pscustomobject]@{PatchCode=$metadata.PatchCode;ProductCode=$product})
                if((Get-BastosMsiPatchState -PatchCode $metadata.PatchCode -ProductCode $product) -notin @(1,2)){$needsInstall=$true}
            }
            if(-not $needsInstall){continue}
            Write-BastosAdkProgress 80 'Application du correctif ADK' $msp.Name
            $msiLog=Join-Path $logs ('msiexec-'+$msp.BaseName+'.log')
            $patchArgs=@('/p',('"{0}"' -f $msp.FullName),'/qn','/norestart','/l*v',('"{0}"' -f $msiLog))
            $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\msiexec.exe') -ArgumentList $patchArgs -PassThru -WindowStyle Hidden
            $process.WaitForExit();$code=$process.ExitCode;$process.Dispose();$process=$null
            $patchRuns.Add([pscustomobject]@{File=$msp.Name;ExitCode=$code;Log=$msiLog})
            if($code -eq 3010){$rebootRequired=$true}
            if($code -notin @(0,3010,1605,1642)){throw "Correctif ADK en echec : code $code. Journal : $msiLog"}
        }
        $evidence=Get-BastosAdkEvidence -RequiredPatches @($required.ToArray()) -ArchiveHash $archiveHash
        $evidence.PatchRuns=@($patchRuns.ToArray())
        if($rebootRequired){throw 'ADK_RESTART_REQUIRED : redemarre Windows pour terminer le correctif.'}
        Write-BastosAdkProgress 98 'Verification ADK' 'Correctifs relus dans Windows Installer ; signature et empreinte Oscdimg controlees.'
        Save-AdkResult $true 'Outils ADK et composants applicables de KB5101684 confirmes par Windows Installer.'
        exit 0
    } finally {
        $resolved=[IO.Path]::GetFullPath($patchRoot)
        if($resolved.StartsWith($tempBase+'\BASTOS-ADK-Patch-',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $marker) -and
           ([IO.File]::ReadAllText($marker) -eq $OperationId)) {Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue}
    }
} catch {
    $failureMessage=$_.Exception.Message
    if($_.Exception.Message -match '^ADK_RESTART_REQUIRED'){$rebootRequired=$true}
    if($rebootRequired -and $receiptPath -and -not (Test-Path -LiteralPath $receiptPath)) {
        try{Save-BastosAdkRestart -Path $receiptPath}catch{$evidence.ActionCompletionUnconfirmed=$true;$evidence.RestartReceiptError=$_.Exception.Message}
    }
    $evidence.ErrorCode=if($rebootRequired){'ADK_RESTART_REQUIRED'}elseif($_.Exception.Message -match '^ADK_PATCH_UNCONFIRMED'){'ADK_PATCH_UNCONFIRMED'}elseif($_.Exception.Message -match '^ADK_VERSION_UNSUPPORTED'){'ADK_VERSION_UNSUPPORTED'}else{'ADK_PREPARATION_FAILED'}
    if($process){try{$evidence.ActionCompletionUnconfirmed=(-not $process.HasExited)}catch{$evidence.ActionCompletionUnconfirmed=$true}}
    try{Save-AdkResult $false $failureMessage}catch{[Console]::Error.WriteLine($_.Exception.Message)}
    exit 1
}
