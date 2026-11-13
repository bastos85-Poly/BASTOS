@echo off
setlocal EnableExtensions
set "BASTOS_OOBE_ROOT=%ProgramData%\BASTOS-ISO"
if not exist "%BASTOS_OOBE_ROOT%\Logs" md "%BASTOS_OOBE_ROOT%\Logs" >nul 2>&1
set "BASTOS_SETUP_LOG=%BASTOS_OOBE_ROOT%\Logs\SetupComplete.log"
if exist "%BASTOS_OOBE_ROOT%\BASTOS-AccountFlow.txt" (
  find "RufusLocal" "%BASTOS_OOBE_ROOT%\BASTOS-AccountFlow.txt" >nul 2>&1
  if not errorlevel 1 (
    goto :VERIFY_RUFUS_LOCAL
  )
)

>"%BASTOS_SETUP_LOG%" echo [%DATE% %TIME%] Validation preconnexion du compte local BastOS.
if not exist "%BASTOS_OOBE_ROOT%\Initialize-BASTOS-PreLogon.ps1" (
  >>"%BASTOS_SETUP_LOG%" echo ECHEC : Initialize-BASTOS-PreLogon.ps1 absent.
  exit /b 31
)
if not exist "%BASTOS_OOBE_ROOT%\BASTOS-LocalAccount.txt" (
  >>"%BASTOS_SETUP_LOG%" echo ECHEC : marqueur BASTOS-LocalAccount.txt absent.
  exit /b 32
)
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%BASTOS_OOBE_ROOT%\Initialize-BASTOS-PreLogon.ps1" -AccountMarkerPath "%BASTOS_OOBE_ROOT%\BASTOS-LocalAccount.txt" -LogPath "%BASTOS_OOBE_ROOT%\Logs\PreLogon.log" >>"%BASTOS_SETUP_LOG%" 2>&1
set "BASTOS_PRELOGON_EXIT=%ERRORLEVEL%"
if not "%BASTOS_PRELOGON_EXIT%"=="0" (
  >>"%BASTOS_SETUP_LOG%" echo ECHEC : validation preconnexion retour %BASTOS_PRELOGON_EXIT%. AutoLogon a ete neutralise.
  exit /b %BASTOS_PRELOGON_EXIT%
)
>>"%BASTOS_SETUP_LOG%" echo [%DATE% %TIME%] SUCCES : BastOS local sans mot de passe verifie; SID-500 desactive; domaine local reel configure.
if exist "%BASTOS_OOBE_ROOT%\BASTOS-LocalOnly-OOBE.cmd" >>"%BASTOS_SETUP_LOG%" echo Filet manuel OOBE ms-cxh:localonly present.
exit /b 0

:VERIFY_RUFUS_LOCAL
>>"%BASTOS_SETUP_LOG%" echo [%DATE% %TIME%] Verification du compte cree en specialize.
if not exist "%BASTOS_OOBE_ROOT%\Initialize-BASTOS-LocalAccount.ps1" (
  >>"%BASTOS_SETUP_LOG%" echo ECHEC : verification du compte absente.
  exit /b 33
)
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%BASTOS_OOBE_ROOT%\Initialize-BASTOS-LocalAccount.ps1" -VerifyOnly >>"%BASTOS_SETUP_LOG%" 2>&1
set "BASTOS_ACCOUNT_EXIT=%ERRORLEVEL%"
>>"%BASTOS_SETUP_LOG%" echo Verification du compte : retour %BASTOS_ACCOUNT_EXIT%.
exit /b %BASTOS_ACCOUNT_EXIT%
