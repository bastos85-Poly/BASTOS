$ErrorActionPreference = 'Stop'
function Test-BastosWinREEnabled([string]$Info) {
    $Info -match '(?im)^\s*[^\r\n]*(?:Windows\s*RE|WinRE)[^\r\n]*:\s*(?:Enabled|Activé|Active)\s*$'
}
$log = 'C:\ProgramData\BASTOS-ISO\Logs\Integrate-WinRE.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null
$oldLocation = $null
$recoveryChanged = $false
try {
    $volumes = @(Get-Volume -FileSystemLabel 'BASTOS_RECOVERY' -ErrorAction Stop)
    if ($volumes.Count -ne 1) { throw 'Une unique partition BASTOS_RECOVERY est requise.' }
    $partition = $volumes[0] | Get-Partition
    $letter = [string]$partition.DriveLetter
    if (-not $letter) { throw 'La partition BASTOS_RECOVERY doit etre montee avant cette integration.' }
    $target = "${letter}:\Recovery\WindowsRE"
    $destination = Join-Path $target 'Winre.wim'

    $oldInfo = (& reagentc.exe /info | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Lecture de la configuration WinRE impossible.' }
    $locationMatch = [regex]::Match($oldInfo, '\\\\\?\\GLOBALROOT\\device\\harddisk\d+\\partition\d+\\Recovery\\WindowsRE', 'IgnoreCase')
    if ($locationMatch.Success) { $oldLocation = $locationMatch.Value }
    $expectedLocation = "harddisk$($partition.DiskNumber)\partition$($partition.PartitionNumber)\Recovery\WindowsRE"
    if ((Test-BastosWinREEnabled $oldInfo) -and $oldLocation -like "*$expectedLocation" -and
        (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) OK WinRE deja integre sur $target"
        return
    }
    $source = 'C:\Windows\System32\Recovery\Winre.wim'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        if (-not $oldLocation) { throw 'Emplacement de l image WinRE introuvable dans reagentc /info.' }
        $source = Join-Path $oldLocation 'Winre.wim'
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Image WinRE introuvable : $source" }
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    # Get-Item and Copy-Item cannot open a GLOBALROOT file even when Test-Path
    # and Get-FileHash can. The .NET file APIs support this device path.
    $imageSize = ([IO.FileInfo]::new($source)).Length
    if ($volumes[0].SizeRemaining -lt ($imageSize + 100MB)) { throw 'Espace libre insuffisant sur BASTOS_RECOVERY.' }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    [IO.File]::Copy($source, $destination, $true)
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'La copie de Winre.wim ne correspond pas a la source.'
    }

    & reagentc.exe /disable | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAgentC /disable a echoue.' }
    $recoveryChanged = $true
    & reagentc.exe /setreimage /path $target /target C:\Windows | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAgentC /setreimage a echoue.' }
    & reagentc.exe /enable | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAgentC /enable a echoue.' }
    $newInfo = (& reagentc.exe /info | Out-String)
    if ($LASTEXITCODE -ne 0 -or -not (Test-BastosWinREEnabled $newInfo)) {
        throw 'WinRE n est pas confirme actif apres integration.'
    }
    if ($newInfo -notlike "*$expectedLocation*") { throw "WinRE actif, mais emplacement inattendu : $newInfo" }
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) OK WinRE=$target TailleImage=$imageSize SHA256=$sourceHash"
} catch {
    $failure = $_.Exception.Message
    if ($recoveryChanged -and $oldLocation) {
        try {
            & reagentc.exe /disable | Out-Null
            & reagentc.exe /setreimage /path $oldLocation /target C:\Windows | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'setreimage de restauration a echoue.' }
            & reagentc.exe /enable | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'enable de restauration a echoue.' }
            Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) Restauration WinRE=$oldLocation"
        } catch {
            Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) ERREUR restauration WinRE $($_.Exception.Message)"
        }
    }
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) ERREUR $failure"
    throw
}
