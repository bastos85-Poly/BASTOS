# BASTOS 7.120 — options Windows adaptées de Rufus

## Choix d'horloge supplémentaires (7.120.125)

Les choix avancés exposent `disabledynamictick` et `useplatformclock` avec
Yes, No et suppression de la valeur. Le tick dynamique partage son mutex et
respecte les sauvegardes actives de « Timers pour les jeux » ; une sélection
individuelle est refusée tant qu'une sauvegarde de ce réglage est en attente.
Les valeurs sont relues après écriture. Un redémarrage est nécessaire.

## Mode du pointeur : courbes nulles (7.120.124)

Le mode facultatif « Courbes nulles » reproduit les deux valeurs binaires de
40 octets à zéro du fichier utilisateur. Son effet dépend de Windows et ne
prouve pas un déplacement 1:1. La sélection ne modifie rien ; l'application
demande confirmation et sauvegarde les courbes antérieures pour restauration.

## Menu contextuel classique (7.120.123)

Le profil de personnalisation propose la clé de registre utilisateur du menu
classique. « Restaurer les choix » supprime la clé propre au menu classique pour
revenir au menu récent, même si cette clé a été créée hors de Bastos. Le statut
confirme la clé, pas l'affichage effectif : certains builds Windows peuvent
ignorer cette méthode. L'Explorateur est redémarré après application.

## Progression des outils de réparation (7.120.120)

SFC, DISM et le vidage DNS transmettent l'état de démarrage puis les pourcentages
réellement émis par Windows via un rapport temporaire. La sortie Unicode de SFC
est décodée et le résultat final est journalisé. Le test réseau affiche l'étape
ICMP. CHKDSK reste interactif dans sa console et une réparation planifiée ne
peut être considérée terminée avant le prochain démarrage. Bootrec est expliqué
pour l'environnement de récupération, sans exécution depuis le bureau.

## Réparation Windows (7.120.119)

La page Réparation conserve les diagnostics existants et propose SFC /scannow,
DISM /RestoreHealth et le vidage DNS. CHKDSK /f ouvre une console interactive
pour le lecteur Windows ; elle indique si la réparation doit être programmée au
prochain démarrage. Le résultat ne doit pas être présenté comme une réparation
terminée avant ce démarrage. La page fournit les instructions pour bootrec
/fixmbr dans WinRE : cet outil concerne le code MBR, pas le démarrage EFI GPT.

## Écran : conservation du profil sans EXFIL (7.120.118)

Quand EXFIL est absent, « Enregistrer ce réglage » écrit le profil de gamma,
luminosité logicielle, contraste et vibrance dans `%LOCALAPPDATA%\BASTOS\DisplayCalibration.json`.
Fermer Bastos conserve alors le réglage appliqué ; un essai non enregistré
restaure le dernier profil. L'enregistrement installe un agent de session
utilisateur dans la clé Windows Run. Il démarre à chaque connexion et vérifie
le profil toutes les trois secondes, sans ouvrir la fenêtre de Bastos. Il
réapplique les valeurs si Windows, le pilote ou un jeu les réinitialise. Les
changements d'affichage pendant l'édition sont laissés à l'interface Bastos.
Les modes HDR ou certains jeux plein écran peuvent ignorer la rampe SDR :
aucune garantie de contrôle des couleurs dans tous les jeux.

## Bastos Power Plan (AMD)

Le menu Alimentation propose le plan d'origine de synez-os/power-synez sous
le nom « Bastos Power Plan (AMD) ». Bastos ne redistribue pas le fichier `.pow` :
à la première activation il télécharge la révision GitHub épinglée, contrôle
son SHA-256, l'importe avec son identifiant connu et le renomme. Si ce plan
existe déjà, Bastos conserve ses réglages. L'activation est explicite ; la
simple installation de Bastos ne change pas le plan actif. Le dépôt source
ne présente pas de licence de redistribution.

## Affinité des interruptions Bastos (candidat 7.120.113)

Dans « Optimisations > Processeur », quatre profils Bastos
reproduisent les valeurs fournies pour X3D, 6 cœurs, double CCD et Intel. Le
fichier `Manage-BASTOS-InterruptAffinity.ps1` est une implémentation distincte :
les CMD tiers ne sont ni exécutés ni redistribués. L'activation cible les GPU,
contrôleurs USB, cartes réseau et bus audio PCI détectés, puis règle la base RSS
des cartes réseau physiques actives. La désactivation retire uniquement
`DevicePolicy` et `AssignmentSetOverride` de ces catégories et règle la base RSS
des cartes physiques sur 0. Elle ne touche pas au mode MSI ni au NVMe.

