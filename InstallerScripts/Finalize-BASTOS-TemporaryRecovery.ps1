[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ResultPath=(Join-Path $env:ProgramData 'BASTOS-ISO\Logs\Recovery-Finalization.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'BASTOS-ISO'
$profilePath=Join-Path $root 'Installation-Expected.json'
$receiptPath=Join-Path $root 'Logs\Rufus-FirstLogon.ok'
$logRoot=Join-Path $root 'Logs'
$partitionWritesStarted=$false
New-Item -ItemType Directory -Path $logRoot -Force|Out-Null
function Write-FinalizationReport([string]$status,[string]$message,$details){
    $report=[ordered]@{Schema=1;Status=$status;Message=$message;CheckedUtc=[DateTime]::UtcNow.ToString('o');Details=$details}
    [IO.File]::WriteAllText($ResultPath,($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]$report
}
function Assert-VerifiedWindowsApplication {
    $buildPath=Join-Path $root 'BASTOS-Build.json'
    $manifestPath=Join-Path $root 'BASTOS-App-Manifest.json'
    $build=Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne [string]$build.AppManifestSha256){throw 'Manifeste Bastos sur C: invalide.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($entry in $manifest.Files){
        $relative=([string]$entry.Path).Replace('/','\')
        if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or @($relative.Split('\')|Where-Object{$_ -in @('.','..')}).Count){throw "Chemin interdit : $relative"}
        if((Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash -ne [string]$entry.Sha256){throw "Application Bastos sur C: incomplete : $relative"}
    }
    $exe=Join-Path $root 'Bastos.Native\BASTOS-Native.exe'
    if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne [string]$build.NativeAppSha256){throw 'Executable Bastos sur C: invalide.'}
    return $exe
}
try {
    $profile=Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8|ConvertFrom-Json
    if($profile.Schema -ne 2 -or -not $profile.PSObject.Properties['ApplicationPlacement'] -or $profile.ApplicationPlacement -ne 'Windows'){throw 'Cette installation ne prevoit pas encore une application Bastos independante de D:.'}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($receipt.ProfileId -ne $profile.ProfileId -or $receipt.ProfileSha256 -ne (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash -or
       $receipt.MachineGuid -ne [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography','MachineGuid',$null)){
        throw 'Premiere connexion ou profil de reinstallation non verifies.'
    }
    $exe=Assert-VerifiedWindowsApplication
    $c=Get-Partition -DriveLetter C -ErrorAction Stop
    $cDisk=Get-Disk -Number $c.DiskNumber -ErrorAction Stop
    if($cDisk.PartitionStyle -ne 'GPT' -or [guid]$cDisk.Guid -ne [guid]$profile.WindowsDiskIdentity){throw 'Identite du disque Windows modifiee.'}
    $appPart=Get-Partition -Volume (Get-Volume -FilePath $exe -ErrorAction Stop) -ErrorAction Stop
    if([guid]$appPart.Guid -ne [guid]$c.Guid){throw 'Bastos ne fonctionne pas depuis C:.'}
    $d=Get-Partition -DriveLetter D -ErrorAction Stop
    $dVolume=$d|Get-Volume -ErrorAction Stop
    if($d.DiskNumber -ne $c.DiskNumber -or [guid]$d.Guid -ne [guid]$profile.RecoveryPartitionGuid -or
       $dVolume.FileSystemLabel -ne 'BASTOS_RECOVERY' -or $dVolume.FileSystem -ne 'NTFS' -or $d.Size -lt 35GB -or $d.Size -gt 45GB){
        throw 'D: ne correspond pas exactement a la partition temporaire attendue.'
    }
    $parts=@(Get-Partition -DiskNumber $c.DiskNumber -ErrorAction Stop|Sort-Object Offset)
    if($parts[-1].Guid -ne $d.Guid){throw 'BASTOS_RECOVERY n est pas la derniere partition du disque.'}
    $between=@($parts|Where-Object{$_.Offset -gt $c.Offset -and $_.Offset -lt $d.Offset})
    if(@($between|Where-Object{$_.GptType -ne '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'}).Count -gt 0 -or $between.Count -gt 1){throw 'Une autre partition separe C: et D:.'}
    $running=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and $_.ExecutablePath.StartsWith('D:\',[StringComparison]::OrdinalIgnoreCase)})
    if($running.Count){throw 'Un programme utilise encore D:.'}
    $bootmgr=(& bcdedit.exe /enum '{bootmgr}' 2>&1|Out-String)
    if($LASTEXITCODE -ne 0 -or $bootmgr -match '(?im)^\s*bootsequence\s+'){throw 'Demarrage temporaire encore programme ou BCD non lisible.'}
    $reagentInfo=(& reagentc.exe /info 2>&1|Out-String)
    if($LASTEXITCODE -ne 0 -or $reagentInfo -notmatch '(?im)^\s*[^\r\n]*(?:Windows\s*RE|WinRE)[^\r\n]*:\s*(Enabled|Activé|Active)\s*$'){throw 'WinRE non verifie actif.'}
    $winreCandidates=@((Join-Path 'D:\' 'Recovery\WindowsRE\Winre.wim'),(Join-Path $env:SystemRoot 'System32\Recovery\Winre.wim'))
    if($between.Count -eq 1){$winreCandidates+=('\\?\GLOBALROOT\device\harddisk'+$c.DiskNumber+'\partition'+$between[0].PartitionNumber+'\Recovery\WindowsRE\Winre.wim')}
    $winreSource=@($winreCandidates|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1)
    if($winreSource.Count -ne 1){throw 'Image WinRE source introuvable.'}
    $details=[ordered]@{DiskGuid=[string]$cDisk.Guid;WindowsGuid=[string]$c.Guid;RecoveryGuid=[string]$d.Guid;WindowsOffset=[long]$c.Offset;RecoveryOffset=[long]$d.Offset;RecoveryBytes=[long]$d.Size;IntermediateWinREGuid=if($between.Count){[string]$between[0].Guid}else{''};WinreSource=$winreSource[0];Application=$exe}
    if(-not $Apply){Write-FinalizationReport 'Ready' 'C: et D: verifies. La finalisation peut etre demandee apres sauvegarde.' $details;return}
    $principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'La finalisation demande une session administrateur elevee.'}
    # Keep the recovery image on C: before touching either recovery partition.
    $savedImage=Join-Path $root 'Winre-Finalization.wim'
    if(-not(Test-Path -LiteralPath $savedImage -PathType Leaf)){
        Copy-Item -LiteralPath $winreSource[0] -Destination $savedImage -ErrorAction Stop
    }
    if((Get-FileHash -LiteralPath $savedImage -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $winreSource[0] -Algorithm SHA256).Hash){throw 'Copie temporaire WinRE invalide.'}
    $imageStream=[IO.File]::OpenRead($savedImage)
    try {$imageLength=$imageStream.Length} finally {$imageStream.Dispose()}
    if($imageLength -lt 100MB -or $imageLength -gt 2GB){throw 'Taille de l image WinRE inattendue.'}
    Write-FinalizationReport 'Started' 'Image WinRE sauvegardee sur C:. Debut de la finalisation.' $details|Out-Null
    & reagentc.exe /disable | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Impossible de desactiver WinRE ; aucune partition supprimee.'}
    $partitionWritesStarted=$true
    # Re-resolve each partition by GUID. Partition numbers may change after a deletion.
    if($between.Count -eq 1){
        $oldWinre=@(Get-Partition -DiskNumber $c.DiskNumber|Where-Object{[guid]$_.Guid -eq [guid]$between[0].Guid})
        if($oldWinre.Count -ne 1 -or $oldWinre[0].GptType -ne '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}') {throw 'Ancienne partition WinRE modifiee ; arret.'}
        $oldWinre[0]|Remove-Partition -Confirm:$false -ErrorAction Stop
    }
    $temporary=@(Get-Partition -DiskNumber $c.DiskNumber|Where-Object{[guid]$_.Guid -eq [guid]$d.Guid})
    if($temporary.Count -ne 1 -or [long]$temporary[0].Offset -ne [long]$d.Offset){throw 'Partition BASTOS_RECOVERY modifiee ; arret.'}
    $temporary[0]|Remove-Partition -Confirm:$false -ErrorAction Stop
    $windows=@(Get-Partition -DiskNumber $c.DiskNumber|Where-Object{[guid]$_.Guid -eq [guid]$c.Guid})
    if($windows.Count -ne 1){throw 'Partition Windows introuvable apres retrait de D:.'}
    $supported=Get-PartitionSupportedSize -DriveLetter C -ErrorAction Stop
    $reserve=1536MB
    $newSize=[long]$supported.SizeMax-$reserve
    if($newSize -le [long]$windows[0].Size){throw 'Espace non contigu ou insuffisant pour agrandir C: et recreer WinRE.'}
    Resize-Partition -DriveLetter C -Size $newSize -ErrorAction Stop
    $newWinre=New-Partition -DiskNumber $c.DiskNumber -UseMaximumSize -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -AssignDriveLetter -ErrorAction Stop
    if($newWinre.Size -lt 1GB -or -not $newWinre.DriveLetter){throw 'Nouvelle partition WinRE incomplete.'}
    Format-Volume -Partition $newWinre -FileSystem NTFS -NewFileSystemLabel 'Windows RE tools' -Confirm:$false -ErrorAction Stop|Out-Null
    $target=Join-Path (([string]$newWinre.DriveLetter)+':\') 'Recovery\WindowsRE'
    New-Item -ItemType Directory -Path $target -Force|Out-Null
    $destination=Join-Path $target 'Winre.wim'
    Copy-Item -LiteralPath $savedImage -Destination $destination -ErrorAction Stop
    if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $savedImage -Algorithm SHA256).Hash){throw 'Nouvelle image WinRE invalide.'}
    & reagentc.exe /setreimage /path $target | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Enregistrement de WinRE refuse.'}
    & reagentc.exe /enable | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Reactivation de WinRE refusee.'}
    $verified=(& reagentc.exe /info 2>&1|Out-String)
    $location=[regex]::Match($verified,'\\\\\?\\GLOBALROOT\\device\\harddisk\d+\\partition\d+\\Recovery\\WindowsRE','IgnoreCase')
    if($LASTEXITCODE -ne 0 -or $verified -notmatch '(?im)^\s*[^\r\n]*(?:Windows\s*RE|WinRE)[^\r\n]*:\s*(Enabled|Activé|Active)\s*$' -or -not $location.Success){
        throw 'WinRE ne pointe pas vers sa nouvelle partition.'
    }
    $registeredImage=$location.Value+'\Winre.wim'
    if((Get-FileHash -LiteralPath $registeredImage -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $savedImage -Algorithm SHA256).Hash){throw 'WinRE enregistre ne correspond pas a la nouvelle image.'}
    $newWinre|Remove-PartitionAccessPath -AccessPath (([string]$newWinre.DriveLetter)+':\') -ErrorAction Stop
    $ordered=@(Get-Partition -DiskNumber $c.DiskNumber|Sort-Object Offset)
    if([guid]$ordered[-1].Guid -ne [guid]$newWinre.Guid){throw 'Nouvelle partition WinRE non finale.'}
    $nativeNumber=$ordered.Count
    $diskpartFile=Join-Path $logRoot 'Recovery-Finalization-DiskPart.txt'
    @("select disk $($c.DiskNumber)","select partition $nativeNumber",'gpt attributes=0x8000000000000001')|Set-Content -LiteralPath $diskpartFile -Encoding ASCII
    $diskpartOutput=(& diskpart.exe /s $diskpartFile 2>&1|Out-String)
    [IO.File]::WriteAllText((Join-Path $logRoot 'Recovery-Finalization-DiskPart.log'),$diskpartOutput)
    if($LASTEXITCODE -ne 0){throw 'Attributs de protection WinRE non appliques.'}
    $hidden=@(Get-Partition -DiskNumber $c.DiskNumber|Where-Object{[guid]$_.Guid -eq [guid]$newWinre.Guid})
    if($hidden.Count -ne 1 -or -not $hidden[0].IsHidden -or $hidden[0].DriveLetter){throw 'Nouvelle partition WinRE non masquee.'}
    if(Get-Partition -DiskNumber $c.DiskNumber|Where-Object{[guid]$_.Guid -eq [guid]$d.Guid}){throw 'D: est encore present.'}
    Write-FinalizationReport 'Completed' 'D: supprime, espace rendu a C: et WinRE verifie.' $details
} catch {
    Write-FinalizationReport $(if($partitionWritesStarted){'Incomplete'}else{'Blocked'}) $_.Exception.Message @{ErrorId=$_.FullyQualifiedErrorId;ScriptStack=$_.ScriptStackTrace} | Out-Null
    throw
}
