@echo off
setlocal EnableExtensions EnableDelayedExpansion

>X:\BASTOS-Start-Early.log echo BASTOS-Start.cmd entre dans WinPE le %DATE% a %TIME%.

rem BASTOS OneClick launcher v16-SpecializeAware-BastOS.
rem Le numero du disque est volontairement redetecte dans WinPE a partir de
rem son identite GPT. Aucune lettre (C:, D:) et aucun numero Windows n est cru.
wpeinit
>>X:\BASTOS-Start-Early.log echo Wpeinit termine avec le code %ERRORLEVEL%.
set "BASTOS_EXIT_CODE=1"
set "BASTOS_MEDIA="
set "BASTOS_IMAGE="
set "BASTOS_VOLUME="
set "BASTOS_MEDIA_COUNT=0"
set "BASTOS_TARGET_DISK="
set "BASTOS_DESTRUCTIVE_STARTED=0"
set "BASTOS_DIAG="
set "BASTOS_ATTEMPT_ID="
set "BASTOS_DIAGNOSTIC_ONLY=0"
set "BASTOS_BOOT_MODE="
set "BASTOS_BOOT_MODE_ID="
set "BASTOS_PRECHECKS_COMPLETED=0"
set "BASTOS_DISK_PREPARED=0"
set "BASTOS_SETUP_LAUNCHED=0"

rem La sonde native enumere les volumes par leur GUID, meme lorsque WinPE n a
rem attribue aucune lettre a BASTOS_RECOVERY. Elle lui affecte alors une lettre
rem temporaire libre avant que le script ne commence ses controles.
if exist "%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe" (
  for /f "delims=" %%D in ('"%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe" --find-recovery-volume 2^>X:\BASTOS-probe-volume.log') do if not defined BASTOS_MEDIA set "BASTOS_MEDIA=%%D"
  if defined BASTOS_MEDIA set "BASTOS_MEDIA_COUNT=1"
)

for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if not defined BASTOS_MEDIA if exist "%%D:\BASTOS-ISO.sha256" (
  set /a BASTOS_MEDIA_COUNT+=1
  set "BASTOS_MEDIA=%%D:"
)

rem Ne jamais analyser les colonnes localisees ou tronquees de "list volume".
rem Si WinPE n a attribue aucune lettre a Recovery, essayer chaque volume avec
rem une lettre temporaire libre et reconnaitre le marqueur BASTOS exact.
if not defined BASTOS_MEDIA (
  set "BASTOS_TEMP_LETTER="
  for %%D in (Z Y W V U T S R Q P O N M L K J I H G F E D C) do if not exist "%%D:\" if not defined BASTOS_TEMP_LETTER set "BASTOS_TEMP_LETTER=%%D"
  if defined BASTOS_TEMP_LETTER for /L %%V in (0,1,63) do if !BASTOS_MEDIA_COUNT! equ 0 (
    >X:\BASTOS-assign.txt echo select volume %%V
    >>X:\BASTOS-assign.txt echo assign letter=!BASTOS_TEMP_LETTER! noerr
    diskpart /s X:\BASTOS-assign.txt>X:\BASTOS-diskpart.log 2>&1
    if exist "!BASTOS_TEMP_LETTER!:\BASTOS-ISO.sha256" (
      set "BASTOS_MEDIA=!BASTOS_TEMP_LETTER!:"
      set "BASTOS_VOLUME=%%V"
      set /a BASTOS_MEDIA_COUNT=1
    ) else (
      >X:\BASTOS-remove-letter.txt echo select volume %%V
      >>X:\BASTOS-remove-letter.txt echo remove letter=!BASTOS_TEMP_LETTER! noerr
      diskpart /s X:\BASTOS-remove-letter.txt>X:\BASTOS-remove-letter.log 2>&1
    )
  )
)

if not "%BASTOS_MEDIA_COUNT%"=="1" (
  echo BASTOS_RECOVERY introuvable.>X:\BASTOS-Recovery.log
  echo Nombre de medias avec marqueur BASTOS : %BASTOS_MEDIA_COUNT%.>>X:\BASTOS-Recovery.log
  if exist X:\BASTOS-probe-volume.log type X:\BASTOS-probe-volume.log>>X:\BASTOS-Recovery.log
  echo Arret sans modifier les disques.>>X:\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=2"
  goto SAFE_REBOOT
)
vol %BASTOS_MEDIA%>X:\BASTOS-volume-label.txt 2>&1
find /i "BASTOS_RECOVERY" X:\BASTOS-volume-label.txt >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : le marqueur existe mais l etiquette du volume n est pas BASTOS_RECOVERY.>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=23"
  goto SAFE_REBOOT
)

>>X:\BASTOS-Start-Early.log echo Recovery detectee sur %BASTOS_MEDIA%.
type X:\BASTOS-Start-Early.log >"%BASTOS_MEDIA%\BASTOS-Recovery-Boot.log" 2>nul
if exist "%BASTOS_MEDIA%\BASTOS-Recovery.log" (
  set "BASTOS_PREVIOUS_BOOT=%BASTOS_MEDIA%\BASTOS-Diagnostics\Boot-History\Boot-%RANDOM%-%RANDOM%"
  md "!BASTOS_PREVIOUS_BOOT!" >nul 2>&1
  copy /y "%BASTOS_MEDIA%\BASTOS-Recovery.log" "!BASTOS_PREVIOUS_BOOT!\Recovery.log" >nul 2>&1
  if exist "%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" copy /y "%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" "!BASTOS_PREVIOUS_BOOT!\Last-Error.txt" >nul 2>&1
)
echo Partition detectee : %BASTOS_MEDIA%>%BASTOS_MEDIA%\BASTOS-Recovery.log
echo Debut des controles integraux v16-SpecializeAware-BastOS avant reinstallation.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
type X:\BASTOS-Start-Early.log >>%BASTOS_MEDIA%\BASTOS-Recovery.log 2>nul
>>%BASTOS_MEDIA%\BASTOS-Recovery.log echo Etape prejournal persistante terminee.

rem Un manifeste de mode lie chaque demarrage a une action precise. Les anciens
rem fichiers diagnostic ne peuvent plus choisir le parcours a eux seuls.
if exist "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt" for /f "usebackq tokens=1,2 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt") do if not defined BASTOS_BOOT_MODE (
  set "BASTOS_BOOT_MODE=%%A"
  set "BASTOS_BOOT_MODE_ID=%%B"
)
if /i "!BASTOS_BOOT_MODE!"=="BOOTONCE" goto AUTHORIZE_BOOTONCE
if /i "!BASTOS_BOOT_MODE!"=="DIAGNOSTIC" goto AUTHORIZE_DIAGNOSTIC
goto AUTHORIZATION_FAILED

:AUTHORIZE_BOOTONCE
if not exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" goto AUTHORIZATION_FAILED
if not exist "%BASTOS_MEDIA%\BASTOS-ACTIVE-ATTEMPT.txt" goto AUTHORIZATION_FAILED
set /p BASTOS_ATTEMPT_ID=<"%BASTOS_MEDIA%\BASTOS-ACTIVE-ATTEMPT.txt"
if /i not "!BASTOS_BOOT_MODE_ID!"=="!BASTOS_ATTEMPT_ID!" goto AUTHORIZATION_FAILED
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-ONLY.token" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-Diagnostic-Result.log" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-WINDOWS-PARTITION.txt" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-EFI-PARTITION.txt" >nul 2>&1
set "BASTOS_DIAGNOSTIC_ONLY=0"
goto AUTHORIZATION_READY

:AUTHORIZE_DIAGNOSTIC
if not exist "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-ONLY.token" goto AUTHORIZATION_FAILED
if exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" goto AUTHORIZATION_FAILED
if exist "%BASTOS_MEDIA%\BASTOS-ACTIVE-ATTEMPT.txt" goto AUTHORIZATION_FAILED
set "BASTOS_DIAGNOSTIC_ID="
set /p BASTOS_DIAGNOSTIC_ID=<"%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-ONLY.token"
if /i not "!BASTOS_BOOT_MODE_ID!"=="!BASTOS_DIAGNOSTIC_ID!" goto AUTHORIZATION_FAILED
del /f /q "%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-ONLY.token" >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt" >nul 2>&1
set "BASTOS_DIAGNOSTIC_ONLY=1"
>>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo Mode diagnostic lie a la demande courante et active.
goto AUTHORIZATION_READY

