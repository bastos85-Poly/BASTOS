[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('Install','Uninstall')][string]$Action,
 [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference='Stop'
try {
 Import-Module (Join-Path $PSScriptRoot 'BASTOS-RAMMap.psm1') -Force
 $message=Invoke-BastosRamMap -Action $Action
 $result=@{Success=$true;Message=$message}
} catch { $result=@{Success=$false;Message=$_.Exception.Message} }
$parent=Split-Path -Parent $ResultPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
if (-not $result.Success) { exit 1 }
