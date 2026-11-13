[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('DiscordBelowNormal','DiscordRestore','WindowsDriversBlock','WindowsDriversRestore','RebootFirmware','RebootAdvancedStartup','SfcVerify')]
    [string]$Operation,
    [string]$BackupPath,
    [string]$LiveOutputPath,
    [string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Cette operation protegee doit etre executee avec elevation UAC.'
}

$discordPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Discord.exe\PerfOptions'
$windowsUpdatePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

function Test-BastosUefiFirmware {
    try {
        $firmware = (Get-ComputerInfo -Property BiosFirmwareType -ErrorAction Stop).BiosFirmwareType
        if ([string]$firmware -match '^(?i:Uefi)$') { return $true }
        if ([string]$firmware -match '(?i:Bios|Legacy)') { return $false }
    } catch {}

    try {
        $null = & bcdedit.exe /enum '{fwbootmgr}' 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

switch ($Operation) {
    'DiscordBelowNormal' {
        if (-not (Test-Path -LiteralPath $discordPath)) { New-Item -Path $discordPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $discordPath -Name CpuPriorityClass -PropertyType DWord -Value 5 -Force | Out-Null
    }
    'DiscordRestore' {
        $restored = $false
        if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
            $backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
            if ([bool]$backup.Exists) {
                if (-not (Test-Path -LiteralPath $discordPath)) { New-Item -Path $discordPath -Force | Out-Null }
                New-ItemProperty -LiteralPath $discordPath -Name CpuPriorityClass -PropertyType DWord -Value ([int]$backup.Value) -Force | Out-Null
                $restored = $true
            }
        }
        if (-not $restored -and (Test-Path -LiteralPath $discordPath)) {
            Remove-ItemProperty -LiteralPath $discordPath -Name CpuPriorityClass -ErrorAction SilentlyContinue
        }
    }
    'WindowsDriversBlock' {
        if (-not (Test-Path -LiteralPath $windowsUpdatePath)) { New-Item -Path $windowsUpdatePath -Force | Out-Null }
        New-ItemProperty -LiteralPath $windowsUpdatePath -Name ExcludeWUDriversInQualityUpdate -PropertyType DWord -Value 1 -Force | Out-Null
    }
    'WindowsDriversRestore' {
        if (Test-Path -LiteralPath $windowsUpdatePath) {
            Remove-ItemProperty -LiteralPath $windowsUpdatePath -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
        }
    }
    'RebootFirmware' {
        if (-not (Test-BastosUefiFirmware)) {
            throw 'Ce PC ne permet pas a Windows de redemarrer automatiquement dans le BIOS ou UEFI. Redemarre manuellement et utilise la touche indiquee par le constructeur.'
        }
        $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        if (-not (Test-Path -LiteralPath $shutdown -PathType Leaf)) {
            throw 'La commande de redemarrage Windows est introuvable.'
        }
        & $shutdown /r /fw /f /t 0
        $shutdownCode = $LASTEXITCODE
        if ($shutdownCode -ne 0) {
            throw "Windows a refuse le redemarrage automatique vers le BIOS ou UEFI (code $shutdownCode)."
        }
    }
    'RebootAdvancedStartup' {
        $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        if (-not (Test-Path -LiteralPath $shutdown -PathType Leaf)) {
            throw 'La commande de redemarrage Windows est introuvable.'
        }
        & $shutdown /r /o /f /t 0
        $shutdownCode = $LASTEXITCODE
        if ($shutdownCode -ne 0) {
            throw "Windows a refuse le redemarrage vers les options de demarrage avancees (code $shutdownCode)."
        }
    }
    'SfcVerify' {
        if (-not $LiveOutputPath -or -not [IO.Path]::IsPathRooted($LiveOutputPath)) {
            throw 'Le chemin de sortie directe SFC est invalide.'
        }
        if (-not $ResultPath -or -not [IO.Path]::IsPathRooted($ResultPath)) {
            throw 'Le chemin de resultat SFC est invalide.'
        }
        foreach($path in @($LiveOutputPath,$ResultPath)){
            if($path -match '["\r\n]'){throw 'Un chemin SFC non sûr a ete refuse.'}
            $parent=Split-Path -Parent $path
            if($parent -and -not(Test-Path -LiteralPath $parent)){
                New-Item -ItemType Directory -Path $parent -Force|Out-Null
            }
        }

        $sfcPath=Join-Path $env:SystemRoot 'System32\sfc.exe'
        if(-not(Test-Path -LiteralPath $sfcPath -PathType Leaf)){throw 'sfc.exe est introuvable.'}
        $start=Get-Date
        $writer=[IO.StreamWriter]::new(
            $LiveOutputPath,$false,[Text.UTF8Encoding]::new($false),4096)
        $process=$null
        try{
            $writer.AutoFlush=$true
            $writer.WriteLine('BASTOS > sfc.exe /verifyonly')
            $writer.WriteLine('Verification des fichiers systeme proteges - sortie PowerShell en direct')
            $writer.WriteLine('')

            $psi=[Diagnostics.ProcessStartInfo]::new()
            $psi.FileName=$sfcPath
            $psi.Arguments='/verifyonly'
            $psi.UseShellExecute=$false
            $psi.CreateNoWindow=$true
            $psi.RedirectStandardOutput=$true
            $psi.RedirectStandardError=$true
            $oemCodePage=[Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            $psi.StandardOutputEncoding=[Text.Encoding]::GetEncoding($oemCodePage)
            $psi.StandardErrorEncoding=[Text.Encoding]::GetEncoding($oemCodePage)
            $process=[Diagnostics.Process]::new()
            $process.StartInfo=$psi
            if(-not $process.Start()){throw 'Windows n a pas pu lancer SFC.'}
            $errorTask=$process.StandardError.ReadToEndAsync()
            $buffer=New-Object char[] 2048
            while(($count=$process.StandardOutput.Read($buffer,0,$buffer.Length)) -gt 0){
                $writer.Write($buffer,0,$count)
                $writer.Flush()
            }
            $process.WaitForExit()
            $errorText=$errorTask.Result
            if($errorText){$writer.WriteLine();$writer.Write($errorText)}
            $exitCode=$process.ExitCode
            $writer.WriteLine()
            $writer.WriteLine('')
            $writer.WriteLine("BASTOS > SFC termine avec le code $exitCode.")
        }finally{
            if($process){$process.Dispose()}
            $writer.Dispose()
        }
        $result=[ordered]@{
            Success=($exitCode -eq 0)
            ExitCode=$exitCode
            StartedUtc=$start.ToUniversalTime().ToString('o')
            FinishedUtc=[datetime]::UtcNow.ToString('o')
            LiveOutputPath=$LiveOutputPath
        }
        [IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        exit $exitCode
    }
}

exit 0