:AUTHORIZATION_FAILED
echo ECHEC PRECONTROLE : autorisation de demarrage absente, incomplete ou incoherente.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
>>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo BootMode=!BASTOS_BOOT_MODE! ModeAttempt=!BASTOS_BOOT_MODE_ID! ActiveAttempt=!BASTOS_ATTEMPT_ID!
if not exist "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt" >>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo Missing=BASTOS-BOOT-MODE.txt
if not exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" >>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo Missing=BASTOS-AUTO-REINSTALL.token
if not exist "%BASTOS_MEDIA%\BASTOS-ACTIVE-ATTEMPT.txt" >>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo Missing=BASTOS-ACTIVE-ATTEMPT.txt
set "BASTOS_EXIT_CODE=56"
goto SAFE_REBOOT

:AUTHORIZATION_READY
if defined BASTOS_ATTEMPT_ID (
  set "BASTOS_DIAG=%BASTOS_MEDIA%\BASTOS-Diagnostics\Attempts\!BASTOS_ATTEMPT_ID!"
  if not exist "!BASTOS_DIAG!" md "!BASTOS_DIAG!" >nul 2>&1
)
if defined BASTOS_ATTEMPT_ID del /f /q "%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" >nul 2>&1
if defined BASTOS_ATTEMPT_ID del /f /q "%BASTOS_MEDIA%\BASTOS-LAST-ERROR.json" >nul 2>&1
>>%BASTOS_MEDIA%\BASTOS-Recovery.log echo Contexte de tentative charge : !BASTOS_ATTEMPT_ID!.
call :SYNC_DIAGNOSTICS "WinPEStarted"
>>%BASTOS_MEDIA%\BASTOS-Recovery.log echo Synchronisation diagnostic WinPE terminee.

if not exist "%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe" (
  echo ECHEC PRECONTROLE : sonde native de disque absente de WinPE.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=42"
  goto SAFE_REBOOT
)
if "%BASTOS_DIAGNOSTIC_ONLY%"=="1" goto DIAGNOSTIC_PRECHECKS

for %%F in (
  BASTOS-LAYOUT-DISK0.ok
  BASTOS-WINDOWS-DISK-ID.txt
  BASTOS-DELETE-PARTITIONS.txt
  BASTOS-CREATE-PARTITIONS.txt
  BASTOS-RECOVERY-PARTITION.txt
  BASTOS-WINDOWS-PARTITION.txt
  BASTOS-Recovery-Unattend.xml
  Application\BASTOS-LocalOnly-OOBE.cmd
  Application\BASTOS-SetupComplete.cmd
  sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt
  sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd
  setup.exe
) do if not exist "%BASTOS_MEDIA%\%%F" (
  echo ECHEC PRECONTROLE : fichier obligatoire absent %%F.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=24"
  goto SAFE_REBOOT
)
if "%BASTOS_DIAGNOSTIC_ONLY%"=="0" if not exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" (
  echo ECHEC PRECONTROLE : jeton de reinstallation absent.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=24"
  goto SAFE_REBOOT
)

if exist "%BASTOS_MEDIA%\sources\install.wim" set "BASTOS_IMAGE=%BASTOS_MEDIA%\sources\install.wim"
if not defined BASTOS_IMAGE if exist "%BASTOS_MEDIA%\sources\install.esd" set "BASTOS_IMAGE=%BASTOS_MEDIA%\sources\install.esd"
if not defined BASTOS_IMAGE (
  echo ECHEC PRECONTROLE : install.wim ou install.esd absent.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=3"
  goto SAFE_REBOOT
)

find "__BASTOS_" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : choix langue, clavier ou compte non resolus.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=17"
  goto SAFE_REBOOT
)
rem BootOnce a deja valide le XML avec le parseur .NET avant le redemarrage.
rem WinPE effectue ici une seconde verification non destructive. Le compte normal
rem Bastos est cree localement par oobeSystem, sans mot de passe et sans domaine.
set "BASTOS_RUFUS_LOCAL=0"
rem v17: le compte est cree et teste en specialize, sans dependance FirstLogon.
find /i "BASTOS local account before OOBE" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not errorlevel 1 (
  if not exist "%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\Initialize-BASTOS-LocalAccount.ps1" (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  if not exist "%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\Installation-Expected.json" (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find "SpecializePasswordlessV1" "%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\Installation-Expected.json" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "Initialize-BASTOS-LocalAccount.ps1" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<LocalAccounts" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if not errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  set "BASTOS_RUFUS_LOCAL=1"
  goto ACCOUNT_PROFILE_VALIDATED
)
find "UABhAHMAcwB3AG8AcgBkAA==" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not errorlevel 1 (
  find /i "<PlainText>false</PlainText>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<AutoLogon>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  set "BASTOS_RUFUS_USERNAME="
  set /p BASTOS_RUFUS_USERNAME=<"%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt"
  if not defined BASTOS_RUFUS_USERNAME (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<Name>!BASTOS_RUFUS_USERNAME!</Name>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<Username>!BASTOS_RUFUS_USERNAME!</Username>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<LogonCount>1</LogonCount>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  find /i "<Enabled>true</Enabled>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
  if errorlevel 1 (set "BASTOS_EXIT_CODE=67" & goto SAFE_REBOOT)
  set "BASTOS_RUFUS_LOCAL=1"
  goto ACCOUNT_PROFILE_VALIDATED
)

find /i "<AutoLogon>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : AutoLogon local Bastos requis absent.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<Username>Bastos</Username>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : AutoLogon ne cible pas le compte local Bastos.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<Enabled>true</Enabled>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : AutoLogon Bastos n est pas active.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<LogonCount>1</LogonCount>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : AutoLogonCount Bastos est incoherent.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
rem LocalAccounts peut contenir des attributs xmlns apres serialisation .NET.
rem Chercher le debut de balise evite de refuser un XML valide.
find /i "<LocalAccounts" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : la creation du compte local Bastos est absente.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
set "BASTOS_EMPTY_PASSWORD_VALUE="
find /i "<Value />" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not errorlevel 1 set "BASTOS_EMPTY_PASSWORD_VALUE=1"
if not defined BASTOS_EMPTY_PASSWORD_VALUE find /i "<Value/>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not defined BASTOS_EMPTY_PASSWORD_VALUE if not errorlevel 1 set "BASTOS_EMPTY_PASSWORD_VALUE=1"
if not defined BASTOS_EMPTY_PASSWORD_VALUE find /i "<Value></Value>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not defined BASTOS_EMPTY_PASSWORD_VALUE if not errorlevel 1 set "BASTOS_EMPTY_PASSWORD_VALUE=1"
if not defined BASTOS_EMPTY_PASSWORD_VALUE (
  echo ECHEC PRECONTROLE : aucune valeur de mot de passe vide n est serialisee.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<Domain>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : le domaine local explicite AutoLogon est absent.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<Domain>.</Domain>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : le domaine ambigu point est interdit.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
find /i "<Name>Bastos</Name>" "%BASTOS_MEDIA%\BASTOS-Recovery-Unattend.xml" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : le compte local Bastos n est pas defini.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=67"
  goto SAFE_REBOOT
)
:ACCOUNT_PROFILE_VALIDATED
echo Precontrole compte local Bastos et filet ms-cxh:localonly valide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
find /i "clean" "%BASTOS_MEDIA%\BASTOS-CREATE-PARTITIONS.txt" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : commande CLEAN interdite.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=20"
  goto SAFE_REBOOT
)
find /i "assign letter=W" "%BASTOS_MEDIA%\BASTOS-CREATE-PARTITIONS.txt" >nul 2>&1
if errorlevel 1 (
  echo ECHEC PRECONTROLE : le plan ne cree pas W:.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=19"
  goto SAFE_REBOOT
)

set "BASTOS_EXPECTED_DISK_ID="
set /p BASTOS_EXPECTED_DISK_ID=<"%BASTOS_MEDIA%\BASTOS-WINDOWS-DISK-ID.txt"
if not defined BASTOS_EXPECTED_DISK_ID (
  echo ECHEC PRECONTROLE : identite GPT vide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=9"
  goto SAFE_REBOOT
)

rem Le meme NVMe peut changer de numero dans WinPE. La sonde interroge l API
rem disque binaire de Windows : aucune traduction ni mise en forme DiskPart.
for /f "delims=" %%D in ('%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe --find-disk "%BASTOS_EXPECTED_DISK_ID%" 2^>X:\BASTOS-probe-disk.log') do set "BASTOS_TARGET_DISK=%%D"
if not defined BASTOS_TARGET_DISK (
  echo ECHEC PRECONTROLE : GUID GPT absent, duplique ou illisible.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  if exist X:\BASTOS-probe-disk.log type X:\BASTOS-probe-disk.log>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=11"
  goto SAFE_REBOOT
)
echo Disque Windows retrouve dans WinPE : disque %BASTOS_TARGET_DISK%, GUID %BASTOS_EXPECTED_DISK_ID%.>>%BASTOS_MEDIA%\BASTOS-Recovery.log

set "BASTOS_RECOVERY_PARTITION="
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-RECOVERY-PARTITION.txt") do if not defined BASTOS_RECOVERY_PARTITION (
  set "BASTOS_RECOVERY_PARTITION=%%A"
  set "BASTOS_RECOVERY_OFFSET=%%B"
  set "BASTOS_RECOVERY_TYPE=%%C"
  set "BASTOS_RECOVERY_GUID=%%D"
)
if not defined BASTOS_RECOVERY_PARTITION (
  echo ECHEC PRECONTROLE : identite de partition Recovery vide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=25"
  goto SAFE_REBOOT
)
call :VALIDATE_PARTITION %BASTOS_RECOVERY_PARTITION% %BASTOS_RECOVERY_OFFSET% %BASTOS_RECOVERY_TYPE% %BASTOS_RECOVERY_GUID%
if errorlevel 1 (
  echo ECHEC PRECONTROLE : numero, offset, type ou GUID de BASTOS_RECOVERY different.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=26"
  goto SAFE_REBOOT
)
if not exist "%BASTOS_MEDIA%\BASTOS-ISO.sha256" (
  echo ECHEC PRECONTROLE : les marqueurs du volume protege ont disparu.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=28"
  goto SAFE_REBOOT
)

if exist "%BASTOS_MEDIA%\BASTOS-EFI-PARTITION.txt" (
  for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-EFI-PARTITION.txt") do call :VALIDATE_PARTITION %%A %%B %%C %%D
  if errorlevel 1 (
    echo ECHEC PRECONTROLE : la partition EFI a change.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=29"
    goto SAFE_REBOOT
  )
)

set "BASTOS_WINDOWS_PARTITION="
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-WINDOWS-PARTITION.txt") do if not defined BASTOS_WINDOWS_PARTITION (
  set "BASTOS_WINDOWS_PARTITION=%%A"
  set "BASTOS_WINDOWS_OFFSET=%%B"
  set "BASTOS_WINDOWS_TYPE=%%C"
  set "BASTOS_WINDOWS_GUID=%%D"
)
if not defined BASTOS_WINDOWS_PARTITION (
  echo ECHEC PRECONTROLE : identite de la partition Windows absente.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=30"
  goto SAFE_REBOOT
)
set "BASTOS_LAST_DELETE="
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-DELETE-PARTITIONS.txt") do set "BASTOS_LAST_DELETE=%%A|%%B|%%C|%%D"
if not "%BASTOS_LAST_DELETE%"=="%BASTOS_WINDOWS_PARTITION%|%BASTOS_WINDOWS_OFFSET%|%BASTOS_WINDOWS_TYPE%|%BASTOS_WINDOWS_GUID%" (
  echo ECHEC PRECONTROLE : la partition Windows n est pas la derniere cible explicite du plan.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=30"
  goto SAFE_REBOOT
)

