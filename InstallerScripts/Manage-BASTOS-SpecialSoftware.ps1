[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CustomAction,
    [Parameter(Mandatory)][ValidateSet('Install','Uninstall')][string]$Action,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$portableRoot = Join-Path $env:LOCALAPPDATA 'BASTOS\Software\Portable'
$toolsRoot = Join-Path $env:LOCALAPPDATA 'BASTOS\Tools'

function Save-Result([bool]$Success, [string]$Message) {
    $parent = Split-Path -Parent $ResultPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($ResultPath, ([pscustomobject]@{ Success=$Success; Message=$Message } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
}

function Remove-ManagedFolder([string]$Path) {
    $root = [IO.Path]::GetFullPath($portableRoot).TrimEnd('\') + '\'
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Suppression hors de la zone portable BASTOS refusée.' }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function New-DesktopShortcut([string]$Name, [string]$Target, [string]$Arguments = '') {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if (-not $desktop) { return }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop ($Name + '.lnk')))
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = Split-Path -Parent $Target
    $shortcut.IconLocation = "$Target,0"
    $shortcut.Save()
}

function Get-BastosSourceForgeFileUrl([string]$Html,[string]$ExpectedPath){
    foreach($match in [regex]::Matches($Html,'https://downloads\.sourceforge\.net/project/[^"\s<>]+')){
        $candidate=[Uri][Net.WebUtility]::HtmlDecode($match.Value)
        if($candidate.Scheme -eq 'https' -and $candidate.DnsSafeHost -eq 'downloads.sourceforge.net' -and $candidate.AbsolutePath -ceq $ExpectedPath){return $candidate.AbsoluteUri}
    }
    throw 'Lien SourceForge du fichier exact introuvable dans la page officielle.'
}

function Assert-BastosMicrosoftTool([string]$Path){
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    if([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -ne 'Microsoft Corporation'){throw 'Signature Microsoft de Process Explorer non valide.'}
}

function Invoke-VerifiedDownload([string]$Uri, [string]$Destination, [string]$Sha256) {
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https') { throw 'Seuls les téléchargements HTTPS sont autorisés.' }
    # AMD otherwise returns an HTML "Download Not Complete" page with a successful HTTP status.
    $headers = @{}
    if ($parsed.DnsSafeHost -eq 'drivers.amd.com') { $headers['Referer'] = 'https://www.amd.com/' }
    if($parsed.DnsSafeHost -eq 'sourceforge.net' -and $parsed.AbsolutePath -match '^/projects/([^/]+)/files/(.+)/download$'){
        $expectedPath='/project/'+$Matches[1]+'/'+$Matches[2]
        $landing=$parsed.GetLeftPart([UriPartial]::Path)
        Invoke-WebRequest -Uri $landing -OutFile $Destination -UseBasicParsing -TimeoutSec 60
        if((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Sha256){
            if((Get-Item -LiteralPath $Destination).Length -gt 2MB){throw 'Reponse SourceForge inattendue ; aucun fichier accepte.'}
            $html=[IO.File]::ReadAllText($Destination)
            $direct=Get-BastosSourceForgeFileUrl $html $expectedPath
            Invoke-WebRequest -Uri $direct -OutFile $Destination -UseBasicParsing -TimeoutSec 180
        }
    }else{
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -Headers $headers -TimeoutSec 180
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $Sha256) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "Empreinte SHA-256 invalide pour $($parsed.Host)."
    }
}

function Get-AudioProduct([string]$Name) {
    return Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -eq $Name } | Select-Object -First 1
}

function Test-VersionAtLeast([string]$Actual,[string]$Required) {
    try { return [version]$Actual -ge [version]$Required } catch { return $false }
}

function Install-BastosAudioTool([ValidateSet('EqualizerAPO','Peace')][string]$Tool) {
    $definition = if ($Tool -eq 'EqualizerAPO') {
        @{ Product='Equalizer APO'; Version='1.4.2'; File='EqualizerAPO-x64-1.4.2.exe';
           Uri='https://sourceforge.net/projects/equalizerapo/files/1.4.2/EqualizerAPO-x64-1.4.2.exe/download?use_mirror=master';
           Hash='7403BE7427BBE1936A40DDED082829B6E217FC4F5990FEE5CBA501F0AE055AFA'; Length=11980366; Signer='' }
    } else {
        @{ Product='Peace'; Version='1.6.9.11'; File='PeaceSetup.exe';
           Uri='https://sourceforge.net/projects/peace-equalizer-apo-extension/files/PeaceSetup.exe/download?use_mirror=master';
           Hash='D007A5EFCBE361EFBE5EC88EEA8EFF6191D0188E8C7111354CBB063FBAC26F2C'; Length=55657784; Signer='Petrus Verbeek' }
    }
    $installed=Get-AudioProduct $definition.Product
    if($installed -and (Test-VersionAtLeast ([string]$installed.DisplayVersion) $definition.Version)) {
        return "$($definition.Product) $($installed.DisplayVersion) est déjà à jour."
    }
    if($Tool -eq 'Peace' -and !(Get-AudioProduct 'Equalizer APO')) {
        $dependency=Install-BastosAudioTool 'EqualizerAPO'
    }
    $download=Join-Path $env:TEMP ("BASTOS-{0}-{1}" -f [guid]::NewGuid().ToString('N'),$definition.File)
    try {
        $curl=(Get-Command curl.exe -ErrorAction Stop).Source
        & $curl -L --fail --silent --show-error --output $download $definition.Uri
        if($LASTEXITCODE -ne 0){throw "Le téléchargement officiel de $($definition.Product) a échoué (code $LASTEXITCODE)."}
        if((Get-Item -LiteralPath $download).Length -ne $definition.Length){throw "Taille inattendue pour $($definition.Product)."}
        $bytes=[IO.File]::ReadAllBytes($download)
        if($bytes.Length -lt 2 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A){throw "Le téléchargement de $($definition.Product) n’est pas un exécutable Windows."}
        if((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $definition.Hash){throw "Empreinte SHA-256 invalide pour $($definition.Product)."}
        if($definition.Signer){
            $signature=Get-AuthenticodeSignature -LiteralPath $download
            if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike "*$($definition.Signer)*"){throw "Signature éditeur invalide pour $($definition.Product)."}
        }
        $process=Start-Process -FilePath $download -Wait -PassThru
        if($process.ExitCode -notin @(0,3010)){throw "L’assistant de $($definition.Product) a renvoyé le code $($process.ExitCode)."}
        $after=Get-AudioProduct $definition.Product
        if(!$after -or !(Test-VersionAtLeast ([string]$after.DisplayVersion) $definition.Version)){throw "$($definition.Product) $($definition.Version) n’a pas été confirmé après l’assistant."}
        return "$($definition.Product) $($after.DisplayVersion) est installé."
    } finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}

function Uninstall-BastosAudioTool([ValidateSet('EqualizerAPO','Peace')][string]$Tool) {
    $product=if($Tool -eq 'EqualizerAPO'){'Equalizer APO'}else{'Peace'}
    if($Tool -eq 'EqualizerAPO' -and (Get-AudioProduct 'Peace')){throw 'Peace est encore installé. Désinstallez Peace avant Equalizer APO.'}
    $entry=Get-AudioProduct $product
    if(!$entry){return "$product est déjà absent."}
    $path=if($Tool -eq 'Peace'){Join-Path $env:ProgramFiles 'EqualizerAPO\config\PeaceSetup.exe'}else{Join-Path $env:ProgramFiles 'EqualizerAPO\Uninstall.exe'}
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Désinstallateur de $product introuvable."}
    $arguments=if($Tool -eq 'Peace'){@('2')}else{@()}
    $process=if($arguments.Count){Start-Process -FilePath $path -ArgumentList $arguments -Wait -PassThru}else{Start-Process -FilePath $path -Wait -PassThru}
    if($process.ExitCode -notin @(0,3010)){throw "Le désinstalleur de $product a renvoyé le code $($process.ExitCode)."}
    if(Get-AudioProduct $product){throw "$product est toujours détecté après le désinstalleur."}
    return "$product a été désinstallé."
}

function Expand-VerifiedArchive([string]$ArchivePath, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.Name)) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive non sûre refusée.' }
            $parent = Split-Path -Parent $target
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally { $archive.Dispose() }
}

function Get-OfficialToolDefinition([string]$Tool) {
    $definitions = @{
        AMDCleanupUtility = @{ Name='AMD Cleanup Utility'; Folder='AMDCleanupUtility'; Uri='https://drivers.amd.com/drivers/amdcleanuputility.exe'; Hash='D05A543685AEA37D50995D294EAF5F384F3546CF74CCA1A37B4D5787E71B744E'; Archive=$false; Executable='amdcleanuputility.exe' }
        NSudo = @{ Name='NSudo'; Folder='NSudo'; Uri='https://github.com/M2TeamArchived/NSudo/releases/download/8.2/NSudo_8.2_All_Components.zip'; Hash='346E38030CC9EEEF48223804BA27631DB96691D68BFC5D1728140D468F555204'; Archive=$true; Executable='NSudo Launcher\x64\NSudoLG.exe' }
        DriverView = @{ Name='DriverView'; Folder='DriverView'; Uri='https://www.nirsoft.net/utils/driverview-x64.zip'; Hash='8998E99E733BF112DECF3A9C6954D86787D5A76F8347FFA50CAF55CD7DF9B4FE'; Archive=$true; Executable='DriverView.exe' }
        WUManager = @{ Name='WU Manager'; Folder='WUManager'; Uri='https://github.com/DavidXanatos/wumgr/releases/download/v1.1/WuMgr_v1.1b.zip'; Hash='585F10D7D75779B8A74859A9B70A925370F593B239ECF8B8C328ED59C71B276A'; Archive=$true; Executable='wumgr.exe' }
        MouseTester = @{ Name='Mouse Tester'; Folder='MouseTester'; Uri='https://github.com/valleyofdoom/MouseTester/releases/download/MouseTester_v1.7.2/MouseTester.exe'; Hash='9539E9387AB5C9A5A220D29360EE00D82526462B7A3960FCE0B43542D53C9782'; Archive=$false; Executable='MouseTester.exe' }
        MeasureSleep = @{ Name='Measure Sleep'; Folder='MeasureSleep'; Uri='https://github.com/valleyofdoom/TimerResolution/releases/download/MeasureSleep-v1.0.0/MeasureSleep.exe'; Hash='A7F61D8DA8AC5BAF2D1E01582A487D8849334B3A3B6AA70F52022923F2AF9D1A'; Archive=$false; Executable='MeasureSleep.exe' }
    }
    if (-not $definitions.ContainsKey($Tool)) { throw "Outil officiel inconnu : $Tool" }
    return $definitions[$Tool]
}

try {
    if ($CustomAction -like 'AudioTool:*') {
        $tool=$CustomAction.Split(':',2)[1]
        $message=if($Action -eq 'Install'){Install-BastosAudioTool $tool}else{Uninstall-BastosAudioTool $tool}
        Save-Result $true $message
        exit 0
    }

    if ($CustomAction -eq 'WindowsUtility' -or $CustomAction -eq 'Winhance') {
        if ($Action -eq 'Uninstall') {
            Save-Result $true 'Cet outil est lancé à la demande et ne laisse aucun composant BASTOS installé.'
            exit 0
        }
        $uri = if ($CustomAction -eq 'WindowsUtility') { 'https://christitus.com/win' } else { 'https://winhance.net/' }
        Start-Process -FilePath $uri -ErrorAction Stop | Out-Null
        Save-Result $true 'La page officielle a ete ouverte. Aucun script ni logiciel n a ete installe par Bastos ; suis les instructions de l editeur si tu veux cet outil.'
        exit 0
    }

    if ($CustomAction -like 'RadeonTool:*') {
        $tool = $CustomAction.Split(':',2)[1]
        $folder = Join-Path $portableRoot $tool
        if ($Action -eq 'Uninstall') {
            Get-Process -Name $tool -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Remove-ManagedFolder $folder
            $shortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) ($tool + '.lnk')
            Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
            Save-Result $true "$tool a été supprimé."
            exit 0
        }
        $childResult = Join-Path $env:TEMP ("BASTOS-Radeon-{0}.json" -f [Guid]::NewGuid().ToString('N'))
        & (Join-Path $PSScriptRoot 'Download-BASTOS-RadeonTool.ps1') -Tool $tool -DestinationRoot $portableRoot -ResultPath $childResult
        $result = Get-Content -LiteralPath $childResult -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item -LiteralPath $childResult -Force -ErrorAction SilentlyContinue
        if (-not $result.Success) { throw [string]$result.Message }
        New-DesktopShortcut $result.Name $result.ExecutablePath
        Save-Result $true ([string]$result.Message)
        exit 0
    }

    if ($CustomAction -like 'OfficialTool:*') {
        $tool = $CustomAction.Split(':',2)[1]

        if($tool -eq 'ProcessExplorer'){
            $folder=Join-Path $portableRoot 'ProcessExplorer'
            $target=Join-Path $folder 'procexp64.exe'
            $shortcut=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) 'Process Explorer.lnk'
            if($Action -eq 'Uninstall'){
                if(Get-Process procexp,procexp64 -ErrorAction SilentlyContinue){throw 'Ferme Process Explorer avant de le retirer.'}
                Remove-ManagedFolder $folder
                Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
                Save-Result $true 'Process Explorer portable a ete retire.'
                exit 0
            }
            $stage=Join-Path $portableRoot ('ProcessExplorer-stage-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory $stage -Force|Out-Null
            $zip=Join-Path $stage 'ProcessExplorer.zip'
            try{
                Invoke-WebRequest 'https://download.sysinternals.com/files/ProcessExplorer.zip' -OutFile $zip -UseBasicParsing -TimeoutSec 180
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $archive=[IO.Compression.ZipFile]::OpenRead($zip)
                try{foreach($entry in $archive.Entries){if($entry.FullName -notin @('procexp.exe','procexp64.exe','procexp64a.exe','Eula.txt')){throw 'Archive Process Explorer inattendue.'}}}finally{$archive.Dispose()}
                Expand-VerifiedArchive $zip $stage
                foreach($name in @('procexp.exe','procexp64.exe','procexp64a.exe')){
                    Assert-BastosMicrosoftTool (Join-Path $stage $name)
                }
                Remove-Item -LiteralPath $zip -Force
                if(Test-Path -LiteralPath $folder){[IO.Directory]::Move($folder,$folder+'-before-'+[guid]::NewGuid().ToString('N'))}
                [IO.Directory]::Move($stage,$folder)
                [IO.File]::WriteAllText((Join-Path $folder 'BASTOS-installed.json'),'{"Publisher":"Microsoft Corporation","Source":"https://download.sysinternals.com/files/ProcessExplorer.zip"}',[Text.UTF8Encoding]::new($false))
                New-DesktopShortcut 'Process Explorer' $target
                Save-Result $true 'Process Explorer portable est pret ; les trois executables Microsoft ont ete verifies. Aucun outil lance.'
                exit 0
            }finally{if(Test-Path -LiteralPath $stage){Remove-ManagedFolder $stage}}
        }

        if ($tool -eq 'PerfMeasurement') {
            $folder = Join-Path $portableRoot 'PerfMeasurement'
            $marker = Join-Path $folder 'PerfMeasurement.installed'
            $shortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) 'Perf Measurement.lnk'
            if ($Action -eq 'Uninstall') {
                Remove-ManagedFolder $folder
                Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
                Save-Result $true 'Perf Measurement a été supprimé.'
                exit 0
            }
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            [IO.File]::WriteAllText($marker, "Rapport de performances Windows`r`n", [Text.UTF8Encoding]::new($false))
            New-DesktopShortcut 'Perf Measurement' (Join-Path $env:WINDIR 'System32\perfmon.exe') '/report'
            Save-Result $true 'Perf Measurement est prêt sur le Bureau et ouvre le rapport natif de Windows.'
            exit 0
        }

        if ($tool -eq 'OCAT') {
            $folder = Join-Path $portableRoot 'OCAT'
            $marker = Join-Path $folder 'OCAT.installed'
            if ($Action -eq 'Uninstall') {
                $uninstall = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -match '^OCAT(?:\s|$)' } | Select-Object -First 1
                if ($uninstall) {
                    $quietProperty = $uninstall.PSObject.Properties['QuietUninstallString']
                    $normalProperty = $uninstall.PSObject.Properties['UninstallString']
                    $command = if ($quietProperty -and $quietProperty.Value) { [string]$quietProperty.Value } elseif ($normalProperty) { [string]$normalProperty.Value } else { '' }
                    if ($command) {
                        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/s','/c',($command + ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART')) -Wait -PassThru
                        if ($process.ExitCode -notin @(0,1605,1614)) { throw "Le désinstalleur OCAT a renvoyé le code $($process.ExitCode)." }
                    }
                }
                Remove-ManagedFolder $folder
                Save-Result $true 'OCAT a été supprimé.'
                exit 0
            }
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $installer = Join-Path $env:TEMP ("BASTOS-OCAT-{0}.exe" -f [Guid]::NewGuid().ToString('N'))
            try {
                Invoke-VerifiedDownload 'https://github.com/GPUOpen-Tools/ocat/releases/download/v1.6.3/OCAT_v1.6.3.exe' $installer 'A6D036BEC963BB38F77B72D4591F3D172AAC122D8E441BD9DBB54223EE6B6695'
                $process = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-') -Wait -PassThru
                if ($process.ExitCode -notin @(0,3010)) { throw "L’installateur OCAT a renvoyé le code $($process.ExitCode)." }
                [IO.File]::WriteAllText($marker, "OCAT 1.6.3`r`n", [Text.UTF8Encoding]::new($false))
            } finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
            Save-Result $true 'OCAT 1.6.3 est installé et vérifié.'
            exit 0
        }

        $definition = Get-OfficialToolDefinition $tool
        # Never interrupt a running driver cleanup, including during portable removal/replacement.
        if ($tool -eq 'AMDCleanupUtility' -and (Get-Process -Name 'amdcleanuputility' -ErrorAction SilentlyContinue)) {
            throw "AMD Cleanup Utility est en cours d’exécution. Termine le nettoyage et ferme l’outil avant de modifier sa copie portable."
        }
        $folder = Join-Path $portableRoot $definition.Folder
        $target = Join-Path $folder $definition.Executable
        $shortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) ($definition.Name + '.lnk')
        if ($Action -eq 'Uninstall') {
            if ($tool -ne 'AMDCleanupUtility') {
                Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($target)) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Remove-ManagedFolder $folder
            Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
            Save-Result $true "$($definition.Name) a été supprimé."
            exit 0
        }

        Remove-ManagedFolder $folder
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $download = Join-Path $env:TEMP ("BASTOS-$tool-{0}.download" -f [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-VerifiedDownload $definition.Uri $download $definition.Hash
            if ($definition.Archive) { Expand-VerifiedArchive $download $folder }
            else { Move-Item -LiteralPath $download -Destination $target -Force }
        } finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Exécutable $tool introuvable après installation." }
        New-DesktopShortcut $definition.Name $target
        if ($tool -eq 'AMDCleanupUtility') {
            Save-Result $true 'AMD Cleanup Utility est prêt sur le Bureau. Aucun nettoyage lancé : ouvre le raccourci uniquement lorsque tu souhaites retirer les pilotes graphiques/audio AMD.'
            exit 0
        }
        Save-Result $true "$($definition.Name) est installé, vérifié et disponible sur le Bureau."
        exit 0
    }

    if ($CustomAction -eq 'ScaledResolutionEditor') {
        $folder = Join-Path $portableRoot 'ScaledResolutionEditor'
        if ($Action -eq 'Uninstall') {
            Remove-ManagedFolder $folder
            Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) 'Scaled Resolution Editor.lnk') -Force -ErrorAction SilentlyContinue
            Save-Result $true 'Scaled Resolution Editor a été supprimé.'
            exit 0
        }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $target = Join-Path $folder 'SRE.exe'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Tools\ScaledResolutionEditor\SRE.exe') -Destination $target -Force
        New-DesktopShortcut 'Scaled Resolution Editor' $target
        Save-Result $true 'Scaled Resolution Editor est prêt.'
        exit 0
    }

    if ($CustomAction -eq 'RealAudioLatency') {
        $folder = Join-Path $toolsRoot 'REAL'
        $target = Join-Path $folder 'REAL.exe'
        $watchdog = Join-Path $folder 'BASTOS-REAL-Watchdog.ps1'
        $launcher = Join-Path $folder 'BASTOS-REAL-Launcher.vbs'
        $watchdogPid = Join-Path $folder 'watchdog.pid'
        $stopRequest = Join-Path $folder 'watchdog.stop'
        $startup = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
        $shortcutPath = Join-Path $startup 'BASTOS REAL Audio.lnk'
        if ($Action -eq 'Uninstall') {
            if (Test-Path -LiteralPath $folder -PathType Container) { New-Item -ItemType File -Path $stopRequest -Force | Out-Null }
            Get-Process -Name 'REAL' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $watchdogPid -PathType Leaf) {
                $watchdogProcessId = 0
                try { $watchdogProcessId = [int](Get-Content -LiteralPath $watchdogPid -Raw).Trim() } catch {}
                $deadline = (Get-Date).AddSeconds(5)
                while ($watchdogProcessId -gt 0 -and (Get-Process -Id $watchdogProcessId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
                Get-Process -Id $watchdogProcessId -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
            Save-Result $true 'REAL Audio a été arrêté et supprimé. Le démarrage automatique invisible a été retiré.'
            exit 0
        }
        if (Test-Path -LiteralPath $folder -PathType Container) { New-Item -ItemType File -Path $stopRequest -Force | Out-Null }
        Get-Process -Name 'REAL' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Invoke-WebRequest -Uri 'https://github.com/miniant-git/REAL/releases/download/updater-v2/REAL.exe' -OutFile ($target + '.download') -UseBasicParsing
        $hash = (Get-FileHash -LiteralPath ($target + '.download') -Algorithm SHA256).Hash
        if ($hash -ne 'D9767FD0E29A9FCDD274282DE81C82D7B8FB16F268FA2A7CEC50C01D0DD3C4AD') { throw 'Signature de contrôle REAL invalide.' }
        Move-Item -LiteralPath ($target + '.download') -Destination $target -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BASTOS-REAL-Watchdog.ps1') -Destination $watchdog -Force
        $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $launcherContent = @"
Option Explicit
Dim shell, command
Set shell = CreateObject("WScript.Shell")
command = Chr(34) & "$($powershell.Replace('"','""'))" & Chr(34) & " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & "$($watchdog.Replace('"','""'))" & Chr(34) & " -RealExecutable " & Chr(34) & "$($target.Replace('"','""'))" & Chr(34)
shell.Run command, 0, False
"@
        [IO.File]::WriteAllText($launcher,$launcherContent,[Text.UTF8Encoding]::new($false))
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
        $shortcut.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
        $shortcut.Arguments = '//B //NoLogo "{0}"' -f $launcher
        $shortcut.WorkingDirectory = $folder
        $shortcut.IconLocation = "$target,0"
        $shortcut.Description = 'REAL - latence audio active en arriere-plan via BASTOS'
        $shortcut.Save()
        Remove-Item -LiteralPath $stopRequest -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList @('//B','//NoLogo',$launcher) -WindowStyle Hidden | Out-Null
        $deadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 250
            $realRunning = @(Get-Process -Name 'REAL' -ErrorAction SilentlyContinue).Count -gt 0
            $watchdogRunning = Test-Path -LiteralPath $watchdogPid -PathType Leaf
        } while ((-not $realRunning -or -not $watchdogRunning) -and (Get-Date) -lt $deadline)
        if (-not $realRunning -or -not $watchdogRunning) { throw 'REAL ou son superviseur invisible ne reste pas actif.' }
        Save-Result $true 'REAL Audio est installé, actif en arrière-plan et démarrera silencieusement avec Windows. Pour le désactiver, désinstallez-le depuis Bastos.'
        exit 0
    }

    if ($CustomAction -eq 'VibranceGUI') {
        $folder = Join-Path $portableRoot 'VibranceGUI'
        $target = Join-Path $folder 'vibranceGUI.exe'
        if ($Action -eq 'Uninstall') {
            Get-Process -Name 'vibranceGUI' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Remove-ManagedFolder $folder
            Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) 'VibranceGUI.lnk') -Force -ErrorAction SilentlyContinue
            Save-Result $true 'VibranceGUI a été supprimé.'
            exit 0
        }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $archivePath = Join-Path $env:TEMP ("VibranceGUI-{0}.zip" -f [Guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri 'https://vibrancegui.com/vibrance/download' -OutFile $archivePath -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entry = @($archive.Entries | Where-Object { $_.Name -ieq 'vibranceGUI.exe' } | Select-Object -First 1)
            if ($entry.Count -ne 1) { throw 'Executable VibranceGUI introuvable dans l archive officielle.' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry[0], ($target + '.new'), $true)
        } finally { $archive.Dispose(); Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
        if ((Get-FileHash -LiteralPath ($target + '.new') -Algorithm SHA256).Hash -ne '1CBAA4D4C817743A7EC88BDC3F8D15200E543A86E0B3374C6D05A15A0762970F') { throw 'Signature de contrôle VibranceGUI invalide.' }
        Move-Item -LiteralPath ($target + '.new') -Destination $target -Force
        New-DesktopShortcut 'VibranceGUI' $target
        Save-Result $true 'VibranceGUI est installé et vérifié.'
        exit 0
    }

    throw "Action spéciale inconnue : $CustomAction"
} catch {
    Save-Result $false $_.Exception.Message
    exit 1
}
