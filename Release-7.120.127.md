# 7.120.127 — correction après essai réel en VM

Le candidat 7.120.126 a échoué pendant une installation Windows complète en VM.
SetupComplete.log et UnattendGC/setupact.log montrent que le worker de compte
sort avec le code 1 avant sa propre journalisation : Join-Path reçoit un
PSScriptRoot vide dans la valeur par défaut du paramètre ProfilePath.
Le même appel Windows PowerShell 5.1 -File sans ProfilePath reproduit l'erreur
sur l'hôte, sans aucune modification de compte. Aucun reçu de compte n'existe.

7.120.127 initialise les chemins relatifs au script après le bloc param, dans
Initialize-BASTOS-LocalAccount, New-BASTOS-DesktopShortcut,
Test-BASTOS-InstalledWindows et Initialize-BASTOS-PreLogon. Le test invoque
désormais le véritable worker avec -File sans fournir ProfilePath et exige
d'atteindre la garde SYSTEM (code 31), plutôt qu'une erreur de liaison (code 1).

Cet échec confirme pourquoi la validation réelle est obligatoire. Il ne prouve
pas encore la cause exacte de l'incident initial de l'application 7.120.125.
Windows Setup a explicitement continué malgré le code non nul du worker ; le
code retour de RunSynchronous/WillReboot=Never ne constitue pas une barrière
fiable à l'accès initial. Ne pas décrire ce mécanisme comme un arrêt garanti
de Setup en cas d'erreur.

Le disque de la VM en échec et ses journaux sont conservés. Une nouvelle
installation doit être réalisée sur un disque virtuel neuf avec le candidat
127. Les limites de validation des parcours historiques et du garde général
de livraison restent celles décrites dans Release-7.120.126.md. Cette note ne
constitue pas un résultat positif de réinstallation, de connexion ou de reboot.