set "BASTOS_DELETE_FOUND=0"
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-DELETE-PARTITIONS.txt") do (
  set "BASTOS_DELETE_FOUND=1"
  if "%%A"=="%BASTOS_RECOVERY_PARTITION%" (
    echo ECHEC PRECONTROLE : le plan tente de supprimer BASTOS_RECOVERY.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=31"
    goto SAFE_REBOOT
  )
  call :VALIDATE_PARTITION %%A %%B %%C %%D
  if errorlevel 1 (
    echo ECHEC PRECONTROLE : la partition %%A ne correspond plus a l offset %%B et au type %%C.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=32"
    goto SAFE_REBOOT
  )
)
if "%BASTOS_DELETE_FOUND%"=="0" (
  echo ECHEC PRECONTROLE : aucune partition a remplacer.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=34"
  goto SAFE_REBOOT
)

set "BASTOS_ANSWER=%BASTOS_MEDIA%\BASTOS-Recovery-Unattend-Disk%BASTOS_TARGET_DISK%.xml"
if not exist "%BASTOS_ANSWER%" (
  echo ECHEC PRECONTROLE : reponse Windows absente pour le disque WinPE %BASTOS_TARGET_DISK%.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=35"
  goto SAFE_REBOOT
)
find "__BASTOS_" "%BASTOS_ANSWER%" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : fichier de reponses WinPE non resolu.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=36"
  goto SAFE_REBOOT
)
find /i "<SkipMachineOOBE>" "%BASTOS_ANSWER%" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : SkipMachineOOBE deconseille est encore present.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=56"
  goto SAFE_REBOOT
)
find /i "<SkipUserOOBE>" "%BASTOS_ANSWER%" >nul 2>&1
if not errorlevel 1 (
  echo ECHEC PRECONTROLE : SkipUserOOBE est encore present.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=57"
  goto SAFE_REBOOT
)

rem Recheck the real WIM edition in WinPE before consuming authorization or deleting partitions.
set "BASTOS_SELECTED_INDEX="
set "BASTOS_SELECTED_EDITION="
if exist "%BASTOS_MEDIA%\BASTOS-IMAGE-SELECTION.txt" for /f "usebackq tokens=1,2 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-IMAGE-SELECTION.txt") do (
  set "BASTOS_SELECTED_INDEX=%%A"
  set "BASTOS_SELECTED_EDITION=%%B"
)
if not defined BASTOS_SELECTED_INDEX goto IMAGE_SELECTION_FAILED
if not defined BASTOS_SELECTED_EDITION goto IMAGE_SELECTION_FAILED
dism.exe /English /Get-WimInfo /WimFile:"%BASTOS_IMAGE%" /Index:!BASTOS_SELECTED_INDEX! >X:\BASTOS-ImageSelection.log 2>&1
if errorlevel 1 goto IMAGE_SELECTION_FAILED
set "BASTOS_ACTUAL_EDITION="
for /f "usebackq tokens=1,* delims=:" %%A in ("X:\BASTOS-ImageSelection.log") do if "%%A"=="Edition " for /f "tokens=*" %%C in ("%%B") do set "BASTOS_ACTUAL_EDITION=%%C"
if /i not "!BASTOS_ACTUAL_EDITION!"=="!BASTOS_SELECTED_EDITION!" goto IMAGE_SELECTION_FAILED
>>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo ImageSelectionValidated index=!BASTOS_SELECTED_INDEX! edition=!BASTOS_ACTUAL_EDITION!
goto IMAGE_SELECTION_READY

:IMAGE_SELECTION_FAILED
>>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo ECHEC PRECONTROLE : index ou edition du WIM divergent. Aucun effacement autorise.
if exist X:\BASTOS-ImageSelection.log type X:\BASTOS-ImageSelection.log >>"%BASTOS_MEDIA%\BASTOS-Recovery.log"
set "BASTOS_EXIT_CODE=80"
goto SAFE_REBOOT

