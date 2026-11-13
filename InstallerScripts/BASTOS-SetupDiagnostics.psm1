Set-StrictMode -Version Latest

function Get-BastosDiagnosticContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StorageRoot,
        [switch]$Create
    )

    $storage = [IO.Path]::GetFullPath($StorageRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $storage -PathType Container)) {
        if (-not $Create) { return $null }
        New-Item -ItemType Directory -Path $storage -Force | Out-Null
    }

    $pointerPath = Join-Path $storage 'BASTOS-ACTIVE-ATTEMPT.txt'
    $attemptId = ''
    if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
        $attemptId = (Get-Content -LiteralPath $pointerPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if ($attemptId -notmatch '^Attempt-[0-9a-fA-F]{32}$') {
        if (-not $Create) { return $null }
        $attemptId = 'Attempt-' + [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText($pointerPath,$attemptId,[Text.Encoding]::ASCII)
    }

    $attemptRoot = Join-Path (Join-Path (Join-Path $storage 'BASTOS-Diagnostics') 'Attempts') $attemptId
    if ($Create) { New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $attemptRoot -PathType Container)) { return $null }

    [pscustomobject]@{
        AttemptId = $attemptId
        StorageRoot = $storage
        AttemptRoot = $attemptRoot
        StatePath = Join-Path $attemptRoot 'State.json'
        TimelinePath = Join-Path $attemptRoot 'Timeline.log'
    }
}

function Write-BastosDiagnosticEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARNING','ERROR')][string]$Level = 'INFO'
    )

    New-Item -ItemType Directory -Path $Context.AttemptRoot -Force | Out-Null
    $clean = $Message -replace "[\r\n\t]",' '
    $line = '{0} [{1}] [{2}] {3}' -f ([DateTime]::UtcNow.ToString('o')),$Level,$Component,$clean
    Add-Content -LiteralPath $Context.TimelinePath -Value $line -Encoding UTF8
    Add-Content -LiteralPath (Join-Path $Context.AttemptRoot ($Component + '.log')) -Value $line -Encoding UTF8
}

function Set-BastosDiagnosticState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Stage,
        [string]$Message = '',
        [Nullable[bool]]$Success = $null,
        [hashtable]$Extra = @{}
    )

    $state = [ordered]@{
        Schema = 1
        AttemptId = [string]$Context.AttemptId
        Stage = $Stage
        UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    if (Test-Path -LiteralPath $Context.StatePath -PathType Leaf) {
        try {
            $previous = Get-Content -LiteralPath $Context.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $previous.PSObject.Properties) { $state[$property.Name] = $property.Value }
        } catch {
            $state.PreviousStateReadError = $_.Exception.Message
        }
    }
    $state.Stage = $Stage
    $state.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    if ($Message) { $state.Message = $Message }
    if ($null -ne $Success) { $state.Success = [bool]$Success }
    foreach ($key in $Extra.Keys) { $state[$key] = $Extra[$key] }

    $temporary = $Context.StatePath + '.tmp'
    [IO.File]::WriteAllText($temporary,($state | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Context.StatePath -Force

    # Conserver aussi un pointeur lisible directement a la racine de
    # BASTOS_RECOVERY. Une panne de fin d installation reste ainsi visible sans
    # devoir deviner le dernier dossier Attempt-*.
    $lastAttemptPath = Join-Path $Context.StorageRoot 'BASTOS-LAST-ATTEMPT.json'
    [IO.File]::WriteAllText(($lastAttemptPath + '.tmp'),($state | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath ($lastAttemptPath + '.tmp') -Destination $lastAttemptPath -Force
    if ($null -ne $Success -and -not [bool]$Success) {
        $lastError = [ordered]@{
            Schema = 1
            AttemptId = [string]$Context.AttemptId
            Stage = $Stage
            Success = $false
            Message = $Message
            UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            AttemptStatePath = [string]$Context.StatePath
        }
        foreach ($key in $Extra.Keys) { $lastError[$key] = $Extra[$key] }
        $lastErrorPath = Join-Path $Context.StorageRoot 'BASTOS-LAST-ERROR.json'
        [IO.File]::WriteAllText(($lastErrorPath + '.tmp'),($lastError | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath ($lastErrorPath + '.tmp') -Destination $lastErrorPath -Force
    } elseif ($null -ne $Success -and [bool]$Success -and $Stage -eq 'Completed') {
        Copy-Item -LiteralPath $lastAttemptPath -Destination (Join-Path $Context.StorageRoot 'BASTOS-LAST-SUCCESS.json') -Force
        Remove-Item -LiteralPath (Join-Path $Context.StorageRoot 'BASTOS-LAST-ERROR.json') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $Context.StorageRoot 'BASTOS-LAST-ERROR.txt') -Force -ErrorAction SilentlyContinue
    }
}

function Copy-BastosSetupDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [string]$WindowsRoot = $env:SystemRoot,
        [string]$SnapshotName = 'Latest'
    )

    if (-not $WindowsRoot -or -not (Test-Path -LiteralPath $WindowsRoot -PathType Container)) { return }
    $destination = Join-Path (Join-Path $Context.AttemptRoot 'Windows-Setup') $SnapshotName
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $files = @(
        'Panther\setupact.log','Panther\setuperr.log','Panther\diagerr.xml','Panther\diagwrn.xml',
        'Panther\cbs_unattend.log','Panther\cbs.log','Panther\cbs_intl.log',
        'Panther\UnattendGC\setupact.log','Panther\UnattendGC\setuperr.log',
        'Panther\UnattendGC\diagerr.xml','Panther\UnattendGC\diagwrn.xml',
        'INF\setupapi.dev.log','INF\setupapi.app.log','INF\setupapi.offline.log',
        'Logs\CBS\CBS.log'
    )
    foreach ($relative in $files) {
        $source = Join-Path $WindowsRoot $relative
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $safeName = $relative.Replace('\','--')
            try { Copy-Item -LiteralPath $source -Destination (Join-Path $destination $safeName) -Force -ErrorAction Stop } catch {}
        }
    }

    $wevtutil = Join-Path $WindowsRoot 'System32\wevtutil.exe'
    if (Test-Path -LiteralPath $wevtutil -PathType Leaf) {
        try { & $wevtutil epl Setup (Join-Path $destination 'Setup.evtx') /ow:true 2>$null | Out-Null } catch {}
    }
}

Export-ModuleMember -Function Get-BastosDiagnosticContext,Write-BastosDiagnosticEvent,Set-BastosDiagnosticState,Copy-BastosSetupDiagnostics
