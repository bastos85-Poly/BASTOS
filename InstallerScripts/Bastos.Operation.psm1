Set-StrictMode -Version Latest

function Write-BastosOperationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResultPath,
        [string]$OperationId = '',
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][string]$Message,
        [System.Collections.IDictionary]$Data = @{}
    )
    $payload = [ordered]@{}
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $payload['SchemaVersion'] = 1
    $payload['OperationId'] = $OperationId
    $payload['Success'] = $Success
    $payload['Message'] = $Message
    Write-BastosJsonFile -Path $ResultPath -Data $payload
}
function Write-BastosAtomicText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $full=[IO.Path]::GetFullPath($Path)
    $parent=[IO.Path]::GetDirectoryName($full)
    if($parent){[IO.Directory]::CreateDirectory($parent)|Out-Null}
    $temporary=$full+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $backup=$temporary+'.bak'
    try {
        [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new($false))
        for($attempt=0;$attempt -lt 50;$attempt++){
            try {
                if([IO.File]::Exists($full)){[IO.File]::Replace($temporary,$full,$backup)}else{[IO.File]::Move($temporary,$full)}
                return
            } catch [IO.IOException] {
                if($attempt -eq 49){throw}
                Start-Sleep -Milliseconds 10
            }
        }
    } finally {
        if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}
        if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
    }
}
function Write-BastosJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object]$Data,[ValidateRange(1,50)][int]$Depth=20)
    $json=if($null -eq $Data){'null'}else{ConvertTo-Json -InputObject $Data -Depth $Depth -Compress -ErrorAction Stop}
    Write-BastosAtomicText -Path $Path -Text $json
}
function Get-BastosFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    }
    finally { if($stream){$stream.Dispose()}; $algorithm.Dispose() }
}
function Write-BastosOperationProgress {
    param([string]$ProgressPath, [ValidateRange(0,100)][int]$Percent, [string]$Phase, [string]$Message,
        [ValidateRange(0,1000)][int]$Step=0,[ValidateRange(0,1000)][int]$TotalSteps=0)
    if (-not $ProgressPath) { return }
    if($TotalSteps -gt 0 -and $Step -gt $TotalSteps){throw 'Progression incoherente : etape superieure au total.'}
    $line = "$Percent`t$($Phase -replace "[`r`n`t]", ' ')`t$($Message -replace "[`r`n`t]", ' ')"
    # Legacy readers expect three fields; step-aware workers explicitly opt in to five.
    if($PSBoundParameters.ContainsKey('Step') -or $PSBoundParameters.ContainsKey('TotalSteps')){$line+="`t$Step`t$TotalSteps"}
    Write-BastosAtomicText -Path $ProgressPath -Text $line
}
Export-ModuleMember -Function Write-BastosOperationReport,Get-BastosFileSha256,Write-BastosOperationProgress,Write-BastosAtomicText,Write-BastosJsonFile
