# Candidat 7.120.129 — Widgets de la barre des tâches

Le candidat 128 pouvait déclarer le contrôle Widgets réussi alors que le bouton météo restait affiché sur l'ISO 26H2 du laboratoire. Il choisissait DisableWidgetsBoard dès que le fichier ADMX contenait cette stratégie. Sa présence ne prouvait pas son application par le shell.

La stratégie établie AllowNewsAndInterests=0 est désormais toujours configurée lorsque DisableWidgets est demandé ; DisableWidgetsBoard reste complémentaire si disponible. Aucun changement de TaskbarDa, de permissions de registre ou de paquet Web Experience n'est nécessaire. Le compte rendu parle de configuration vérifiée, sans revendiquer une preuve visuelle.

Essai ciblé sur la VM installée avec 128 : ajout de la seule stratégie établie dans le registre invité à l'arrêt, puis démarrage. Le bouton météo précédemment visible a disparu. La réinstallation complète de 129 n'a pas été rejouée ; les preuves d'installation et de compte de 128 restent distinctes. Le garde général de livraison et le parcours sans USB restent non validés.
