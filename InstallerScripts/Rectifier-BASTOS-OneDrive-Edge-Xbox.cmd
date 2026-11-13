@echo off
setlocal
cd /d "%~dp0"
echo BASTOS va demander une seule autorisation Windows pour Edge, OneDrive et les composants machine.
echo Accepte Oui dans la fenetre UAC pour terminer la rectification.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-BASTOS-Applications.ps1"
echo.
if errorlevel 1 (
  echo La rectification n'a pas pu se terminer. Consulte le message ci-dessus.
) else (
  echo Rectification terminee et verifiee.
)
pause
endlocal