:IMAGE_SELECTION_READY
rem Drivers are supplied to Setup, never force-loaded into the initial WinPE.
rem These checks run before any partition deletion. The complete manifest was
rem independently hashed in Windows before the reboot was authorized.
set "BASTOS_DRIVER_ARGS="
if exist "%BASTOS_MEDIA%\BASTOS-DRIVERS.enabled" (
  rem Only cmd builtins: findstr.exe is not included in every WinPE image.
  set "BASTOS_DRIVER_MODE="
  set "BASTOS_DRIVER_MARKER_SIZE="
  set "BASTOS_DRIVER_MARKER_LINES=0"
  for %%F in ("%BASTOS_MEDIA%\BASTOS-DRIVERS.enabled") do set "BASTOS_DRIVER_MARKER_SIZE=%%~zF"
  set /p BASTOS_DRIVER_MODE=<"%BASTOS_MEDIA%\BASTOS-DRIVERS.enabled"
  for /f "usebackq eol=| delims=" %%L in ("%BASTOS_MEDIA%\BASTOS-DRIVERS.enabled") do set /a BASTOS_DRIVER_MARKER_LINES+=1 >nul
  set "BASTOS_DRIVER_MARKER_VALID=1"
  if not "!BASTOS_DRIVER_MODE!"=="0" if not "!BASTOS_DRIVER_MODE!"=="1" set "BASTOS_DRIVER_MARKER_VALID=0"
  if not "!BASTOS_DRIVER_MARKER_SIZE!"=="1" if not "!BASTOS_DRIVER_MARKER_SIZE!"=="3" set "BASTOS_DRIVER_MARKER_VALID=0"
  if not "!BASTOS_DRIVER_MARKER_LINES!"=="1" set "BASTOS_DRIVER_MARKER_VALID=0"
  if "!BASTOS_DRIVER_MARKER_VALID!"=="0" (
    >>"%BASTOS_MEDIA%\BASTOS-Recovery.log" echo ECHEC PRECONTROLE : marqueur pilotes invalide, valeur 0 ou 1 attendue.
    set "BASTOS_EXIT_CODE=81"
    goto SAFE_REBOOT
  )
  if "!BASTOS_DRIVER_MODE!"=="1" (
    if not exist "%BASTOS_MEDIA%\BASTOS-Drivers\Active\Manifest.json" (
      set "BASTOS_EXIT_CODE=82"
      goto SAFE_REBOOT
    )
    if not exist "%BASTOS_MEDIA%\BASTOS-Drivers\Active\Packages\" (
      set "BASTOS_EXIT_CODE=83"
      goto SAFE_REBOOT
    )
    dir /s /b "%BASTOS_MEDIA%\BASTOS-Drivers\Active\Packages\*.inf" >nul 2>&1
    if not errorlevel 1 set BASTOS_DRIVER_ARGS=/InstallDrivers "%BASTOS_MEDIA%\BASTOS-Drivers\Active\Packages"
  )
)
echo Tous les precontroles ont reussi. La partition BASTOS est protegee par numero, offset, type, GUID et marqueurs.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
set "BASTOS_PRECHECKS_COMPLETED=1"
call :SYNC_DIAGNOSTICS "PrechecksCompleted"
set "BASTOS_BOOT_ID="
if exist "%BASTOS_MEDIA%\BASTOS-BOOT-ID.txt" set /p BASTOS_BOOT_ID=<"%BASTOS_MEDIA%\BASTOS-BOOT-ID.txt"
bcdedit /set {bootmgr} displaybootmenu no >nul 2>&1
bcdedit /timeout 0 >nul 2>&1
if defined BASTOS_BOOT_ID bcdedit /displayorder %BASTOS_BOOT_ID% /remove >nul 2>&1
del /f /q "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token"
del /f /q "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt"
if exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" goto TOKEN_CONSUMPTION_FAILED
if exist "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt" goto TOKEN_CONSUMPTION_FAILED
goto TOKEN_CONSUMPTION_OK

:TOKEN_CONSUMPTION_FAILED
  echo ECHEC PRECONTROLE : jeton non consommable.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=21"
  goto SAFE_REBOOT

:TOKEN_CONSUMPTION_OK

rem Chaque partition est reverifiee puis supprimee separement. Windows est la
rem derniere suppression du fichier; les partitions auxiliaires servent de test.
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-DELETE-PARTITIONS.txt") do (
  call :VALIDATE_PARTITION %%A %%B %%C %%D
  if errorlevel 1 (
    echo ECHEC CRITIQUE : la partition %%A a change avant suppression.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=37"
    goto FAIL_REBOOT
  )
  rem La redirection doit preceder ECHO. Sinon "disk 0>X:" est interprete
  rem par cmd.exe comme la redirection du descripteur 0 et le numero disparait.
  >X:\BASTOS-delete-one.txt echo select disk %BASTOS_TARGET_DISK%
  >>X:\BASTOS-delete-one.txt echo select partition %%A
  >>X:\BASTOS-delete-one.txt echo delete partition override
  set "BASTOS_DESTRUCTIVE_STARTED=1"
  diskpart /s X:\BASTOS-delete-one.txt>>%BASTOS_MEDIA%\BASTOS-Recovery.log 2>&1
  if !errorlevel! neq 0 (
    echo ECHEC CRITIQUE : DiskPart a refuse la suppression %%A.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=22"
    goto CRITICAL_REBOOT
  )
  call :VALIDATE_PARTITION %%A %%B %%C %%D
  if not errorlevel 1 (
    echo ECHEC CRITIQUE : la partition %%A existe encore apres la demande de suppression.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=41"
    goto CRITICAL_REBOOT
  )
  call :VALIDATE_PARTITION %BASTOS_RECOVERY_PARTITION% %BASTOS_RECOVERY_OFFSET% %BASTOS_RECOVERY_TYPE% %BASTOS_RECOVERY_GUID%
  if errorlevel 1 (
    echo ECHEC CRITIQUE : BASTOS_RECOVERY n est plus a son emplacement apres suppression %%A.>X:\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=7"
    goto CRITICAL_REBOOT
  )
  if not exist "%BASTOS_MEDIA%\BASTOS-ISO.sha256" (
    echo ECHEC CRITIQUE : le volume BASTOS n est plus accessible apres suppression %%A.>X:\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=7"
    goto CRITICAL_REBOOT
  )
  call :SYNC_DIAGNOSTICS "PartitionDeleted-%%A"
)

>X:\BASTOS-create.txt echo select disk %BASTOS_TARGET_DISK%
>>X:\BASTOS-create.txt type "%BASTOS_MEDIA%\BASTOS-CREATE-PARTITIONS.txt"
diskpart /s X:\BASTOS-create.txt>>%BASTOS_MEDIA%\BASTOS-Recovery.log 2>&1
if errorlevel 1 (
  echo ECHEC CRITIQUE : creation des partitions Windows refusee.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=39"
  goto CRITICAL_REBOOT
)
if not exist W:\ (
  echo ECHEC CRITIQUE : la nouvelle partition Windows W: est absente.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=6"
  goto CRITICAL_REBOOT
)
call :VALIDATE_PARTITION %BASTOS_RECOVERY_PARTITION% %BASTOS_RECOVERY_OFFSET% %BASTOS_RECOVERY_TYPE% %BASTOS_RECOVERY_GUID%
if errorlevel 1 (
  echo ECHEC CRITIQUE : BASTOS_RECOVERY a change apres creation de Windows.>X:\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=40"
  goto CRITICAL_REBOOT
)

