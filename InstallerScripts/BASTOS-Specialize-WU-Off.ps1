$ErrorActionPreference = 'Continue'
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = Join-Path $wu 'AU'
New-Item -Path $au -Force | Out-Null
New-ItemProperty -Path $wu -Name DoNotConnectToWindowsUpdateInternetLocations -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $au -Name NoAutoUpdate -PropertyType DWord -Value 1 -Force | Out-Null
Stop-Service wuauserv,UsoSvc -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -Name Start -Value 4 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc' -Name Start -Value 4 -ErrorAction SilentlyContinue
exit 0