Le calcul des processeurs logiques suit les profils fournis (coeur * 1 ou 2).
Les topologies hybrides ou asymétriques sont refusées, car ce calcul ne permet
pas d'identifier correctement leurs coeurs. Un redémarrage est nécessaire.
La lecture du profil X3D et les plans des quatre profils ont été testés sans
écriture sur l'hôte. La modification effective et son retour aux défauts
restent à valider dans une VM avant déploiement.

Cette livraison comprend le code source complet du programme WPF, les scripts
d'installation et les sources originales de Rufus utilisées pour l'adaptation.
Le générateur de l'expérience Windows de Rufus est porté dans
`InstallerScripts/Bastos.Rufus.psm1`. Le menu WPF et le moteur de déploiement
interne de BASTOS utilisent ce générateur. Le programme USB complet de Rufus
n'est pas exécuté sur le disque interne.

Rufus : https://github.com/pbatard/rufus
Révision : 875f221d5b4fa2c43cad1b85ae975d106964949f
Source adaptée : src/wue.c (CreateUnattendXml).
Licence de cette adaptation et du programme qui l'intègre : GPL v3 ou ultérieure,
dont le texte figure dans LICENSE.txt. Les logiciels indépendants regroupés dans
le kit BASTOS conservent leurs propres licences et notices.

Compilation sous Windows avec le SDK .NET 8 :

    dotnet publish BASTOS-Native.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish

Installer l'exécutable publié dans `Bastos.Native/BASTOS-Native.exe` du dossier
BASTOS, et les scripts d'InstallerScripts à la racine du même dossier.
Les modules doivent rester à côté des scripts PowerShell. Les autres outils et
fichiers du kit de restauration existant sont conservés.

Le menu enregistre un compte local sans mot de passe, le nom du PC, les options
de confidentialité et les suppressions OneDrive/Teams/Outlook/Copilot.
L'option de partition conserve D: BASTOS_RECOVERY, identifié par GUID GPT sur le
disque Windows interne, et remplace les autres partitions de ce disque.
La partition EFI peut également être conservée en décochant cette option.
Les partitions sont contrôlées à nouveau dans WinPE avant chaque suppression.
Le menu affiche un plan et demande une confirmation avant de lancer le
redémarrage de réinstallation. Le téléchargement et la préparation seuls
ne lancent pas l'effacement de Windows.

La création du compte écrit une valeur de mot de passe vide dans la réponse Windows.
BASTOS supprime l'ancien AutoLogon forcé et ne demande pas de changement de mot
de passe au premier démarrage. La connexion existante du PC n'est pas modifiée.
Les opérations de nettoyage sont exécutées sur la nouvelle installation.

Validation : compilation WPF, génération Pro et Enterprise LTSC, options
activées et désactivées, mot de passe vide, idempotence, validation des noms,
refus d'un GUID modifié, aperçu réel et plans D seul / EFI+D en lecture seule.
L'installation réelle de Windows reste à vérifier lors du prochain essai.

## Choix de l’édition Windows — 13 octobre 2026
La préparation Recovery affiche désormais une fenêtre BASTOS qui liste les éditions Windows 11 Client x64 réellement présentes dans install.wim ou install.esd. Le choix explicite est obligatoire, même si une seule édition est présente. Annuler interrompt la préparation avant modification du média ou des partitions. L’index et EditionId sont conservés dans BASTOS-MEDIA-STATE.json pour BootOnce ; le message final indique le choix.
Windows Familial, Pro, Entreprise LTSC, IoT Entreprise LTSC et les autres éditions Client x64 ne sont plus filtrées au profit de Pro. Les éditions N restent identifiées par leur nom réel. Aucun changement de licence ni activation n’est effectué. Les clés du fichier de réponses et les fichiers ei.cfg/PID.txt du média préparé sont retirés pour ne pas imposer une autre édition. Le nettoyage Panther cible l’index choisi et le cache exige le même index nettoyé. ESD est converti en WIM en conservant tous les index consécutifs. Le menu de création d’une ISO personnalisée est un parcours distinct, inchangé.
Validation : syntaxe sous Windows PowerShell 5.1, sélection Familial/Pro/Entreprise/IoT, refus d’index absent et de choix ambigu sans interface, refus Windows 10/ARM64, génération XML répétée avec index correct, sans clé ni AutoLogon, dialogue sélection/annulation et rendu. Catalogue WIM réel sur D: : Entreprise LTSC (1), IoT LTSC (2), IoT Subscription LTSC (3). Pas de nouvelle réinstallation, de redémarrage ni de conversion ESD réelle testée. Exécutable inchangé (7.120) : correction du worker PowerShell.