set "BASTOS_DISK_PREPARED=1"
echo Disque prepare. Demarrage de Windows Setup avec la cible WinPE %BASTOS_TARGET_DISK%...>>%BASTOS_MEDIA%\BASTOS-Recovery.log
call :SYNC_DIAGNOSTICS "WindowsSetupStarting"
set "BASTOS_COPYLOGS="
if defined BASTOS_DIAG (
  if not exist "%BASTOS_DIAG%\Windows-Setup\Native-Failure" md "%BASTOS_DIAG%\Windows-Setup\Native-Failure" >nul 2>&1
  set "BASTOS_COPYLOGS=%BASTOS_DIAG%\Windows-Setup\Native-Failure"
)
if not "!BASTOS_PRECHECKS_COMPLETED!"=="1" (
  set "BASTOS_EXIT_CODE=67"
  echo ECHEC INTERNE : saut de flux detecte avant Windows Setup, precontroles non termines.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  goto SAFE_REBOOT
)
if not "!BASTOS_DISK_PREPARED!"=="1" (
  set "BASTOS_EXIT_CODE=68"
  echo ECHEC INTERNE : saut de flux detecte avant Windows Setup, disque non prepare.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  if "!BASTOS_DESTRUCTIVE_STARTED!"=="1" goto CRITICAL_REBOOT
  goto SAFE_REBOOT
)
set "BASTOS_SETUP_LAUNCHED=1"
if defined BASTOS_COPYLOGS (
  "%BASTOS_MEDIA%\setup.exe" /Unattend:"%BASTOS_ANSWER%" /InstallFrom "%BASTOS_IMAGE%" !BASTOS_DRIVER_ARGS! /CopyLogs "!BASTOS_COPYLOGS!"
) else (
  "%BASTOS_MEDIA%\setup.exe" /Unattend:"%BASTOS_ANSWER%" /InstallFrom "%BASTOS_IMAGE%" !BASTOS_DRIVER_ARGS!
)
if not "!BASTOS_SETUP_LAUNCHED!"=="1" (
  set "BASTOS_EXIT_CODE=69"
  echo ECHEC INTERNE : retour de sous-routine incoherent, Windows Setup n a pas ete lance.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  if "!BASTOS_DESTRUCTIVE_STARTED!"=="1" goto CRITICAL_REBOOT
  goto SAFE_REBOOT
)
set "BASTOS_SETUP_EXIT=!ERRORLEVEL!"
echo Windows Setup a rendu le code !BASTOS_SETUP_EXIT!.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
call :SYNC_DIAGNOSTICS "WindowsSetupReturned-!BASTOS_SETUP_EXIT!"
if not "!BASTOS_SETUP_EXIT!"=="0" (
  set "BASTOS_EXIT_CODE=!BASTOS_SETUP_EXIT!"
  goto CRITICAL_REBOOT
)
if "!BASTOS_RUFUS_LOCAL!"=="1" (
  echo Profil local : compte cree et verifie avant OOBE ; finalisation de session independante.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  call :SYNC_DIAGNOSTICS "WindowsSetupReturned-RufusLocal"
  wpeutil reboot
  exit /b 0
)
call :HARDEN_OFFLINE_WINDOWS
set "BASTOS_HARDEN_EXIT=!ERRORLEVEL!"
call :CAPTURE_HARDENING_DIAGNOSTICS !BASTOS_HARDEN_EXIT!
if not "!BASTOS_HARDEN_EXIT!"=="0" (
  set "BASTOS_EXIT_CODE=66"
  echo ECHEC CRITIQUE : le filet pre-connexion n a pas pu etre prepare hors ligne, sous-code !BASTOS_HARDEN_EXIT!.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  call :SYNC_DIAGNOSTICS "OfflinePreLogonValidationFailed-66-!BASTOS_HARDEN_EXIT!"
  call :WRITE_LAST_FAILURE "OfflinePreLogonValidationFailed" "66" "!BASTOS_HARDEN_EXIT!"
  goto CRITICAL_STOP
)
echo Reponse specialize et filet pre-connexion prepares; SetupComplete doit verifier BastOS avec le nom final de la machine.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
call :SYNC_DIAGNOSTICS "OfflineWindowsHardened"
wpeutil reboot
exit /b 0

:DIAGNOSTIC_PRECHECKS
for %%F in (
  BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt
  BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt
  BASTOS-DIAGNOSTIC-WINDOWS-PARTITION.txt
  BASTOS-DIAGNOSTIC-EFI-PARTITION.txt
  BASTOS-ISO.sha256
  Application\VERSION.txt
) do if not exist "%BASTOS_MEDIA%\%%F" (
  echo ECHEC TEST : manifeste diagnostic incomplet, fichier absent %%F.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=51"
  goto SAFE_REBOOT
)

set "BASTOS_EXPECTED_DISK_ID="
set /p BASTOS_EXPECTED_DISK_ID=<"%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-WINDOWS-DISK-ID.txt"
if not defined BASTOS_EXPECTED_DISK_ID (
  echo ECHEC TEST : identite du disque Windows vide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=52"
  goto SAFE_REBOOT
)
for /f "delims=" %%D in ('%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe --find-disk "%BASTOS_EXPECTED_DISK_ID%" 2^>X:\BASTOS-probe-diagnostic-disk.log') do set "BASTOS_TARGET_DISK=%%D"
if not defined BASTOS_TARGET_DISK (
  echo ECHEC TEST : disque Windows absent, duplique ou illisible.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  if exist X:\BASTOS-probe-diagnostic-disk.log type X:\BASTOS-probe-diagnostic-disk.log>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=53"
  goto SAFE_REBOOT
)

set "BASTOS_DIAGNOSTIC_RECORD_FOUND=0"
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-RECOVERY-PARTITION.txt") do (
  set "BASTOS_DIAGNOSTIC_RECORD_FOUND=1"
  call :VALIDATE_PARTITION %%A %%B %%C %%D
)
if "%BASTOS_DIAGNOSTIC_RECORD_FOUND%"=="0" (
  echo ECHEC TEST : identite Recovery vide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=54"
  goto SAFE_REBOOT
)
if errorlevel 1 (
  echo ECHEC TEST : la partition BASTOS_RECOVERY ne correspond plus au manifeste frais.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
  set "BASTOS_EXIT_CODE=54"
  goto SAFE_REBOOT
)

for %%F in (WINDOWS EFI) do (
  set "BASTOS_DIAGNOSTIC_RECORD_FOUND=0"
  for /f "usebackq tokens=1-4 delims=|" %%A in ("%BASTOS_MEDIA%\BASTOS-DIAGNOSTIC-%%F-PARTITION.txt") do (
    set "BASTOS_DIAGNOSTIC_RECORD_FOUND=1"
    call :VALIDATE_PARTITION %%A %%B %%C %%D
  )
  if "!BASTOS_DIAGNOSTIC_RECORD_FOUND!"=="0" (
    echo ECHEC TEST : identite %%F vide.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=55"
    goto SAFE_REBOOT
  )
  if errorlevel 1 (
    echo ECHEC TEST : la partition %%F ne correspond plus au manifeste frais.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
    set "BASTOS_EXIT_CODE=55"
    goto SAFE_REBOOT
  )
)

>"%BASTOS_MEDIA%\BASTOS-Diagnostic-Result.log" echo DIAGNOSTIC_OK FreshPartitionManifestValidated drive=%BASTOS_MEDIA% disk=%BASTOS_TARGET_DISK%
>>"%BASTOS_MEDIA%\BASTOS-Native-Launcher.log" echo %DATE% %TIME% DiagnosticFreshManifestSucceeded drive=%BASTOS_MEDIA% disk=%BASTOS_TARGET_DISK%
echo Le manifeste diagnostic frais correspond au disque et aux partitions actuelles.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
echo.
echo ===============================================================
echo TEST BASTOS RECOVERY REUSSI.
echo Le lanceur WinPE et la sonde native ont fonctionne.
echo Le disque Windows, EFI et BASTOS_RECOVERY ont ete valides.
echo Aucun ancien plan de suppression n a ete utilise.
echo Aucune partition Windows n a ete modifiee.
echo Appuyez sur une touche pour revenir sous Windows.
echo ===============================================================
pause >nul
wpeutil reboot
exit /b 0

:HARDEN_OFFLINE_WINDOWS
if not exist W:\Windows\System32\Config\SYSTEM exit /b 2

rem Le nom present dans la ruche SYSTEM juste apres Setup est provisoire : la
rem passe specialize ne s execute qu au premier demarrage. La source de verite
rem avant ce demarrage est donc ComputerName dans la reponse, jamais la ruche.
set "BASTOS_EXPECTED_COMPUTER_NAME="
for /f "tokens=2 delims=<>" %%A in ('find /i "<ComputerName>" "%BASTOS_ANSWER%"') do if not defined BASTOS_EXPECTED_COMPUTER_NAME set "BASTOS_EXPECTED_COMPUTER_NAME=%%A"
if not defined BASTOS_EXPECTED_COMPUTER_NAME exit /b 45
set "BASTOS_NAME_REMAINDER=!BASTOS_EXPECTED_COMPUTER_NAME!"
for %%C in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 -) do if defined BASTOS_NAME_REMAINDER set "BASTOS_NAME_REMAINDER=!BASTOS_NAME_REMAINDER:%%C=!"
if defined BASTOS_NAME_REMAINDER exit /b 45
if not "!BASTOS_EXPECTED_COMPUTER_NAME:~15,1!"=="" exit /b 45
if "%BASTOS_EXPECTED_COMPUTER_NAME%"=="." exit /b 45

