Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-BastosRemoteConsent {
    param([bool]$Consent)
    return $Consent
}

function Get-BastosQuickAssistStatus {
    param([AllowNull()][array]$StartAppsOverride)
    $apps = @()
    if ($null -ne $StartAppsOverride) {
        $apps = @($StartAppsOverride)
    } else {
        try { $apps = @(Get-StartApps -ErrorAction Stop) } catch { $apps = @() }
    }
    $entry = $apps | Where-Object {
        ([string]$_.Name -match '(?i)Quick Assist|Assistance rapide') -or
        ([string]$_.AppID -match '(?i)QuickAssist|MicrosoftCorporationII\.QuickAssist')
    } | Select-Object -First 1
    $legacy = Get-Command 'quickassist.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $packagePresent = $false
    if ($null -eq $StartAppsOverride) {
        try { $packagePresent = $null -ne (Get-AppxPackage -Name 'MicrosoftCorporationII.QuickAssist' -ErrorAction Stop | Select-Object -First 1) } catch {}
    }
    $processes = @(Get-Process -Name 'QuickAssist','QuickAssistUI' -ErrorAction SilentlyContinue | Sort-Object Id -Unique)
    return [pscustomobject]@{
        Available = [bool]($entry -or $legacy -or $packagePresent)
        AppId = $(if ($entry) { [string]$entry.AppID } else { '' })
        LegacyPath = $(if ($legacy) { [string]$legacy.Source } else { '' })
        PackagePresent = $packagePresent
        Running = $processes.Count -gt 0
        ProcessCount = $processes.Count
        Status = $(if ($processes.Count -gt 0) { 'Lancee' } elseif ($entry -or $legacy -or $packagePresent) { 'Disponible' } else { 'Absente' })
    }
}

function Start-BastosQuickAssist {
    param([Parameter(Mandatory)][bool]$Consent)
    if (-not (Test-BastosRemoteConsent -Consent $Consent)) { throw 'Le consentement explicite est obligatoire avant le lancement.' }
    $status = Get-BastosQuickAssistStatus
    if (-not $status.Available) { return [pscustomobject]@{ Success=$false; Message='Assistance rapide n est pas installee.' } }
    if ($status.AppId) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\" + $status.AppId)
    } elseif ($status.LegacyPath) {
        Start-Process -FilePath $status.LegacyPath
    } else {
        # Le package Store est present mais son raccourci n a pas ete retourne.
        Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:AppsFolder\MicrosoftCorporationII.QuickAssist_8wekyb3d8bbwe!App'
    }
    return [pscustomobject]@{ Success=$true; Message='Assistance rapide a ete lancee. Les confirmations Microsoft restent obligatoires.' }
}

function Open-BastosQuickAssistStore {
    # Recherche dans le Microsoft Store : aucun telechargement ou installation silencieuse.
    Start-Process 'ms-windows-store://search/?query=Quick%20Assist'
    return $true
}

function Stop-BastosQuickAssist {
    $processes = @(Get-Process -Name 'QuickAssist','QuickAssistUI' -ErrorAction SilentlyContinue | Sort-Object Id -Unique)
    if ($processes.Count -eq 0) { return [pscustomobject]@{ Success=$true; Closed=0; Message='Assistance rapide est deja fermee.' } }
    $closed = 0
    foreach ($process in $processes) {
        try {
            if ($process.CloseMainWindow()) { $closed++ }
        } catch {}
    }
    return [pscustomobject]@{
        Success=$closed -gt 0
        Closed=$closed
        Message=$(if($closed -gt 0){'Demande de fermeture envoyee. Verifier que la fenetre est fermee.'}else{'Fermer Assistance rapide depuis sa propre fenetre pour terminer la session.'})
    }
}

function New-BastosQuickAssistProvider {
    $provider = [pscustomobject]@{
        ProviderName='Assistance rapide Microsoft'
        SupportsUnattendedAccess=$false
        StoresPermanentPassword=$false
    }
    $provider | Add-Member ScriptMethod IsAvailable { (Get-BastosQuickAssistStatus).Available }
    $provider | Add-Member ScriptMethod InstallOrDownload { Open-BastosQuickAssistStore }
    $provider | Add-Member ScriptMethod Launch { param([bool]$Consent) Start-BastosQuickAssist -Consent $Consent }
    $provider | Add-Member ScriptMethod EndSession { Stop-BastosQuickAssist }
    $provider | Add-Member ScriptMethod GetStatus { Get-BastosQuickAssistStatus }
    return $provider
}

# Point d extension futur. Aucun binaire RustDesk n est telecharge dans cette version.
function New-BastosRustDeskProviderPlaceholder {
    return [pscustomobject]@{
        ProviderName='RustDesk (non configure)'
        Available=$false
        Status='Fournisseur reserve pour une version future avec source officielle et verification Authenticode.'
        SupportsUnattendedAccess=$false
        StoresPermanentPassword=$false
    }
}

Export-ModuleMember -Function Test-BastosRemoteConsent,Get-BastosQuickAssistStatus,Start-BastosQuickAssist,Open-BastosQuickAssistStore,Stop-BastosQuickAssist,New-BastosQuickAssistProvider,New-BastosRustDeskProviderPlaceholder