## 13 octobre 2026 — choix d’édition intégré au menu (7.120.1)
Le choix de l’édition Windows est maintenant directement dans « Compte, nom du PC, nettoyage et partitions… », sous le nom de l’ISO. « Préparer D: avec ces options » ouvre ce même menu. Le redémarrage affiche également le menu et confirme le nom de l’édition dans le plan final.
Le catalogue est lu en lecture seule dans install.wim/install.esd, sans demander les droits DISM pour afficher la liste. Seules les éditions Windows 11 Client x64 sont proposées. Aucune édition n’est présélectionnée au premier choix ; Enregistrer reste désactivé tant que la lecture ou le choix ne sont pas terminés. Un choix antérieur est retrouvé uniquement pour le même chemin et SHA-256 d’ISO, le même index, le même nom et le même identifiant d’édition. Une erreur de lecture laisse le menu ouvert avec un message et interdit l’enregistrement.
La fenêtre WinForms séparée a été retirée du worker : elle laissait le processus de préparation caché en attente à 10 %. Le worker de préparation consomme désormais WindowsImageIndex/WindowsEditionId/WindowsImageName/EditionIsoPath/EditionIsoSha256 enregistrés dans les options. Il revérifie le SHA-256 et les métadonnées DISM avant modification du média ; un choix absent, ancien ou divergent est refusé. Le choix est ensuite conservé dans le média Recovery pour BootOnce. Le nettoyage Panther conserve la correction ciblant l’index choisi ; les diagnostics automatiques et le compte sans AutoLogon sont préservés.
Validations : compilation/publish Windows x64 autonome, lecture réelle de l’ISO utilisateur avec ses trois éditions (Entreprise LTSC 1, IoT LTSC 2, IoT Subscription LTSC 3), tests WPF de liste/sélection IoT/enregistrement/réouverture/annulation/ISO modifié/erreur de lecture et rendu visuel, tests XML Familial/Pro/Entreprise/IoT répétés sans clé contradictoire ni AutoLogon, refus des anciens choix et des hash/chemins divergents. Aucun effacement, préparation réelle de partitions ni redémarrage déclenché. La réinstallation et une conversion ESD réelle restent à valider.
Cette section remplace le comportement temporaire de fenêtre séparée décrit plus haut. La source distribuée exclut les dossiers bin et obj. AssemblyFileVersion=7.120.1.0 ; version du kit conservée à 7.120 pour compatibilité avec l’installeur.

## Correction de comparaison DISM — 13 octobre 2026
Le choix IoT LTSC réel (index 2, IoTEnterpriseS) était refusé à 10 % parce que le catalogue XML NAME porte « Windows 11 IoT Enterprise LTSC 2024 », tandis que Get-WindowsImage -Index renvoie « Windows 11 IoT Enterprise LTSC ». La vérification de nom d’affichage a été retirée du contrôle de préparation. Le SHA-256 et le chemin de l’ISO restent contrôlés, ainsi que l’index et EditionId du catalogue DISM réel. Assert-BastosPreparedImageSelection centralise ce contrôle et décrit toute véritable divergence d’index/identifiant. L’interface et les options utilisateur enregistrées restent identiques.
Validations : métadonnées réellement lues par DISM dans l’ISO utilisateur, choix IoT enregistré accepté malgré la différence de nom, éditions Entreprise et Subscription et EditionId divergent refusés, SHA-256 réel contrôlé ; syntaxe et XML de quatre éditions répétés sans clé contradictoire ni AutoLogon. Aucune préparation destructive, réinstallation ou aucun redémarrage déclenché par Codex.

