# Bastos 7.120.41 — pack de curseurs sombre

Personnalisation comporte une carte Curseurs sombres permettant d'activer le pack présent dans Assets/Cursor-Dark ou de restaurer le thème précédent. Le pack n'est pas activé automatiquement à l'installation de cette version. Les contrôles de vitesse, d'accélération et de courbes du pointeur restent distincts et inchangés.

Pack : **W11 Cursor Dark Free by Jepri Creations**. Auteur : https://www.deviantart.com/jepricreations. La licence et les crédits du dossier sont conservés et copiés avec les fichiers. Bastos n'exécute pas Install.inf et ne modifie pas l'installation automatique déjà existante : cette nouvelle commande est une activation manuelle par compte utilisateur.

Les 15 fichiers .cur et 2 fichiers .ani sont validés puis copiés dans un dossier persistant sous LocalAppData/BASTOS/Cursors, avec contrôle de leur empreinte. Le nom du modèle conserve son attribution à l'auteur. Les 17 rôles, le nom du modèle, sa source et son enregistrement sont sauvegardés avant écriture dans LocalAppData/BASTOS/CursorPack.json. Une réactivation garde l'original de la première activation.

La commande recharge les curseurs avec SystemParametersInfo(SPI_SETCURSORS). Si Windows refuse le rechargement de la session courante, l'interface précise que la configuration est enregistrée et qu'il faut rouvrir la session. La restauration remet les valeurs et types précédents, ou l'absence d'une valeur, et conserve les champs modifiés à l'extérieur de Bastos. Une sauvegarde partiellement restaurée reste disponible pour réessai. Les cibles autorisées sont limitées aux préférences de curseur prévues.

Validation : publication x64 et 10 contrôles en VM couvrant l'intégrité du pack et de la licence, la lecture sans modification, l'application/relecture, la répétition sans écrasement de sauvegarde, la copie persistante des fichiers, la restauration exacte, les modifications externes, l'absence de pack et l'affichage de la carte sans activation. La session de laboratoire peut refuser le rechargement graphique ; les tests de cette session vérifient les fichiers et préférences enregistrés, pas une observation du pointeur après redémarrage.

Le mode --cursor-smoke-test est réservé au laboratoire : il applique et restaure un thème de curseurs. Ne pas l'exécuter sur une session de production.
