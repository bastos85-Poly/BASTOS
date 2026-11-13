# BASTOS 7.120.92 — préparation initiale sans clé USB

Le parcours « Réinstallation facile Windows » affiche désormais « Vérifier la compatibilité » et « Préparer BASTOS_RECOVERY » avant le menu des options. Sur un PC compatible, la préparation valide l’ISO, demande confirmation, réserve 40 Go sur le disque Windows si nécessaire, crée D: BASTOS_RECOVERY et copie le média. Elle ne lance pas la réinstallation ni le redémarrage.

Si D: est occupé par un autre volume, la préparation est refusée avant la réduction de C:. L’utilisateur peut alors libérer D: sans que Bastos modifie le disque. Après préparation, il choisit « Compte, clavier et partitions… » puis vérifie le récapitulatif avant de lancer la réinstallation.

La création effective d’une partition et le démarrage WinPE doivent être validés en laboratoire Hyper-V avant d’être considérés comme éprouvés sur toutes les configurations matérielles.