rem Injecter d abord les deux filets pre-connexion. Ainsi, meme si la ruche
rem SYSTEM est encore verrouillee par Setup, aucun redemarrage manuel ne peut
rem laisser le nouveau Windows sans scripts de suppression du mot de passe.
set "BASTOS_OFFLINE_RUNTIME=W:\ProgramData\BASTOS-ISO"
set "BASTOS_OFFLINE_SETUP=W:\Windows\Setup\Scripts"
if not exist "%BASTOS_OFFLINE_RUNTIME%" md "%BASTOS_OFFLINE_RUNTIME%" >nul 2>&1
if not exist "%BASTOS_OFFLINE_SETUP%" md "%BASTOS_OFFLINE_SETUP%" >nul 2>&1
if not exist "%BASTOS_OFFLINE_RUNTIME%" exit /b 12
if not exist "%BASTOS_OFFLINE_SETUP%" exit /b 13
copy /y "%BASTOS_MEDIA%\Application\Initialize-BASTOS-PreLogon.ps1" "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" >X:\BASTOS-prelogon-script.log 2>&1
if errorlevel 1 exit /b 14
copy /y "%BASTOS_MEDIA%\Application\BASTOS-LocalOnly-OOBE.cmd" "%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalOnly-OOBE.cmd" >X:\BASTOS-localonly-oobe.log 2>&1
if errorlevel 1 exit /b 43
copy /y "%BASTOS_MEDIA%\Application\BASTOS-SetupComplete.cmd" "%BASTOS_OFFLINE_SETUP%\SetupComplete.cmd" >X:\BASTOS-setupcomplete.log 2>&1
if errorlevel 1 exit /b 15
copy /y "%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt" "%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt" >X:\BASTOS-account-marker.log 2>&1
if errorlevel 1 exit /b 16
if not exist "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" exit /b 17
if not exist "%BASTOS_OFFLINE_SETUP%\SetupComplete.cmd" exit /b 18
if not exist "%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt" exit /b 19

reg unload HKLM\BASTOS_OFFLINE_SYSTEM >nul 2>&1
set "BASTOS_REG_LOAD_ATTEMPT=0"
:HARDEN_REG_LOAD_RETRY
set /a BASTOS_REG_LOAD_ATTEMPT+=1
reg load HKLM\BASTOS_OFFLINE_SYSTEM W:\Windows\System32\Config\SYSTEM >X:\BASTOS-reg-load.log 2>&1
if not errorlevel 1 goto HARDEN_REG_LOADED
if %BASTOS_REG_LOAD_ATTEMPT% geq 15 exit /b 3
ping 127.0.0.1 -n 3 >nul 2>&1
goto HARDEN_REG_LOAD_RETRY
:HARDEN_REG_LOADED
reg add HKLM\BASTOS_OFFLINE_SYSTEM\Setup /v UnattendFile /t REG_SZ /d "C:\Windows\Panther\Unattend\Unattend.xml" /f >X:\BASTOS-reg-unattend-pointer.log 2>&1
set "BASTOS_UNATTEND_POINTER_EXIT=%ERRORLEVEL%"
set "BASTOS_OFFLINE_COMPUTER_NAME="
for /f "tokens=1,2,*" %%A in ('reg query "HKLM\BASTOS_OFFLINE_SYSTEM\ControlSet001\Control\ComputerName\ComputerName" /v ComputerName 2^>nul ^| find /i "REG_SZ"') do set "BASTOS_OFFLINE_COMPUTER_NAME=%%C"
if not defined BASTOS_OFFLINE_COMPUTER_NAME for /f "tokens=1,2,*" %%A in ('reg query "HKLM\BASTOS_OFFLINE_SYSTEM\ControlSet002\Control\ComputerName\ComputerName" /v ComputerName 2^>nul ^| find /i "REG_SZ"') do set "BASTOS_OFFLINE_COMPUTER_NAME=%%C"
reg unload HKLM\BASTOS_OFFLINE_SYSTEM >X:\BASTOS-reg-unload.log 2>&1
if not "%BASTOS_UNATTEND_POINTER_EXIT%"=="0" exit /b 30

rem Setup doit avoir mis en cache le fichier exact valide avant les suppressions.
rem Le recopier apres son retour rend les deux directives OOBE autoritaires pour
rem le premier demarrage, comme dans la reinstallation USB qui a reussi.
if not exist W:\Windows\Panther md W:\Windows\Panther >nul 2>&1
if not exist W:\Windows\Panther exit /b 6
if not exist W:\Windows\Panther\Unattend md W:\Windows\Panther\Unattend >nul 2>&1
if not exist W:\Windows\Panther\Unattend exit /b 31
copy /y "%BASTOS_ANSWER%" W:\Windows\Panther\unattend.xml >X:\BASTOS-unattend-cache.log 2>&1
if errorlevel 1 exit /b 7
copy /y "%BASTOS_ANSWER%" W:\Windows\Panther\Unattend\Unattend.xml >X:\BASTOS-unattend-embedded.log 2>&1
if errorlevel 1 exit /b 32
set "BASTOS_ANSWER_SIZE="
set "BASTOS_CACHE_SIZE="
set "BASTOS_EMBEDDED_SIZE="
for %%F in ("%BASTOS_ANSWER%") do set "BASTOS_ANSWER_SIZE=%%~zF"
for %%F in ("W:\Windows\Panther\unattend.xml") do set "BASTOS_CACHE_SIZE=%%~zF"
for %%F in ("W:\Windows\Panther\Unattend\Unattend.xml") do set "BASTOS_EMBEDDED_SIZE=%%~zF"
>X:\BASTOS-unattend-cache-compare.log echo SourceBytes=!BASTOS_ANSWER_SIZE! CacheBytes=!BASTOS_CACHE_SIZE!
>X:\BASTOS-unattend-embedded-compare.log echo SourceBytes=!BASTOS_ANSWER_SIZE! EmbeddedBytes=!BASTOS_EMBEDDED_SIZE!
if not defined BASTOS_ANSWER_SIZE exit /b 33
if not "!BASTOS_ANSWER_SIZE!"=="!BASTOS_CACHE_SIZE!" exit /b 33
if not "!BASTOS_ANSWER_SIZE!"=="!BASTOS_EMBEDDED_SIZE!" exit /b 34
find /i "<SkipMachineOOBE>" W:\Windows\Panther\unattend.xml >nul 2>&1
if not errorlevel 1 exit /b 8
find /i "<SkipUserOOBE>" W:\Windows\Panther\unattend.xml >nul 2>&1
if not errorlevel 1 exit /b 9
find /i "<LocalAccounts" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 22
find /i "<AutoLogon>" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 26
find /i "<Username>Bastos</Username>" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 27
find /i "<Name>Bastos</Name>" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 21
find /i "<Enabled>true</Enabled>" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 28
find /i "<Domain>%BASTOS_EXPECTED_COMPUTER_NAME%</Domain>" W:\Windows\Panther\unattend.xml >nul 2>&1
if errorlevel 1 exit /b 29

