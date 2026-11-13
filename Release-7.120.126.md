# BASTOS 7.120.126 — candidat de validation du compte local

Ce candidat corrige le parcours WindowsOnly/RufusLocal. Il ne constitue pas une
version validée pour une réinstallation réelle. Le laboratoire de réinstallation
du projet est absent de ce poste. Ne pas déployer avant validation complète en VM.

Le compte local sans mot de passe est créé pendant specialize avec NetUserAdd,
son mot de passe vide est appliqué avec NetUserSetInfo niveau 1003, puis une
authentification interactive LogonUser (type 2) est vérifiée. Le groupe
administrateurs est résolu par SID, indépendant de la langue Windows.
LocalAccounts est retiré d'oobeSystem pour éviter deux mécanismes concurrents.
Un compte existant sans reçu correspondant à son SID et au hash du profil est
refusé. Les politiques refusant un mot de passe vide produisent une erreur ;
elles ne sont pas désactivées. Aucun mot de passe temporaire n'est généré.

SetupComplete vérifie le compte sans changer son mot de passe. La création
initiale ne dépend donc ni de SetupComplete (restriction OEM), ni de FirstLogon.
FirstLogon nettoie AutoLogon avant les options de logiciels et ne touche plus
à l'authentification. Ses échecs restent des échecs de finalisation, sans changer
le compte. AutoLogonEnabled=false est accepté par le générateur, pour les essais
de connexion manuelle ; aucune nouvelle case n'a été ajoutée à l'interface.
Le menu actuel propose uniquement des comptes sans mot de passe. Les profils
contenant un mot de passe non vide sont explicitement refusés par ce parcours.

Les contrôles XML BootOnce et WinPE reconnaissent ce mécanisme et exigent le
worker de compte. Les médias préparés précédemment ne sont pas mis à jour par
ce paquet : ils doivent être préparés à nouveau dans la VM.

Integrate-WinRE reconnaît les états activés anglais et français au lieu de
rechercher uniquement « Enabled ». Cela corrige un faux échec dans le parcours
historique, sans établir la cause de l'échec de réinitialisation rapporté.
Les opérations de partitionnement et de migration WinRE restent inchangées.
Les parcours historiques BastosAutonomous/Build-BASTOS-ISO conservent leur
stratégie de création de compte : leur installation réelle n'est pas validée
par ce candidat. Ils ne doivent pas être considérés couverts par la correction.

Tests reproductibles depuis les sources, sous Windows PowerShell 5.1 :

```powershell
& .\Tests\Test-PasswordlessProvisioning.ps1
& .\Tests\Test-LocalAccountWorkerIsolated.ps1
& .\Tests\Test-ReinstallOptions.ps1
& .\Tests\Test-RufusQolParity.ps1
& .\Tests\Test-CleanBastos.ps1
```

Les tests du worker utilisent une copie instrumentée et des API SAM/ADSI
simulées, sans créer de compte sur l'hôte. La compilation des déclarations
natives vérifie leur syntaxe et leur disposition mémoire, sans les appeler.
La génération Recovery est testée pour Familial, Pro, Entreprise LTSC et IoT
LTSC, sans installer ces éditions et sans vérifier leur compatibilité finale.

Avant livraison : installation Windows complète en VM isolée sans réseau,
connexion avec BastOS puis avec un nom personnalisé, avec/sans AutoLogon,
déconnexion/reconnexion, redémarrage et nouvelle connexion, interruption de
FirstLogon, OEM si disponible, et réinitialisation Windows. Vérifier les noms
réels, LocalAccount-State.json, les journaux Windows Setup et la configuration
WinRE. Une sonde LogonUser n'est pas une preuve de connexion au Bureau après
redémarrage. Les essais avec un compte protégé nécessitent un autre parcours
explicitement pris en charge, absent du menu actuel.
