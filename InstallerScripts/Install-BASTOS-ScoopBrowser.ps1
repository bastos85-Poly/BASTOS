[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('ungoogled-chromium','thorium-avx2')][string]$Browser,
    [ValidateSet('Install','Uninstall')][string]$Action='Install',
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Save-Result([bool]$Success,[string]$Message) {
    $result=[ordered]@{Success=$Success;Browser=$Browser;Message=$Message;Date=[DateTime]::UtcNow.ToString('o')}
    if($ResultPath){$parent=Split-Path -Parent $ResultPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    [pscustomobject]$result
}

try {
    $scoopCommand=Get-Command scoop.ps1,scoop.cmd -ErrorAction SilentlyContinue|Select-Object -First 1
    $scoopPath=if($scoopCommand){[string]$scoopCommand.Source}else{''}
    $fallback=Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'
    if(-not $scoopPath -and (Test-Path -LiteralPath $fallback -PathType Leaf)){$scoopPath=$fallback}
    if(-not $scoopPath -and $Action -eq 'Uninstall'){
        Save-Result $true "$Browser n est pas installe par Scoop."|Out-Null
        exit 0
    }
    if(-not $scoopPath){
        $installer=Join-Path $env:TEMP 'BASTOS-Scoop-Install.ps1'
        $uri='https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
        $response=Invoke-WebRequest -Uri $uri -UseBasicParsing -MaximumRedirection 3 -TimeoutSec 45
        if($response.BaseResponse.ResponseUri.Host -ne 'raw.githubusercontent.com'){throw 'Le programme Scoop ne provient pas du domaine GitHub officiel attendu.'}
        [IO.File]::WriteAllText($installer,[string]$response.Content,[Text.UTF8Encoding]::new($false))
        $installProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File',$installer) -PassThru -Wait -WindowStyle Hidden
        if($installProcess.ExitCode -ne 0){throw "Installation de Scoop impossible (code $($installProcess.ExitCode))."}
        $scoopCommand=Get-Command scoop.ps1,scoop.cmd -ErrorAction SilentlyContinue|Select-Object -First 1
        $scoopPath=if($scoopCommand){[string]$scoopCommand.Source}else{''}
        if(-not $scoopPath){
            if(Test-Path -LiteralPath $fallback -PathType Leaf){$scoopPath=$fallback}
        }
    }
    if(-not $scoopPath){throw 'Scoop reste introuvable apres son installation officielle.'}

    $bucket=if($Browser -eq 'thorium-avx2'){'versions'}else{'extras'}
    if($Action -eq 'Install'){
        & $scoopPath bucket add $bucket 2>&1|Out-Null
        & $scoopPath update 2>&1|Out-Null
        & $scoopPath install "$bucket/$Browser"
        if($LASTEXITCODE -ne 0){throw "Scoop a retourne le code $LASTEXITCODE pour $Browser."}
        Save-Result $true "$Browser est installe ou deja a jour."|Out-Null
    }else{
        $scoopAppRoot=Join-Path $env:USERPROFILE "scoop\apps\$Browser"
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($scoopAppRoot,[StringComparison]::OrdinalIgnoreCase)}|ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
        & $scoopPath uninstall $Browser -p
        if($LASTEXITCODE -ne 0){throw "Scoop a retourne le code $LASTEXITCODE pendant la suppression de $Browser."}
        $cleanup=if($Browser -eq 'ungoogled-chromium'){@("$env:LOCALAPPDATA\Chromium","$env:APPDATA\Chromium",(Join-Path $env:USERPROFILE 'scoop\persist\ungoogled-chromium'))}else{@("$env:LOCALAPPDATA\Thorium","$env:APPDATA\Thorium",(Join-Path $env:USERPROFILE 'scoop\persist\thorium-avx2'))}
        $allowedRoots=@($env:LOCALAPPDATA,$env:APPDATA,$env:USERPROFILE)|ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\')}
        foreach($target in $cleanup){
            if(-not(Test-Path -LiteralPath $target)){continue}
            $full=[IO.Path]::GetFullPath($target).TrimEnd('\');$approved=$false
            foreach($root in $allowedRoots){if($full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)-and $full.Length-gt($root.Length+1)){$approved=$true;break}}
            if(-not $approved){throw "Chemin de nettoyage refuse : $full"}
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
        }
        $shortcutPattern=if($Browser -eq 'ungoogled-chromium'){'Chromium'}else{'Thorium'}
        foreach($root in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'))){if($root-and(Test-Path $root)){Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue|Where-Object {$_.Name-match $shortcutPattern-and $_.Extension-in '.lnk','.url'}|Remove-Item -Force -ErrorAction SilentlyContinue}}
        $remaining=@($cleanup|Where-Object {Test-Path -LiteralPath $_})
        if($remaining.Count){throw "Nettoyage incomplet : $($remaining -join '; ')"}
        Save-Result $true "$Browser et toutes ses donnees locales ont ete supprimes."|Out-Null
    }
    exit 0
} catch {
    Save-Result $false $_.Exception.Message|Out-Null
    exit 1
}