rem Preparer le filet Winlogon avec le nom qui sera applique par specialize.
rem SetupComplete le reverifiera ensuite avec le vrai env:COMPUTERNAME.
reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1
set "BASTOS_SOFTWARE_LOAD_ATTEMPT=0"
:HARDEN_SOFTWARE_LOAD_RETRY
set /a BASTOS_SOFTWARE_LOAD_ATTEMPT+=1
reg load HKLM\BASTOS_OFFLINE_SOFTWARE W:\Windows\System32\Config\SOFTWARE >X:\BASTOS-reg-software-load.log 2>&1
if not errorlevel 1 goto HARDEN_SOFTWARE_LOADED
if %BASTOS_SOFTWARE_LOAD_ATTEMPT% geq 15 exit /b 35
ping 127.0.0.1 -n 3 >nul 2>&1
goto HARDEN_SOFTWARE_LOAD_RETRY
:HARDEN_SOFTWARE_LOADED
set "BASTOS_OFFLINE_WINLOGON=HKLM\BASTOS_OFFLINE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
reg add "%BASTOS_OFFLINE_WINLOGON%" /v AutoAdminLogon /t REG_SZ /d 1 /f >X:\BASTOS-reg-winlogon.log 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 36)
reg add "%BASTOS_OFFLINE_WINLOGON%" /v DefaultUserName /t REG_SZ /d BastOS /f >>X:\BASTOS-reg-winlogon.log 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 37)
reg add "%BASTOS_OFFLINE_WINLOGON%" /v DefaultDomainName /t REG_SZ /d "%BASTOS_EXPECTED_COMPUTER_NAME%" /f >>X:\BASTOS-reg-winlogon.log 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 38)
reg add "%BASTOS_OFFLINE_WINLOGON%" /v DefaultPassword /t REG_SZ /d "" /f >>X:\BASTOS-reg-winlogon.log 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 39)
reg add "%BASTOS_OFFLINE_WINLOGON%" /v AutoLogonCount /t REG_DWORD /d 1 /f >>X:\BASTOS-reg-winlogon.log 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 40)
reg delete "%BASTOS_OFFLINE_WINLOGON%" /v ForceAutoLogon /f >>X:\BASTOS-reg-winlogon.log 2>&1
reg query "%BASTOS_OFFLINE_WINLOGON%" /v DefaultDomainName | find /i "%BASTOS_EXPECTED_COMPUTER_NAME%" >nul 2>&1
if errorlevel 1 (reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >nul 2>&1 & exit /b 44)
reg unload HKLM\BASTOS_OFFLINE_SOFTWARE >X:\BASTOS-reg-software-unload.log 2>&1
if errorlevel 1 exit /b 41

rem Oobe.xml reste un filet de compatibilite pour transmettre le nom deja choisi.
set "BASTOS_OOBE_INFO=W:\Windows\System32\Oobe\Info"
if not exist "%BASTOS_OOBE_INFO%" md "%BASTOS_OOBE_INFO%" >nul 2>&1
if not exist "%BASTOS_OOBE_INFO%" exit /b 10
>"%BASTOS_OOBE_INFO%\Oobe.xml" echo ^<?xml version="1.0" encoding="utf-8"?^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo ^<FirstExperience^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo   ^<oobe^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo     ^<oem^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo       ^<name^>BASTOS^</name^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo       ^<computername^>%BASTOS_EXPECTED_COMPUTER_NAME%^</computername^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo     ^</oem^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo   ^</oobe^>
>>"%BASTOS_OOBE_INFO%\Oobe.xml" echo ^</FirstExperience^>
if not exist "%BASTOS_OOBE_INFO%\Oobe.xml" exit /b 11

rem oobeSystem cree BastOS. SetupComplete valide ensuite le mot de passe vide,
rem desactive le compte integre SID-500 et verrouille Winlogon sur le nom final.
set "BASTOS_OFFLINE_RUNTIME=W:\ProgramData\BASTOS-ISO"
set "BASTOS_OFFLINE_SETUP=W:\Windows\Setup\Scripts"
if not exist "%BASTOS_OFFLINE_RUNTIME%" md "%BASTOS_OFFLINE_RUNTIME%" >nul 2>&1
if not exist "%BASTOS_OFFLINE_SETUP%" md "%BASTOS_OFFLINE_SETUP%" >nul 2>&1
if not exist "%BASTOS_OFFLINE_RUNTIME%" exit /b 12
if not exist "%BASTOS_OFFLINE_SETUP%" exit /b 13
copy /y "%BASTOS_MEDIA%\Application\Initialize-BASTOS-PreLogon.ps1" "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" >X:\BASTOS-prelogon-script.log 2>&1
if errorlevel 1 exit /b 14
copy /y "%BASTOS_MEDIA%\Application\BASTOS-SetupComplete.cmd" "%BASTOS_OFFLINE_SETUP%\SetupComplete.cmd" >X:\BASTOS-setupcomplete.log 2>&1
if errorlevel 1 exit /b 15
copy /y "%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt" "%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt" >X:\BASTOS-account-marker.log 2>&1
if errorlevel 1 exit /b 16
if not exist "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" exit /b 17
if not exist "%BASTOS_OFFLINE_SETUP%\SetupComplete.cmd" exit /b 18
if not exist "%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt" exit /b 19
find /i "LogonUser" "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" >nul 2>&1
if errorlevel 1 exit /b 23
find /i "PasswordVerified" "%BASTOS_OFFLINE_RUNTIME%\Initialize-BASTOS-PreLogon.ps1" >nul 2>&1
if errorlevel 1 exit /b 24
set "BASTOS_ACCOUNT_MARKER="
set /p BASTOS_ACCOUNT_MARKER=<"%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt"
if /i not "!BASTOS_ACCOUNT_MARKER!"=="Bastos" exit /b 25
set "BASTOS_ACCOUNT_SOURCE_SIZE="
set "BASTOS_ACCOUNT_COPY_SIZE="
for %%F in ("%BASTOS_MEDIA%\sources\$OEM$\$1\ProgramData\BASTOS-ISO\BASTOS-LocalAccount.txt") do set "BASTOS_ACCOUNT_SOURCE_SIZE=%%~zF"
for %%F in ("%BASTOS_OFFLINE_RUNTIME%\BASTOS-LocalAccount.txt") do set "BASTOS_ACCOUNT_COPY_SIZE=%%~zF"
>X:\BASTOS-account-marker-compare.log echo SourceBytes=!BASTOS_ACCOUNT_SOURCE_SIZE! CopyBytes=!BASTOS_ACCOUNT_COPY_SIZE! Value=!BASTOS_ACCOUNT_MARKER!
if not "!BASTOS_ACCOUNT_SOURCE_SIZE!"=="6" exit /b 42
if not "!BASTOS_ACCOUNT_SOURCE_SIZE!"=="!BASTOS_ACCOUNT_COPY_SIZE!" exit /b 42
if defined BASTOS_DIAG (
  if not exist "%BASTOS_DIAG%\Windows-Setup\WinPE-AfterSetup" md "%BASTOS_DIAG%\Windows-Setup\WinPE-AfterSetup" >nul 2>&1
  if exist W:\Windows\Panther robocopy W:\Windows\Panther "%BASTOS_DIAG%\Windows-Setup\WinPE-AfterSetup\Panther" /E /R:1 /W:1 /XJ /NP /NFL /NDL /XF unattend.xml autounattend.xml >nul
  if exist W:\$WINDOWS.~BT\Sources\Panther robocopy W:\$WINDOWS.~BT\Sources\Panther "%BASTOS_DIAG%\Windows-Setup\WinPE-AfterSetup\Setup-Panther" /E /R:1 /W:1 /XJ /NP /NFL /NDL /XF unattend.xml autounattend.xml >nul
  if exist W:\Windows\INF\setupapi.dev.log copy /y W:\Windows\INF\setupapi.dev.log "%BASTOS_DIAG%\Windows-Setup\WinPE-AfterSetup\setupapi.dev.log" >nul
  >"%BASTOS_DIAG%\Offline-Oobe-ComputerName.txt" echo ExpectedAfterSpecialize=%BASTOS_EXPECTED_COMPUTER_NAME%
  >>"%BASTOS_DIAG%\Offline-Oobe-ComputerName.txt" echo ProvisionalBeforeSpecialize=%BASTOS_OFFLINE_COMPUTER_NAME%
  >"%BASTOS_DIAG%\Offline-Oobe-Policy.txt" echo SkipMachineOOBE=absent
  >>"%BASTOS_DIAG%\Offline-Oobe-Policy.txt" echo SkipUserOOBE=absent
  >"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo SetupComplete=true
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo LocalAccount=Bastos
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo PasswordEmpty=true
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo LocalOnlyFallback=ms-cxh:localonly
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo HighestPrecedenceUnattend=C:\Windows\Panther\Unattend\Unattend.xml
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo AutoLogonDomain=%BASTOS_EXPECTED_COMPUTER_NAME%
  >>"%BASTOS_DIAG%\Offline-PreLogon-Ready.txt" echo OfflineWinlogonPrepared=true
)
exit /b 0

