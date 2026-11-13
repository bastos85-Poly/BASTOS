[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$OfficialUrl,
    [string]$ResolutionStrategy = '',
    [string]$SearchTerm = '',
    [Parameter(Mandatory)][string]$ResultPath,
    [string]$OperationId = '',
    [string]$ProgressPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bastos.Operation.psm1') -Force

try {
    Write-BastosOperationProgress -ProgressPath $ProgressPath -Percent 10 -Phase 'Validation du lien' -Message 'Verification du domaine officiel...'
    $modulePath = Join-Path $PSScriptRoot 'Driver-Recommendation-Service.psm1'
    $configPath = Join-Path $PSScriptRoot 'Official-Sources.json'
    Import-Module $modulePath -Force -ErrorAction Stop
    $config = Get-BastosOfficialConfig -Path $configPath
    if (-not (Test-BastosOfficialUrl -Url $OfficialUrl -Config $config)) {
        throw 'Ce domaine ne figure pas dans la liste blanche officielle BASTOS.'
    }
    $recommendation = [pscustomobject]@{
        OfficialUrl = $OfficialUrl
        ResolutionStrategy = $ResolutionStrategy
    }
    $resolved = Resolve-BastosOfficialDownloadUrl -Recommendation $recommendation -Config $config -TimeoutSeconds 8
    $finalUrl = [string]$resolved.FinalUrl
    if (-not (Test-BastosOfficialUrl -Url $finalUrl -Config $config)) {
        throw 'Le lien final ne figure pas dans la liste blanche officielle BASTOS.'
    }
    if ($SearchTerm) {
        try { Set-Clipboard -Value $SearchTerm -ErrorAction Stop } catch { }
    }
    Start-Process -FilePath $finalUrl
    Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $true -Message "Demande d'ouverture transmise au navigateur. $($resolved.Status)" -Data @{ Url=$finalUrl; RequestedUrl=$OfficialUrl; LaunchRequested=$true; ResolutionStrategy=$ResolutionStrategy }
    exit 0
} catch {
    try { Write-BastosOperationReport -ResultPath $ResultPath -OperationId $OperationId -Success $false -Message $_.Exception.Message } catch { }
    exit 1
}
