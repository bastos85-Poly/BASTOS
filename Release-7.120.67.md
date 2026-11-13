# 7.120.67 — finalisation de première connexion

Correction du bilan réel du 19 octobre 2026 (11 conformes, 4 écarts, 1 non vérifié).

- Identifiants COM GPO corrigés : classe EA502722, interface EA502723. Enregistrement et relecture réels de la stratégie Démarrer.
- Écritures registre via CreateSubKey/SetValue en vue 64 bits, sans recréation forcée des clés existantes. Préservation des valeurs et sous-clés ; types DWORD, chaîne, chaîne extensible et binaire vérifiés. Erreurs identifiées par chemin et nom.
- Widgets : valeur enabledValue lue dans la définition ADMX installée (0 sur le Windows 26300 actuel). La stratégie masque aussi le point d’entrée dans la barre des tâches ; TaskbarDa n’est plus forcé.
- Profil propre uniquement : anciennes valeurs AllowNewsAndInterests, EnableFeeds et ConfigureChatAutoInstall remplacées par la stratégie Widgets et ConfigureChatAutoInstall=false dans unattend. Parité Rufus stricte conservée et testée.
- Inventaire provisionné : repli sur PackageManager.FindProvisionedPackages si DISM est refusé. Chaque identité est vérifiée ; deux échecs restent un contrôle indisponible. Déprovisionnement via DeprovisionPackageForAllUsersAsync quand l’inventaire provient de cette API ; attente du résultat et contrôle indépendant final maintenus.

Validation : 25 contrôles de registre/COM et compatibilité (registre jetable réel, politiques et déprovisionnement simulés), 76 contrôles du profil propre, 96 contrôles des options, 84 contrôles de parité Rufus, 53 contrôles C# du bilan. Compilation autonome x64 avec catalogue de 115 scripts régénéré.

Réparation du Windows actuel effectuée avec sauvegardes : confidentialité/services/tâches ciblés, stratégies et registre, déprovisionnement réel de Dev Home. Rapport indépendant final : 16 contrôles conformes. Marqueur de finalisation réparée écrit seulement après vérification des 15 autres contrôles ; rapports antérieurs conservés dans les sauvegardes.

Limites : aucune nouvelle réinstallation complète testée, aucune préparation Recovery, aucun démarrage ni modification de partitions. Préparer à nouveau Recovery avant une nouvelle tentative ; les médias déjà préparés ne sont pas remplacés par la mise à jour de l’application.

Sources Microsoft :
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests
- https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findprovisionedpackages
- https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.deprovisionpackageforallusersasync
- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-configurechatautoinstall