:CAPTURE_HARDENING_DIAGNOSTICS
if not defined BASTOS_DIAG exit /b 0
set "BASTOS_HARDEN_DIAG=%BASTOS_DIAG%\Offline-Hardening"
if not exist "%BASTOS_HARDEN_DIAG%" md "%BASTOS_HARDEN_DIAG%" >nul 2>&1
>"%BASTOS_HARDEN_DIAG%\ExitCode.txt" echo %~1
for %%F in (BASTOS-reg-load.log BASTOS-reg-childcompletion.log BASTOS-reg-unattend-pointer.log BASTOS-reg-unload.log BASTOS-unattend-cache.log BASTOS-unattend-embedded.log BASTOS-unattend-cache-compare.log BASTOS-unattend-embedded-compare.log BASTOS-reg-software-load.log BASTOS-reg-winlogon.log BASTOS-reg-software-unload.log BASTOS-prelogon-script.log BASTOS-setupcomplete.log BASTOS-account-marker.log BASTOS-account-marker-compare.log) do if exist X:\%%F copy /y X:\%%F "%BASTOS_HARDEN_DIAG%\%%F" >nul 2>&1
exit /b 0

:SYNC_DIAGNOSTICS
if defined BASTOS_MEDIA (
  >"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo AttemptId=!BASTOS_ATTEMPT_ID!
  >>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Stage=%~1
  >>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Result=PENDING
  >>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Timestamp=%DATE% %TIME%
  >>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo RecoveryLog=%BASTOS_MEDIA%\BASTOS-Recovery.log
)
if defined BASTOS_DIAG (
  if not exist "%BASTOS_DIAG%" md "%BASTOS_DIAG%" >nul 2>&1
  if exist "%BASTOS_MEDIA%\BASTOS-Recovery.log" copy /y "%BASTOS_MEDIA%\BASTOS-Recovery.log" "%BASTOS_DIAG%\Recovery-WinPE.log" >nul
  >>"%BASTOS_DIAG%\Recovery-Timeline.log" echo %DATE% %TIME% %~1
  if exist "%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" copy /y "%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" "%BASTOS_DIAG%\Last-Attempt.txt" >nul 2>&1
)
exit /b 0

:WRITE_LAST_FAILURE
if not defined BASTOS_MEDIA exit /b 0
>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo AttemptId=!BASTOS_ATTEMPT_ID!
>>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo Stage=%~1
>>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo ExitCode=%~2
>>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo SubCode=%~3
>>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo Timestamp=%DATE% %TIME%
>>"%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" echo RecoveryLog=%BASTOS_MEDIA%\BASTOS-Recovery.log
>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo AttemptId=!BASTOS_ATTEMPT_ID!
>>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Stage=%~1
>>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Result=FAILED
>>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo ExitCode=%~2
>>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo SubCode=%~3
>>"%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" echo Timestamp=%DATE% %TIME%
if defined BASTOS_DIAG copy /y "%BASTOS_MEDIA%\BASTOS-LAST-ERROR.txt" "%BASTOS_DIAG%\Last-Error.txt" >nul 2>&1
if defined BASTOS_DIAG copy /y "%BASTOS_MEDIA%\BASTOS-LAST-ATTEMPT.txt" "%BASTOS_DIAG%\Last-Attempt.txt" >nul 2>&1
exit /b 0

:VALIDATE_PARTITION
if "%~4"=="" exit /b 2
"%SYSTEMROOT%\System32\BASTOS-Recovery-Probe.exe" --validate-partition %BASTOS_TARGET_DISK% %~1 %~2 %~3 %~4 >X:\BASTOS-partition-detail.log 2>&1
set "BASTOS_PROBE_EXIT=%ERRORLEVEL%"
if not "%BASTOS_PROBE_EXIT%"=="0" if defined BASTOS_MEDIA type X:\BASTOS-partition-detail.log>>%BASTOS_MEDIA%\BASTOS-Recovery.log
exit /b %BASTOS_PROBE_EXIT%

:FAIL_REBOOT
if "%BASTOS_DESTRUCTIVE_STARTED%"=="1" goto CRITICAL_REBOOT
goto SAFE_REBOOT

:SAFE_REBOOT
if defined BASTOS_MEDIA echo Arret sur controle non destructif, code !BASTOS_EXIT_CODE!. Aucun disque Windows n a ete modifie.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
call :WRITE_LAST_FAILURE "PrecheckFailure" "!BASTOS_EXIT_CODE!" ""
if defined BASTOS_DIAG copy /y "%BASTOS_MEDIA%\BASTOS-Recovery.log" "!BASTOS_DIAG!\Recovery-WinPE.log" >nul 2>&1
if defined BASTOS_DIAG >>"!BASTOS_DIAG!\Recovery-Timeline.log" echo %DATE% %TIME% SafeReboot-!BASTOS_EXIT_CODE!
rem Une autorisation BootOnce ne doit jamais survivre a un arret de securite.
rem Sans cette neutralisation, un demarrage manuel ulterieur sur Recovery
rem pourrait reutiliser le jeton de la tentative refusee sans nouvelle confirmation.
if defined BASTOS_MEDIA del /f /q "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" >nul 2>&1
if defined BASTOS_MEDIA del /f /q "%BASTOS_MEDIA%\BASTOS-BOOT-MODE.txt" >nul 2>&1
if defined BASTOS_MEDIA if exist "%BASTOS_MEDIA%\BASTOS-AUTO-REINSTALL.token" (
  echo ECHEC SECURITE : le jeton BootOnce refuse n a pas pu etre neutralise.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
) else (
  echo Autorisation BootOnce neutralisee apres l arret non destructif.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
)
echo.
echo ================================================================
echo BASTOS RECOVERY S EST ARRETE AVANT DE MODIFIER WINDOWS.
echo Code : !BASTOS_EXIT_CODE!
echo Le PC ne redemarrera qu apres une pression sur une touche.
echo Photographiez cet ecran si le probleme se reproduit.
echo ================================================================
pause
wpeutil reboot
exit /b !BASTOS_EXIT_CODE!

:CRITICAL_REBOOT
if defined BASTOS_MEDIA echo Arret apres debut de preparation du disque, code !BASTOS_EXIT_CODE!. Attente avant redemarrage.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
call :WRITE_LAST_FAILURE "WindowsSetupOrDiskFailure" "!BASTOS_EXIT_CODE!" ""
if defined BASTOS_DIAG copy /y "%BASTOS_MEDIA%\BASTOS-Recovery.log" "!BASTOS_DIAG!\Recovery-WinPE.log" >nul 2>&1
if defined BASTOS_DIAG >>"!BASTOS_DIAG!\Recovery-Timeline.log" echo %DATE% %TIME% CriticalStop-!BASTOS_EXIT_CODE!
echo.
echo ================================================================
echo L INSTALLATION WINDOWS A ECHOUE APRES PREPARATION DU DISQUE.
echo Code : !BASTOS_EXIT_CODE!
echo Le journal est conserve dans BASTOS-Diagnostics.
echo Photographiez cet ecran avant de continuer.
echo ================================================================
pause
wpeutil reboot
exit /b !BASTOS_EXIT_CODE!

:CRITICAL_STOP
if defined BASTOS_MEDIA echo Arret apres installation de Windows : preparation pre-connexion incomplete, code !BASTOS_EXIT_CODE!.>>%BASTOS_MEDIA%\BASTOS-Recovery.log
if defined BASTOS_DIAG copy /y "%BASTOS_MEDIA%\BASTOS-Recovery.log" "!BASTOS_DIAG!\Recovery-WinPE.log" >nul 2>&1
echo.
echo ================================================================
echo BASTOS A BLOQUE LE PREMIER DEMARRAGE WINDOWS.
echo Le compte local sans mot de passe n a pas pu etre garanti.
echo Code : !BASTOS_EXIT_CODE!
echo Photographiez cet ecran. Aucune saisie de mot de passe n est requise.
echo Appuyez sur une touche pour redemarrer seulement apres avoir note le code.
echo ================================================================
pause
wpeutil reboot
exit /b !BASTOS_EXIT_CODE!
