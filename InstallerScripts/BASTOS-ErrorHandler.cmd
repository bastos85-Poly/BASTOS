@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Ce gestionnaire est appele uniquement par Windows Setup apres une erreur
rem fatale. Il ne modifie aucun etat Setup, ne lance aucune optimisation et ne
rem redemarre jamais la machine. Son seul role est de sauver les diagnostics.
set "BASTOS_RECOVERY="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if not defined BASTOS_RECOVERY if exist "%%D:\BASTOS-ISO.sha256" if exist "%%D:\BASTOS-RECOVERY-PARTITION.txt" set "BASTOS_RECOVERY=%%D:"
if not defined BASTOS_RECOVERY exit /b 0

set "BASTOS_ATTEMPT=Unknown-OOBE-Failure"
if exist "%BASTOS_RECOVERY%\BASTOS-ACTIVE-ATTEMPT.txt" set /p BASTOS_ATTEMPT=<"%BASTOS_RECOVERY%\BASTOS-ACTIVE-ATTEMPT.txt"
if /i not "%BASTOS_ATTEMPT:~0,8%"=="Attempt-" set "BASTOS_ATTEMPT=Unknown-OOBE-Failure"
set "BASTOS_DEST=%BASTOS_RECOVERY%\BASTOS-Diagnostics\Attempts\%BASTOS_ATTEMPT%\Windows-Setup\OOBE-Fatal"
if not exist "%BASTOS_DEST%" md "%BASTOS_DEST%" >nul 2>&1

>"%BASTOS_DEST%\ErrorHandler.log" echo %DATE% %TIME% Windows Setup a appele BASTOS-ErrorHandler.cmd.
>>"%BASTOS_DEST%\ErrorHandler.log" echo Windows=%WINDIR% Recovery=%BASTOS_RECOVERY% Attempt=%BASTOS_ATTEMPT%
>"%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" echo AttemptId=%BASTOS_ATTEMPT%
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" echo Stage=WindowsSetupOOBEFatal
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" echo Result=FAILED
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" echo Timestamp=%DATE% %TIME%
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" echo Diagnostic=%BASTOS_DEST%
>"%BASTOS_RECOVERY%\BASTOS-LAST-ATTEMPT.txt" echo AttemptId=%BASTOS_ATTEMPT%
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ATTEMPT.txt" echo Stage=WindowsSetupOOBEFatal
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ATTEMPT.txt" echo Result=FAILED
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ATTEMPT.txt" echo Timestamp=%DATE% %TIME%
>>"%BASTOS_RECOVERY%\BASTOS-LAST-ATTEMPT.txt" echo Diagnostic=%BASTOS_DEST%
copy /y "%BASTOS_RECOVERY%\BASTOS-LAST-ERROR.txt" "%BASTOS_DEST%\Last-Error.txt" >nul 2>&1

if exist "%WINDIR%\Panther" robocopy "%WINDIR%\Panther" "%BASTOS_DEST%\Panther" /E /R:1 /W:1 /XJ /NP /NFL /NDL /XF unattend.xml autounattend.xml >>"%BASTOS_DEST%\ErrorHandler.log" 2>&1
if exist "%WINDIR%\System32\Sysprep\Panther" robocopy "%WINDIR%\System32\Sysprep\Panther" "%BASTOS_DEST%\Sysprep-Panther" /E /R:1 /W:1 /XJ /NP /NFL /NDL /XF unattend.xml autounattend.xml >>"%BASTOS_DEST%\ErrorHandler.log" 2>&1
if exist "%SystemDrive%\$WINDOWS.~BT\Sources\Panther" robocopy "%SystemDrive%\$WINDOWS.~BT\Sources\Panther" "%BASTOS_DEST%\Setup-Panther" /E /R:1 /W:1 /XJ /NP /NFL /NDL /XF unattend.xml autounattend.xml >>"%BASTOS_DEST%\ErrorHandler.log" 2>&1
if exist "%WINDIR%\INF\setupapi.dev.log" copy /y "%WINDIR%\INF\setupapi.dev.log" "%BASTOS_DEST%\setupapi.dev.log" >nul 2>&1

reg query HKLM\SYSTEM\Setup /s >"%BASTOS_DEST%\Setup-Registry.txt" 2>&1
wevtutil epl System "%BASTOS_DEST%\System.evtx" /ow:true >nul 2>&1
wevtutil epl Application "%BASTOS_DEST%\Application.evtx" /ow:true >nul 2>&1
>>"%BASTOS_DEST%\ErrorHandler.log" echo %DATE% %TIME% Capture terminee; Windows Setup reste seul responsable de la suite.
exit /b 0