## Parcours simplifié et raccourci Bureau — 13 octobre 2026 (7.120.2)
La section « Choix de l’ISO — personnalisation facultative », son bouton de construction et sa progression ont été retirés de la page Réinstallation. L’ISO reste sélectionnable dans le bloc de méthode interne. Le téléchargement ne configure ni ne prépare plus automatiquement D: : il invite à configurer le module, puis à valider.
« Compte, nom du PC, nettoyage et partitions… » enregistre les options. « Valider les options et préparer D: » consomme ces options sans rouvrir le menu ; un choix manquant ou une autre ISO affiche une instruction de configuration. Le SHA-256 et les identités restent revérifiés par le worker. Le redémarrage utilise aussi les options enregistrées, sans rouvrir le menu, et conserve la confirmation du plan de partitions et de l’édition.
New-BASTOS-DesktopShortcut.ps1 est livré dans le payload WindowsOnly et appelé au premier démarrage du compte local, avant le marqueur de fin de première connexion. Il retrouve BASTOS_RECOVERY par label NTFS, GUID de partition et GUID de disque conservés, vérifie le SHA-256 de l’exécutable avec BASTOS-Build, et crée BASTOS.lnk sur le vrai Bureau du compte. Le raccourci ouvre Application\Bastos.Native\BASTOS-Native.exe de la partition conservée et utilise son icône, même si la lettre de Recovery change. Le profil WindowsOnly ne réintroduit ni AutoLogon, ni installation de logiciels/Radeon Tuner, ni optimisation automatique. Une erreur de raccourci est journalisée sans bloquer la connexion.
Validations : compilation native autonome, XAML, absence de la section facultative et d’appel au dialogue dans préparation/redémarrage, confirmation finale conservée, tests du menu d’édition, XML de quatre éditions et appel du raccourci dans le script de première connexion. Création d’un .lnk en dossier isolé avec cible/icône réelles sur Recovery, résolution des GUID réels et refus d’un mauvais GUID. Copie du worker dans un payload de test vérifiée. La réinstallation et la première connexion réelles restent à valider ; aucun redémarrage ni effacement lancé par Codex.

## 19 octobre 2026 — parité QoL Rufus 4.15 (7.120.58)
La case « Désactiver les applications suggérées et les promotions Windows » devient « Améliorations QoL de Rufus ». Elle applique désormais le bloc UNATTEND_QOL_ENHANCEMENTS complet de src/wue.c de Rufus v4.15 : six commandes specialize et quinze réglages à la première session. Les commandes specialize sont reprises sans changement : stratégie OneDrive, retrait des deux OneDriveSetup.exe du nouveau Windows, retrait provisionné et tous comptes d'Outlook et Teams. Les réglages de première session reprennent les valeurs Rufus : Fast Startup, Copilot, recherche en icône, recommandations, recherche Bing, actualités et flux, installation automatique du chat, contenu cloud, première ouverture Edge, davantage d'épingles et les mêmes raccourcis du menu Démarrer (VisiblePlaces binaire).
Les suppressions et réglages supplémentaires déjà proposés restent indépendants. Le bloc QoL ne désinstalle pas Microsoft News, ne supprime pas les dossiers Documents/Téléchargements et ne touche pas BitLocker. La case confidentialité conserve ProtectYourPC=3 comme Rufus ; elle ne promet pas zéro diagnostic sur toutes les éditions Windows.
Le profil d'installation enregistre RufusQolVersion=4.15 afin de distinguer le nouveau bloc des anciens profils de promotions. Les profils anciens gardent leur portée de contrôle. Le bilan relit les valeurs, les installateurs OneDrive et les paquets Outlook/Teams ; une preuve absente ou divergente n'est pas annoncée conforme. L'effet final des stratégies dépend de Windows, comme dans Rufus.
Validation : tests de parité indépendants contre la source Rufus embarquée, options cochées/décochées et anciens profils, 97 contrôles du moteur d'options sous PowerShell 5.1, 49 contrôles du bilan, compilation WPF x64 autonome et aperçu du menu. Aucune suppression effectuée sur l'hôte, aucune nouvelle image Windows reconstruite, aucune réinstallation ni aucun redémarrage d'essai. Validation réelle de première session encore à effectuer sur une nouvelle installation.
Source de référence QoL : https://github.com/pbatard/rufus/blob/v4.15/src/wue.c ; GPL-3.0-or-later. Copie originale : ThirdParty/Rufus/wue-qol-v4.15.c. Les sources adaptées et leurs tests sont inclus dans Source-Current.zip.
