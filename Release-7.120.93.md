# BASTOS 7.120.93 — choix de l’édition avant la préparation Recovery

Une ISO Windows contenant plusieurs éditions faisait échouer « Préparer BASTOS_RECOVERY » avant toute écriture sur le disque, car la validation sans interface exigeait un index d’édition. Le parcours lit désormais le catalogue de l’ISO, demande un choix explicite si plusieurs éditions sont disponibles, affiche ce choix avant confirmation et transmet l’index au moteur. Le contrôle du média vérifie ensuite que l’index préparé correspond au choix.

La préparation de la partition et le démarrage WinPE ne sont pas rejoués sur le PC de développement. La validation complète en laboratoire Hyper-V reste à effectuer.
