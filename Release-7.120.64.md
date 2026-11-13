# 7.120.64 — services du profil propre

Uniquement dans Installation propre personnalisée BASTOS : désactivation de RetailDemo (démonstration magasin) et MapsBroker (cartes hors connexion, application Cartes retirée), en plus de DiagTrack déjà ciblé. Aucun autre service partagé modifié ; Mobile connecté, Assistance rapide, sécurité, maintenance, réseau, audio et jeux conservent leurs composants. Aucun gain de performances chiffré promis.

Application lors de la première ouverture de session, avec contrôle indépendant de l’état arrêté et du démarrage désactivé. Les services absents sont ignorés. Pas d’arrêt forcé des dépendances. Une erreur empêche de déclarer le profil conforme.

Sauvegarde initiale conservée dans %ProgramData%\BASTOS-ISO\Services-Before.json, bilan dans Services-Applied.json. Pour restaurer ces services après installation, dans Windows PowerShell administrateur :

```powershell
Import-Module "$env:ProgramData\BASTOS-ISO\Bastos.InstallationOptions.psm1" -Force
Restore-BastosCleanServices
```

La restauration rétablit les modes de démarrage, y compris automatique différé, et redémarre les services précédemment actifs. Le contrôle du profil propre signalera ensuite ces écarts volontaires. Aucune modification du Windows actuel et aucune préparation de média déclenchées.

Référence fonctionnelle : https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/services (rôles des services ; pas d’application en bloc des recommandations IoT à Windows de bureau).

Validation : 74 contrôles du profil avec services simulés, 97 contrôles des options ; compilation/publication x64. Aucune réinstallation réelle testée.
