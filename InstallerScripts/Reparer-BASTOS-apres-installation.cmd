@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-BASTOS-First-Run.ps1"
set "BASTOS_EXIT=%ERRORLEVEL%"
echo.
if not "%BASTOS_EXIT%"=="0" echo La reparation BASTOS a echoue avec le code %BASTOS_EXIT%.
pause
exit /b %BASTOS_EXIT%
