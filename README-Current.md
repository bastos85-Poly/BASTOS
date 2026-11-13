# Source courante BASTOS — accueil matériel + Personnalisation + téléchargement Windows

Version 7.119 (12 octobre 2026) : réinstallation interne compatible avec Windows 11 Pro et Windows 11 Entreprise LTSC 2024 x64 (non N). Le worker utilise Windows PowerShell système et ses modules natifs pour éviter les erreurs Get-FileHash dues à un environnement PowerShell 7 hérité. L’édition et l’index sont détectés dans le WIM ; la clé Pro est retirée du fichier de réponses pour LTSC. Le choix d’édition est conservé au redémarrage Recovery. Action ValidateIso disponible pour vérifier un ISO sans modifier les partitions.

Version 7.118 (12 octobre 2026) : Optimisation > Réglages Windows > « Le bon plan pour votre utilisation » fournit Normal (équilibré), Performances élevées et Zoic Ultimate Performance (AMD). Le fichier Zoic corrigé est embarqué dans l'exécutable : le réglage Wi-Fi ACSettingIndex utilise désormais REG_DWORD au lieu de REG_BINARY, sans changer sa valeur. Les plans Windows manquants sont restaurés individuellement. L'application installe un plan absent lors du choix puis vérifie son activation. Les copies OEM et le kit de restauration installent les trois plans automatiquement ; le kit conserve le plan actif, tandis que la nouvelle installation Windows conserve son choix initial Normal. Le profil Zoic déjà importé sur ce PC est réutilisé sans créer de doublon.

Version 7.117 (11 octobre 2026) : livraison de reprise sur clé USB. Le kit `BASTOS-Restauration-2026-10-11-v7.117` contient la copie vérifiée de l’application, les états propres à cette installation, un installeur et un prompt de passation à Codex. Son installeur restaure l’application sans effacer les autres fichiers du PC ; l’image complète de Windows et les données personnelles extérieures à BASTOS n’en font pas partie.

Dans Logiciels, le bouton « Mettre à jour Radeon Tuner » vérifie les métadonnées officielles GitHub et signale si la version installée est déjà à jour. Une archive plus récente remplace la copie portable après contrôle de taille et SHA‑256 ; les fichiers du dossier `Settings` sont conservés. L’installation et la mise à jour créent le raccourci de bureau « Radeon Tuner ».

L’installation de Radeon Tuner lit maintenant la taille et le SHA‑256 de `RadeonTuner.zip` dans les métadonnées de la version `release` du dépôt GitHub officiel. Le téléchargement reste limité à ce dépôt et à cette archive ; un fichier dont la taille ou l’empreinte ne correspond pas est refusé. La taille figée de l’ancienne archive ne bloque plus les mises à jour publiées sous la même adresse.

Le téléchargement de l’ISO Windows charge explicitement le module de sécurité de Windows PowerShell avant de vérifier la signature Microsoft des composants WebView2. Cela évite qu’un module PowerShell 7 trouvé plus tôt dans `PSModulePath` bloque le téléchargement. La même sélection du module natif protège la préparation ADK, la construction ISO et la vérification de fin d’installation.

La création de l’ISO exporte désormais l’édition Windows choisie directement depuis l’ISO Microsoft montée. La copie préalable évite l’image `install.wim`/`install.esd`, ce qui supprime plusieurs gigaoctets d’écritures temporaires sans retirer les contrôles d’intégrité ni les autres fichiers d’installation.

Le bouton « Créer une ISO BASTOS personnalisée » ouvre une liste de suppressions facultatives, toutes cochées par défaut : 26 applications intégrées, OneDrive (y compris son paquet OneDriveSync) et les suggestions/contenus promotionnels Windows. Les applications décochées restent hors de la liste de retrait utilisée hors ligne et au premier démarrage. Les deux options après installation sont enregistrées dans `BASTOS-Removal-Options.json` dans l’ISO et respectées par les scripts d’installation et de réparation. Microsoft Edge n’est retiré qu’après le choix distinct d’un autre navigateur vérifié.

Réinstallation facile Windows détecte au démarrage la disposition de clavier active de la session Windows et la présélectionne. Le choix reste modifiable ; si l’utilisateur le change, les actualisations automatiques ne l’écrasent pas. Une disposition Windows installée mais absente des neuf choix prédéfinis est ajoutée à la liste. Le script de création ISO accepte ce code de disposition et l’inscrit dans le profil d’installation.

Réglages avancés > Écran propose cinq mires SDR intégrées : repères des noirs 0, 8, 16, 24, 32, 48, 64 et 96 puis niveaux fins 0–15 ; repères des blancs 192, 208, 224, 240, 248 et 255 puis niveaux fins 240–255 ; gamma et gris ; couleurs et saturation ; uniformité noir/gris/blanc. Chaque mire s’ouvre dans une fenêtre sans bordure en plein écran. Flèches gauche/droite pour avancer, H pour masquer les commandes, Échap pour quitter ; les touches 1 à 3 changent le fond de la mire d’uniformité. Les cases utilisent des valeurs RVB numériques exactes, sans réutiliser les captures compressées. Les mires seules ne changent aucun réglage ; les curseurs et les flèches appliquent les valeurs choisies. La mire des blancs indique le niveau à partir duquel la courbe logicielle écrête le blanc ; les différences 253–255 ne sont pas exigées à l’œil. Pour les noirs, ne pas forcer les niveaux 1 à 5 : si le fond 0 devient gris, revenir en arrière.

Cette source réunit le tableau de bord matériel validé du 08/09/2026 et la page Personnalisation (trois réglages système, compte administrateur et profils du menu Démarrer). Elle conserve les pages Game, souris, mémoire, réglages Windows et favoris logiciels de la branche récente.

Le profil matériel reste disponible immédiatement depuis le cache, puis BASTOS revalide le nom de la carte graphique en arrière-plan à chaque démarrage. Après le remplacement du pilote d'affichage générique Microsoft par un pilote AMD, NVIDIA ou Intel, le vrai modèle remplace automatiquement l'ancien nom mémorisé sans effacer le reste du profil.

Les favoris de la page Logiciels sont enregistrés localement et recopiés automatiquement dans `BASTOS_RECOVERY\BASTOS-USER-DATA`. Après une réinstallation de Windows par BASTOS, ils sont réimportés au premier lancement, même si Windows attribue une autre lettre à la partition Recovery.

Optimisations > Réglages Windows expose les réglages généraux adaptés du fichier open source `Performance.cs` fourni par l'utilisateur : limitation des applications en arrière-plan, regroupement des hôtes de services selon la RAM, priorité des applications actives, profil MMCSS/jeu et limite WebDAV. Optimisations > Clavier rassemble « Réduire la latence du clavier » (délai et vitesse de répétition) et « Désactiver les raccourcis clavier d'accessibilité ». Chaque fonction détecte ses valeurs réelles, sauvegarde avant la première modification, vérifie l'application et restaure exactement les valeurs antérieures. Le réglage `Win32PrioritySeparation` 38 (`0x26`) partage volontairement la même valeur système que le Quantum avancé.

Optimisations > Carte graphique expose les huit fonctions adaptées du fichier open source `Gpu.cs` fourni par l'utilisateur : quatre réglages AMD, deux NVIDIA et deux Intel. BASTOS identifie les clés de classe graphique par fabricant et identifiant PCI, applique uniquement les réglages compatibles, sauvegarde les valeurs existantes et permet leur restauration exacte.

Dans Optimisation > Carte graphique, le bouton « Analyser la carte graphique » utilise un périmètre dédié : uniquement `Win32_VideoController` et les pilotes signés de classe `DISPLAY`. Il ne parcourt plus la carte mère, le processeur, la mémoire, les disques, le réseau, l’audio ni l’ensemble des périphériques PnP.

Dans Applications > Explorateur Internet, un seul navigateur peut être sélectionné. Après avoir installé et vérifié le navigateur choisi, BASTOS supprime les autres navigateurs gérés, leurs profils locaux et Microsoft Edge Stable, puis vérifie les résidus détectables. Le moteur Microsoft Edge WebView2 est conservé pour les applications Windows qui en dépendent. Le parcours affiche quatre étapes de progression et signale toute suppression incomplète. Opera utilise `Opera.Opera` et une icône transparente issue de son installation locale.

Optimisations propose une catégorie « Sécurité et confidentialité » avec treize modules adaptés du fichier open source `SecurityAndPrivacy.cs` fourni par l'utilisateur. Chaque module est volontaire, sauvegarde les valeurs Registre et l'état des tâches concernées, et propose une restauration individuelle. Une identité visuelle dédiée est fournie dans `Assets\Security-Privacy.png`.

Optimisations > Réglages Windows expose « Optimisations plein écran », adapté uniquement de la classe `FullscreenOptimizations` du fichier open source `Gaming.cs` fourni par l'utilisateur. Activer applique les quatre valeurs Windows à `0`; désactiver applique `1`, `2`, `2`, `1`, avec vérification immédiate de l'état réel.

Le catalogue Audio reconnaît Equalizer APO et Peace. Le worker spécial télécharge les versions officielles contrôlées (Equalizer APO 1.4.2, Peace 1.6.9.11), respecte leur dépendance et confirme l’installation dans Windows.

Pour Windows 11 26H2 Insider, « Télécharger Windows depuis Microsoft » ouvre la page officielle, localise visuellement le contrôle « ME » même lorsque Microsoft ne publie aucun identifiant DOM exploitable, puis l'active avec un événement souris WebView2 réel. Après la connexion, BASTOS laisse obligatoirement le choix de l'édition ou du build dans la page officielle. L'automatisation est suspendue sur les pages d'identification afin de ne jamais activer « Sign-in options » ou « Créer un compte ». Après la confirmation manuelle, BASTOS sélectionne la langue configurée, récupère le lien Microsoft, masque la fenêtre Web et reprend le téléchargement avec sa propre progression. Les identifiants ne sont ni lus ni conservés par BASTOS.

Le formulaire de langue conservé mais masqué par la page Microsoft n'est jamais interprété comme l'étape active : BASTOS reste sur le choix de l'édition jusqu'à sa confirmation, puis reprend sur le formulaire de langue visible.

La bibliothèque ISO recense l'ISO BASTOS de `D:\ISO` et les ISO Microsoft présentes dans le dossier Téléchargements. Le bouton « Ouvrir le dossier ISO » ouvre le dossier réel de l'ISO sélectionnée, afin qu'une ISO source située dans Téléchargements ne soit plus prise pour une entrée fantôme.

Le kit livré ne contient plus les aperçus logiciels abandonnés, l'ancien jeu d'icônes `Assets\Software`, le plan d'alimentation vide, l'ancien paquet ExplorerPatcher, la copie RAMMap devenue inutile ni les anciennes variantes graphiques. Les scripts de construction et de réparation n'exigent plus ces ressources. Les documents de travail et l'ancien prompt de reconstruction ont également été retirés ; ce fichier reste l'unique repère de source courante.

Source de référence distribuée : D:\Application\Bastos.Native\Source-Current.zip.
Ne pas reconstruire depuis les anciens dossiers de travail de septembre : ils ne contiennent pas toutes ces fonctions.

Les trois copies livrées : D:\Application ; D:\sources\$OEM$\$1\ProgramData\BASTOS-ISO ; C:\ProgramData\BASTOS-ISO.
Tout changement de l'exécutable doit mettre à jour les manifestes SHA256, les manifestes JSON et leurs références BASTOS-Build. Conserver les entrées sans rapport avec la modification.

Tests : --smoke-test vérifie la page d'accueil par défaut, le contrôle du schéma PC, les trois réglages de Personnalisation et le profil du menu Démarrer. Le rendu de l'accueil est exporté dans %TEMP%\BASTOS-HardwareHome-Smoke.png.

## Contrôle de l'image avec EXFIL

Dans Réglages avancés > Écran, les curseurs gamma, luminosité, contraste et vibrance agissent via la courbe gamma Windows et AMD ADL. Dans les mires plein écran, ↑/↓ règle respectivement la luminosité (noirs), le contraste (blancs), le gamma et la vibrance (couleurs). Au premier changement, EXFIL est mis en pause pour éviter que sa réapplication périodique contredise BASTOS. Les modifications sont des essais provisoires : « Voir le bureau » réduit BASTOS pour juger une image ordinaire, « Enregistrer ce réglage » crée ou met à jour le profil EXFIL « BASTOS Écran », et « Revenir au dernier profil enregistré » ou R dans la mire annule l'essai. Si BASTOS ferme avec un essai non enregistré, il restaure le profil enregistré et relance EXFIL. Le gamma 1,00 signifie absence de correction logicielle supplémentaire, pas un gamma mesuré de l'écran. Une sonde reste nécessaire pour mesurer la teinte réelle. L'interface AMD et la formule gamma sont adaptées du projet EXFIL sous licence MIT.

Pour repartir d'une image sombre, « Retrouver une image neutre » applique gamma logiciel 1,00, luminosité logicielle 0,00, contraste 1,00 et vibrance AMD par défaut. Dans cette formule EXFIL, augmenter le curseur gamma éclaircit les tons moyens ; le chiffre 2,2 d'un menu de moniteur ne doit pas être recopié dans ce curseur. La mire gamma montre les niveaux RVB exacts 0, 64, 128, 192 et 255, ainsi qu'un dégradé qualitatif. Elle ne mesure pas la courbe physique de l'écran.

## Licence du code EXFIL adapté

MIT License

Copyright (c) 2026 Blazzer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

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

## Correctif navigateur 7.120.4 — 13 octobre 2026

Le journal de la session suivant la réinstallation réussie montre le code Windows
1223 pour les suppressions des anciens navigateurs : la demande administrateur
a été annulée. Brave était installé dans le profil utilisateur et Edge conservé.
Le remplacement groupe désormais les suppressions nécessitant l'administration
dans un seul worker élevé. Une annulation interrompt ce nettoyage et explique
comment le reprendre. Un navigateur standard déjà présent n'est pas réinstallé
lors de cette reprise. Aucun succès complet n'est annoncé si un ancien navigateur
reste détecté. Le navigateur sélectionné et WebView2 sont contrôlés.

La demande Windows reste nécessaire : BASTOS ne contourne pas un refus d'élévation.
Les tests de workers simulés vérifient succès groupé, doublons, sélection protégée,
navigateur inconnu, navigateur choisi absent, échec et rapport manquant.
La compilation autonome .NET 8 et le test WPF des 12 pages ont passé.
Verification du provisionnement partielle : un inventaire DISM refuse est un avertissement explicite pour les futurs comptes, sans masquer une erreur de suppression. L'absence des executables et des enregistrements Edge Stable actuels et la presence du runtime WebView2 sont requises pour un succes. Un echec du desinstalleur initial peut etre recupere par un nettoyage cible verifie. WebView2 absent avant le nettoyage : aucune suppression n'est effectuee.


## Pilotes graphiques 7.120.5 — 14 octobre 2026

Mise à jour matériel dispose du bouton « Lancer NVIDIA / AMD / Intel », conservé
après analyse. Il ouvre une console Windows PowerShell visible avec élévation
Windows et lance le menu FR33THY demandé par l'utilisateur. Le script courant
est téléchargé depuis le dépôt Ultimate à chaque lancement et exécuté depuis
un fichier pour préserver PSCommandPath et les entrées interactives Read-Host.
Une erreur de téléchargement ou de syntaxe reste affichée ; une annulation UAC
est signalée dans BASTOS. Le message « menu ouvert » ne certifie pas l'installation.

Source : https://github.com/FR33THYFR33THY/Ultimate/blob/main/5%20Graphics/2%20Driver%20Updated%20Install.ps1
NVIDIA télécharge son pilote ; AMD lance son installeur de détection ; Intel ouvre
une page officielle. Le comportement et la compatibilité suivent le script amont.
Validation : compilation WPF autonome et syntaxe PowerShell. Le smoke test de
l'interface est bloqué par l'accès au registre Run refusé dans le bac à sable
(initialisation Bastos Game déjà présente avant cette intégration).
Aucun pilote n'a été installé pendant la validation de cette intégration.
## Catalogue ISO 7.120.6 — 14 octobre 2026

Réinstallation facile Windows > Profil de l'installation propose la famille,
la version/édition, la langue et l'architecture des ISO complètes répertoriées
sur les quatre pages Windows 11, Windows 10, LTSC/LTSB et Windows Server de
massgrave.dev. Le relevé embarqué comporte 500 ISO ; Actualiser le catalogue
relit ces quatre pages, en conservant la rubrique précédente en cas d'erreur.
Les langues et architectures dépendent de la version sélectionnée. Un choix
de disque/fichier apparaît quand plusieurs ISO répondent aux mêmes critères
(notamment les deux CD de Windows Server 2003 R2). Les fichiers DVP sont exclus.

Le bouton Télécharger ouvre le fichier choisi chez l'hébergeur dans le navigateur
par défaut, pour permettre sa validation éventuelle. Il ne lance pas d'activation.
Les hébergeurs relevés sont ZeroFS et Buzzheavier. Les fichiers enregistrés dans
Téléchargements sont détectés au retour dans Bastos. La liste locale accepte
également les ISO Windows anciennes de moins de 2 Go. Le navigateur gère le
transfert et sa progression. Voir la rubrique source permet de retrouver les
autres liens proposés sur le site. Le catalogue ne certifie ni l'authenticité
des images hébergées ni leur compatibilité avec le moteur de réinstallation.

Le clavier et les formats régionaux se règlent dans « Compte, nom du PC,
nettoyage et partitions », sous « Compte, PC et clavier ». Les options enregistrées
sont relues au démarrage. Le clavier reste indépendant de la langue de l'ISO.
Le moteur interne conserve ses vérifications Windows 11 x64 Pro / Enterprise LTSC.
Les autres versions sont proposées au téléchargement et à l'utilisation avec Rufus.

Validation : compilation WPF autonome, relecture en ligne des quatre rubriques,
parcours des 500 ISO, choix affichés après changement de famille, sauvegarde du
clavier et des formats indépendamment de la langue de l'image, smoke test des
12 pages et contrôle visuel des écrans Catalogue et Options. Le mode smoke test
ne configure pas le démarrage de Bastos Game et ne prépare pas le gestionnaire
de paquets. Aucun ISO complet téléchargé et aucune partition modifiée pendant
les vérifications. Le bouton des pilotes graphiques 7.120.5 est conservé.
## Langue IoT LTSC 7.120.7 — 14 octobre 2026

Windows 11 IoT Enterprise LTSC 2024 est accessible quelle que soit la langue
choisie auparavant. Sélectionner cette version impose Anglais (États-Unis)
et désactive la liste des langues, avec une explication à l'écran. Le fichier
choisi reste l'ISO anglaise réelle du catalogue. Le clavier et les formats
régionaux dans les options du compte restent indépendants.

En quittant cette version, le choix de langue précédent est restauré lorsqu'il
existe dans la nouvelle version. Les autres éditions gardent leur choix de langue.
Les liens et le catalogue des 500 ISO restent identiques.

Validation : compilation WPF autonome et smoke test des 12 pages. Sélection IoT
testée depuis les 38 langues de Windows 11 ; anglais imposé, champ désactivé,
fichier en-US choisi, refus d'une autre langue et restauration du choix précédent.
Les 500 ISO restent sélectionnables. Aucun téléchargement d'ISO, installation
de pilote ou changement de partition effectué pendant les vérifications.
## LTSC visible dans Windows 11 — 7.120.8 — 14 octobre 2026

La fenêtre ouverte de BASTOS 7.120.7 a été inspectée : la liste de versions
de la famille Windows 11 n'affichait que les cinq éditions Consumer, Business
et IoT GAC. Les éditions LTSC étaient dans une autre famille, difficile à repérer.

Les familles visibles sont désormais Windows 11, Windows 10 et Windows Server.
Windows 11 contient directement IoT Enterprise LTSC 2024 et Enterprise LTSC 2024,
en tête de sa liste de versions. Windows 10 regroupe aussi LTSC et LTSB.
Le catalogue embarqué et les liens conservent leurs 500 ISO, sans duplication.
L'anglais est toujours imposé et le champ désactivé pour IoT LTSC 2024 ; la
langue précédente est restaurée lors du choix d'une autre version compatible.

Validation : compilation autonome, smoke test des 12 pages et des 500 ISO dans
les trois familles, présence des deux éditions LTSC 2024 dans Windows 11,
sélection IoT depuis les 38 langues et conservation du clavier indépendant.
Aucun téléchargement d'ISO ni changement de partition effectué pendant les tests.
## Libellés des éditions Windows — 7.120.9 — 14 octobre 2026

Le mot Consumer est remplacé dans les listes de versions et le résumé de
l'ISO sélectionnée par un libellé compréhensible, par exemple :
Windows 11 26H2 — Famille / Pro / Éducation.
Ce libellé s'applique également aux autres versions Windows 10 et Windows 11
du même type. Les références internes, fichiers ISO et liens sont conservés.
L'édition exacte à installer reste sélectionnable dans les options du compte.

Validation : compilation autonome et smoke test existant des 12 pages et
des 500 choix d'ISO. LTSC et le verrouillage anglais d'IoT restent fonctionnels.
## Langue modifiable et version adaptée — 7.120.10 — 14 octobre 2026

Le choix de langue reste actif pour toutes les versions du catalogue, y compris
Windows 11 IoT Enterprise LTSC 2024. Sélectionner IoT LTSC 2024 choisit son ISO
anglaise. Choisir ensuite une autre langue sélectionne automatiquement une ISO
Famille / Pro / Éducation disponible dans la langue demandée.

La règle s'applique à toute version ne disposant pas de la langue demandée.
Bastos privilégie une version standard de la même famille Windows ; si cette
famille ne possède pas d'ISO standard (Windows Server), il choisit Windows 11.
La langue, l'architecture, le résumé et le lien correspondent au fichier réel.
Changer de version réutilise la langue préférée si elle est disponible ; sinon
une langue existante de cette version est choisie, sans bloquer la liste.
Un message signale les changements automatiques de version. Le clavier et les
formats régionaux restent configurables séparément dans les options du compte.

Validation : compilation WPF autonome, smoke test des 12 pages, 500 ISO toujours
accessibles, sélection IoT depuis les 38 langues et 615 changements de version
depuis une langue indisponible. Aucun ISO téléchargé ni disque préparé pendant
ces vérifications. Cette règle remplace le verrouillage décrit en 7.120.7.
## Retrait du test Recovery — 7.120.11 — 14 octobre 2026

Le bouton « Tester Recovery sans réinstaller » est retiré de la page
Réinstallation facile Windows, à la demande de l'utilisateur. Sa commande et
son gestionnaire d'interface sont également supprimés. Les actions de préparation
de D: et de redémarrage vers BASTOS restent disponibles.

Validation : compilation WPF autonome et contrôle des empreintes après déploiement.

## Premier renforcement du moteur — 7.120.12 — 14 octobre 2026

Le téléchargement de Rufus et les analyses matérielle / graphique utilisent
VerifiedOperationService et un OperationResult commun : identifiant unique,
état, phase, dates, code de sortie, vérifications, erreur et journal associé.
Les états distinguent succès vérifié, analyse partielle, échec, annulation
administrateur, délai dépassé avec arrêt confirmé et résultat non confirmé.

Les deux workers PowerShell publient leur rapport atomiquement via le module
Bastos.Operation.psm1. Le rapport porte SchemaVersion=1 et l'identifiant demandé.
Un code de sortie zéro sans rapport, un rapport d'une autre opération ou un
rapport mal formé ne permet jamais de déclarer une réussite. Les erreurs de
collecte et de recommandations sont signalées comme analyse partielle.

Rufus : provenance GitHub officielle conservée, taille comparée aux métadonnées
de version, signature Authenticode Akeo Consulting contrôlée par Windows puis
empreinte SHA-256 relue par C# et comparée au fichier signé. Le fichier ne peut
être ouvert après un résultat absent, invalide ou non vérifié. La préparation USB
réutilise le même téléchargement vérifié ; son lancement existant conserve le
contrôle de signature. Le calcul d'empreinte PowerShell utilise .NET pour éviter
les échecs d'autochargement de Get-FileHash entre PowerShell 7 et Windows PowerShell.

Les actions migrées refusent un second lancement identique pendant leur
exécution. Elles demandent l'arrêt de leur processus en cas de délai dépassé et
vérifient sa fin. Si l'arrêt ne peut pas être confirmé, la relance de cette action
reste bloquée dans la session ; vérifier l'état du processus avant de redémarrer
l'application. Aucune relance automatique. Les actions Recovery existantes ne
sont pas migrées et ne reçoivent pas cette politique d'arrêt forcé.

Les journaux structurés et rapports restent dans %LOCALAPPDATA%\BASTOS\Logs\Operations,
accessibles depuis le dossier des rapports de la page Journal. Les messages
d'erreur indiquent une référence et une action utile ; les détails techniques
restent dans le journal associé. Les anciens services ne sont pas tous migrés.

Validation : 57 contrôles automatisés du moteur, dont rapports absents/invalides,
identifiants incohérents, annulation UAC simulée, processus réellement dépassant
le délai, refus de doublon et preuves de téléchargement invalides. Téléchargement
réel de Rufus signé sans exécution, analyses matérielle et graphique réelles,
protocole partagé testé sous Windows PowerShell 5, compilation autonome et smoke
test des 12 pages, 500 ISO et nouveaux adaptateurs matériels (19 composants).
Aucune installation de pilote, préparation de partition ou réinstallation effectuée.

## Moteur vérifié 7.120.13 — étape 2 — 15 octobre 2026

Le nettoyage TEMP et l'ouverture des pages officielles de pilotes passent désormais
par le moteur commun : identifiant d'opération, rapport JSON atomique, contrôles
de cohérence, états explicites et journal conservé dans Logs/Operations.
Les doublons de lecture des rapports ont été retirés du service de l'application.
La progression du nettoyage et de l'analyse matérielle utilise un module commun.

Nettoyage : l'estimation porte seulement sur les fichiers de plus de 24 heures.
Les fichiers récents, modifiés depuis l'analyse, verrouillés et les chemins redirigés
sont conservés. Les ancêtres des cibles sont contrôlés avant parcours et suppression.
Chaque suppression est suivie d'un contrôle d'absence. Le bilan compte les octets
des fichiers effectivement supprimés, sans promettre le gain physique sur le disque.
Les erreurs d'accès produisent un résultat partiel avec les compteurs concernés.
Un délai dépassé ne provoque pas d'arrêt forcé du nettoyage ; une nouvelle exécution
identique est bloquée tant que l'arrêt n'est pas confirmé (dans la session courante).

Pilotes : HTTPS, domaine autorisé, absence d'identifiants dans l'URL, port standard
et correspondance du lien final sont contrôlés. L'application confirme uniquement
la transmission au navigateur, pas le chargement de la page ni une installation.
Les rapports sont conservés pour comprendre un refus ou un échec.

Validation : 73 contrôles du moteur et des workers, dont fichiers récents/verrouillés,
jonction vers une cible extérieure, compteurs incohérents, liens trompeurs et ouverture
simulée du navigateur. Les essais de suppression utilisent des fichiers de test isolés.
Compilation WPF autonome réussie. Smoke test des 12 pages, 500 ISO, 615 bascules
de langue et analyses matérielle/graphique réelles réussi. Aucun nettoyage des fichiers
personnels ni installation de pilote effectué pendant les tests.

Les résultats partiels ou non confirmés du nettoyage apparaissent en orange dans l'interface.

## Moteur vérifié 7.120.14 — étape 3 — 15 octobre 2026

Le moteur commun peut exécuter une action C# directement, en plus des workers
PowerShell. Les deux parcours partagent l'identifiant, le journal préalable,
le refus des doubles clics concurrents, le rapport atomique, les vérifications
et les états finaux. La progression reste inférieure à 100 % avant validation.
Le journal distingue Native et PowerShell ; une action C# ne reçoit pas de faux
code de sortie de processus. Les erreurs attendues ont un code et un message
compréhensible ; une exception inattendue produit un résultat non confirmé.

L'ouverture des pages officielles de pilotes ne démarre plus PowerShell.
Le service C# lit la même liste de domaines, contrôle HTTPS, hôte, port et absence
d'identifiants, résout le lien NVIDIA puis transmet l'adresse à Windows. La recherche
est toujours copiée si le presse-papiers est disponible. Un refus intervient avant
l'ouverture et la copie. Le rapport conserve le résultat de transmission ; Bastos
ne prétend pas avoir chargé une page ni installé un pilote. Le worker historique
reste distribué pour compatibilité, mais l'interface ne l'appelle plus.

Le test réseau utilise maintenant Ping de .NET au lieu de lancer ping.exe.
Huit essais vers 1.1.1.1 avec un délai de 1 seconde par essai alimentent un rapport
structuré. Le moteur contrôle cible, paramètres, ordre, nombre de réponses, états
et latences avant de calculer min./moyenne/max. et pourcentage de perte.
Les pertes produisent un résultat partiel orange, sans conclure à une panne Internet
sur la seule absence de réponses ICMP. Les erreurs d'envoi ont un message distinct.
Le résumé s'affiche dans Bastos ; le détail est conservé dans Logs/Operations.

Validation : 103 contrôles du moteur, des workers existants et des nouvelles actions
C#, dont journal avant action, rapport corrélé, erreurs explicites, exceptions,
doubles clics, progression, liens trompeurs, erreur navigateur, presse-papiers
indisponible et résultats réseau complets/partiels/incohérents. Ping local réel.
Compilation WPF autonome réussie. Les ouvertures de navigateur des tests sont
simulées ; aucun pilote installé et aucun nettoyage de fichiers personnels effectué.

Smoke test réussi : 12 pages, 500 ISO, 615 bascules de langue, analyses matérielle et graphique réelles, refus d'un lien pilote de test et huit mesures ICMP réelles vérifiées avec huit réponses.

## Moteur vérifié 7.120.15 — étape 4 — 15 octobre 2026

La préparation de WebView2 rejoint le moteur commun : journal créé avant lancement,
identifiant corrélé, rapport JSON atomique conservé, progression commune et résultat
vérifié. Le service de réinstallation ne supprime plus le rapport ni ne déclare une
installation réussie sur la seule fin d'un processus. Les messages distinguent lien
refusé, téléchargement non validé, signature invalide et échec d'installation avec
son code lorsque disponible. Le worker ne reçoit aucune politique d'arrêt forcé.

La lecture C# des versions est regroupée dans WebView2RuntimeService. Elle examine
les emplacements utilisateur/machine dans les vues de registre 32/64 bits, rejette
les valeurs nulles, invalides ou égales à 0.0.0.0 et retient la version la plus récente.
Le worker utilise la même règle de présence. Une seconde lecture C# indépendante
vérifie le résultat ; une mise à jour parallèle vers une version supérieure est acceptée.
Le critère est la détection de version enregistrée, pas un test de toutes les fonctions
WebView2. Référence Microsoft :
https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution

Si WebView2 est déjà présent, sa vérification passe directement en C#, avec journal,
sans lancer PowerShell ni un installateur. Cette détection peut aussi constater la
fin d'une installation en arrière-plan sans relancer l'installation initiale.

Le bootstrapper conserve le lien Evergreen officiel fixé. Les redirections doivent
aboutir en HTTPS sur microsoft.com/msedge.net. Taille reçue/annoncée, signature
Authenticode Microsoft Corporation, en-tête exécutable et empreinte SHA-256 sont
contrôlés. C# relit l'empreinte du fichier signé et son emplacement après installation.
Les fichiers téléchargés sont conservés dans un cache propre à chaque opération,
pour permettre la vérification et le diagnostic ; ils ne sont pas supprimés alors
qu'un installateur pourrait encore les utiliser.

Une installation déjà active est signalée avant un nouveau lancement. Si la version
n'apparaît pas dans le délai de vérification, le résultat reste non confirmé, y compris
lorsque le bootstrapper a pu passer la main à Edge Update. Le rapport distingue
fin du worker et fin d'action non confirmée. Aucun installateur n'est arrêté de force.
Une relance identique est bloquée dans la session ; une présence nouvellement détectée
peut être recontrôlée directement. Ces verrous ne constituent pas un système complet
de reprise des installations après redémarrage de Bastos.

Validation : 132 contrôles. Téléchargement réel du bootstrapper Microsoft signé,
empreinte relue et comparée, sans exécution. Scénarios Windows PowerShell 5 avec
registre et lancement simulés : déjà présent, lien refusé, installation active,
installation détectée, code d'échec et signature invalide. Présences absentes ou
incohérentes, preuves de fichier modifiées et refus de relance testés. Les tests
simulent l'installation et n'installent pas WebView2 sur le poste.
Compilation WPF autonome réussie. Les actions de partitionnement et Recovery
restent sur leur parcours existant.

Smoke test réussi : 12 pages, 500 ISO, 615 bascules de langue, analyses matérielle/graphique réelles, détection WebView2 en lecture seule (absent), refus d'un lien pilote de test et huit mesures ICMP réelles vérifiées.

## Fiabilisation Windows ADK et construction ISO — 7.120.16 — 15 octobre 2026

La préparation ADK et la construction ISO utilisent VerifiedOperationService :
journal préalable, identifiant unique, rapport atomique conservé, contrôle de
code de sortie et du rapport, vérification finale et refus de doublons.
Le parcours ne considère plus un code de sortie zéro ou un fichier présent comme
une preuve suffisante. Les deux anciens lecteurs de progression et de rapport ont
été supprimés du service de réinstallation. Les sept étapes restent affichées,
et 100 % n'est publié qu'après la vérification C#. Une phase explicite de contrôle
est affichée pendant les relectures d'intégrité. Une annulation du constructeur
est distinguée d'un échec. Aucun arrêt forcé n'est appliqué à ADK, DISM ou Oscdimg.

ADK : Bastos.Deployment.psm1 regroupe les lectures et vérifications utilisées par
l'installateur et le constructeur. La version des Outils de déploiement est relue
dans Windows, Oscdimg doit se trouver dans un emplacement ADK prévu, être signé
Microsoft Corporation, et son empreinte est relue indépendamment par C#.
Les vérifications sont reprises avant son utilisation pour éviter un rapport périmé.

Pour la base 10.1.26100.2454, le fichier KB5101684-applied.ok n'est plus utilisé
comme preuve. L'archive Microsoft KB5101684 est identifiée par l'empreinte SHA-256
relevée sur son téléchargement officiel du 15 octobre 2026. Les MSP portent une
signature Microsoft ; leur PatchCode et leurs ProductCode cibles sont lus via
Windows Installer. Les composants applicables doivent être réellement appliqués
ou supersédés (états 1 ou 2), vérifiés par l'API MSI dans le worker puis dans C#.
Aucun composant applicable attesté signifie un résultat non confirmé/échoué,
pas « déjà intégré ». Les journaux msiexec restent dans le cache ADK/Logs.
Un redémarrage demandé par l'installateur est consigné avec l'heure du dernier démarrage Windows. La suite reste bloquée tant qu'un nouveau démarrage n'est pas constaté ; rouvrir Bastos ne suffit pas. Ce reçu sert à bloquer une reprise prématurée, jamais à prouver une installation.

La révision connue 10.1.26100.9457 est traitée séparément : Bastos vérifie la version
et l'outil installé, mais ne revendique pas l'application du correctif de la base
2024 sur cette autre révision. Une version supérieure quelconque ne prouve plus
l'intégration d'un correctif. Les révisions inconnues sont signalées explicitement.
Cette politique est figée aux références vérifiées aujourd'hui et devra être mise
à jour après validation d'une nouvelle révision ou d'une archive Microsoft republiée.
Références :
https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-servicing
https://learn.microsoft.com/en-us/windows/win32/api/msi/nf-msi-msigetpatchinfoexw

ISO : le nom de sortie est unique et l'application ne demande plus -Force.
Une même session ne peut pas démarrer deux workers de construction, même pour
des sorties différentes. Les contrôles existants de remontage de l'ISO et des
fichiers Bastos embarqués sont conservés. Les fichiers de démarrage BIOS/UEFI,
setup.exe, boot.wim et autounattend.xml sont comparés à la préparation. L'image
Windows finale doit contenir une édition Windows 11 x64 unique correspondant
à la sélection ; l'empreinte du WIM réouvert est comparée à celle du WIM exporté.
Le rapport conserve ces preuves et les empreintes du profil demandé.

C# rouvre ensuite le fichier ISO final, vérifie sa taille, son descripteur UDF,
son empreinte complète, les chemins, la langue, le clavier, le compte, l'exécutable
Bastos, le manifeste source et les sélections de nettoyage. Le manifeste embarqué
est régénéré pendant la construction : il est distingué du manifeste source.
Ces vérifications structurelles ne remplacent pas un essai de démarrage en VM.

Validation : 176 contrôles C# et 16 contrôles Windows PowerShell 5 (192 au total),
dont correctifs absents/obsolètes, archive incorrecte, outil modifié après contrôle,
rapport absent, annulation, refus de construction concurrente et ISO/profil/preuves
incohérents. Téléchargement officiel de KB5101684 et lecture/signature d'un véritable
MSP sans exécution. Les cas positifs de correctifs installés et d'ISO utilisent des
preuves simulées et des fichiers de test. Aucun ADK/correctif n'a été installé sur
ce poste et aucune construction Windows complète ni démarrage d'ISO n'a été lancé.
Compilation autonome WPF réussie.

Smoke test réussi : 12 pages, 500 ISO, 615 bascules de langue, analyses matérielle/graphique réelles, détections ADK et WebView2 en lecture seule (absents), refus d'un lien pilote de test et huit mesures ICMP réelles vérifiées.

## Journal des opérations 7.120.17 — 15 octobre 2026

Le Journal affiche les 200 rapports d'opérations les plus récents : date, nom, résultat et explication. Une recherche par nom, message, code ou référence et les filtres Toutes / À vérifier / Réussies facilitent la lecture.

Sélectionner une opération présente son message, les contrôles et leurs preuves, puis les détails techniques dépliables. Le bouton Ouvrir le rapport complet ouvre le JSON correspondant. Le dossier des rapports et l'ancien journal texte restent accessibles.

Les rapports illisibles sont signalés sans bloquer les autres entrées. Les chemins fournis dans les rapports ne sont pas utilisés pour l'ouverture. Une opération sans résultat final est indiquée Fin non enregistrée, sans prétendre qu'elle est terminée. La navigation vers Journal et les boutons Actualiser relisent les rapports, sans relancer d'opération.

Validation : 31 contrôles dédiés (dont lecture de l'historique réel sans modification), compilation Release, démarrage des 12 pages, rendu du Journal, catalogue de 500 ISO et 615 bascules de langue, diagnostics matériels/graphiques et réseau en lecture seule. Aucun programme installé, aucun disque préparé pour ces tests.

L'historique structuré concerne les opérations prises en charge par le moteur vérifié ; les actions plus anciennes restent dans le journal texte. Les tests qui génèrent des rapports de diagnostic apparaissent eux aussi dans l'historique.

## Suivi des interruptions et redémarrages 7.120.18 — 15 octobre 2026

Le moteur enregistre le processus Bastos de lancement (PID et heure de création), le dernier démarrage Windows, une clé identifiant l'action et les demandes de redémarrage des installateurs. La dernière phase est sauvegardée pendant les opérations longues.

Le Journal distingue En cours, Suivi interrompu, Fin de l'outil à vérifier, Redémarrage nécessaire et Redémarrage effectué / résultat à vérifier. Le résultat initial reste visible. Un PID réutilisé n'est pas confondu avec le processus d'origine ; un accès refusé ou une date absente reste explicitement inconnu. Les anciens rapports restent lisibles sans être réécrits.

Un rappel au lancement renvoie aux opérations à vérifier. La lecture du dernier démarrage utilise une requête WMI locale en C#, limitée à deux secondes d'attente côté interface, sans nouveau script PowerShell. Une réponse absente ne prouve jamais un redémarrage.

Les demandes explicites RestartRequired et le code installateur 3010 sont persistés ; les anciennes erreurs structurées ADK_RESTART_REQUIRED restent reconnues. Après un redémarrage constaté, le résultat doit encore être contrôlé. Une nouvelle exécution réussie et vérifiée de la même action résout le rappel correspondant, en conservant le rapport original.

Validation : 176 contrôles du moteur, 26 contrôles du suivi (dont arrêt d'un processus enfant de test réel, PID réutilisé, états inconnus, redémarrages simulés, code 3010, phase sauvegardée et historique conservé), 34 contrôles Journal. Démarrage des 12 pages, rendu du Journal, catalogue de 500 ISO et 615 bascules de langue vérifiés. Diagnostics matériels/graphiques et réseau vérifiés en lecture seule.

Aucun redémarrage du PC, aucune installation ni préparation de disque pour ces tests. Un processus Bastos absent ne prouve pas qu'un outil externe a terminé : le Journal demande une vérification. Le suivi porte sur les opérations du moteur vérifié et les 200 rapports récents chargés par le Journal ; les anciennes actions restent dans le journal texte. Aucune reprise automatique d'une opération interrompue.

Documentation de l'API WMI utilisée : https://learn.microsoft.com/en-us/windows/win32/wmisdk/swbemobjectset-itemindex

## Securite des disques 7.120.19 — 15 octobre 2026

Le plan de reinstallation enregistre maintenant l'identite des disques Windows, cible Windows et Recovery : GUID GPT, numero de serie et identifiant materiel lorsqu'ils sont fournis par Windows, modele, capacite, numero de disque et type de connexion. Il contient egalement les GUID, numeros, types GPT, tailles et positions de toutes les partitions.

Le module commun Bastos.StorageSafety.psm1 compare ce plan avec une nouvelle lecture du stockage. Un disque disparu, remplace, hors ligne, en lecture seule ou amovible, un GUID ambigu, une partition ajoutee, supprimee, redimensionnee ou remplacee et une lettre de lecteur reaffectee provoquent un refus avant la prochaine etape protegee. Les messages indiquent de revoir puis enregistrer le plan dans Compte, nom du PC, nettoyage et partitions.

La preparation relit le stockage avant les modifications de partitions, avant l'ecriture sur la cible, avant la copie et le remplacement du media, puis avant l'armement du demarrage. Les controles sont repetes apres les longues validations. Les controles GPT et de partitions deja presents dans WinPE restent en place. Le parcours de preparation avec options enregistrees n'agrandit plus automatiquement D: : le plan valide reste fixe.

Les options confirmees sont transmises aux scripts dans un fichier propre a chaque operation. La preparation et le demarrage utilisent ainsi le meme plan confirme, meme si le fichier de configuration general est modifie entre-temps. Les fichiers de reponses sont egalement propres a chaque preparation ; l'enregistrement des options remplace le fichier de facon atomique.

Les anciennes options sans ce plan doivent etre revues et enregistrees une fois avant la prochaine preparation ou reinstallation. Le parcours autonome historique conserve des controles d'identite physique pendant ses propres changements de partitions. La cle USB reste selectionnee et preparee dans l'interface de Rufus.

Validation : 40 scenarios simules de securite disque sous Windows PowerShell 5.1 ; lecture reelle du disque Windows et de sa partition ; generation puis double validation du plan reel de D: ; refus d'une divergence simulee par le worker complet ; anciennes options refusees avant preparation. Integration C# / worker reelle validee. Compilation Release, demarrage des 12 pages et catalogue de 500 ISO / 615 bascules de langue verifies.

Aucun formatage, effacement, redimensionnement, installation ni redemarrage reel pendant ces tests. La preparation destructive et la reinstallation complete ne sont pas executees pour la validation. Les profils et partitions utilisateurs n'ont pas ete modifies.

## Fonctions communes du moteur 7.120.20 — 15 octobre 2026

Sept scripts deleguent maintenant leurs publications au module Bastos.Operation.psm1 : telechargement de Rufus, construction ISO, preparation/reinstallation interne, nettoyage shaders, nettoyage de la liste standby, telechargement du media Microsoft et telechargement des outils Radeon.

Le module centralise l'ecriture UTF-8 des fichiers texte et JSON, leur remplacement atomique, les nouvelles tentatives en cas de verrouillage temporaire et le nettoyage des fichiers temporaires. Une ecriture refusee conserve le rapport precedent. Les rapports du moteur gardent leur identifiant d'operation, leur schema et leurs preuves ; les rapports historiques conservent leur structure propre.

La progression commune conserve les trois champs historiques. Les scripts ISO et Recovery demandent explicitement les cinq champs avec etape et nombre total d'etapes. Les separateurs parasites sont nettoyes et une progression incoherente est refusee sans remplacer la derniere valeur valide. Les calculs SHA-256 communs liberent aussi leurs ressources si l'ouverture du fichier echoue.

Les sept scripts conservent leurs traitements propres, leurs controles de signature, de liens et de disques ainsi que leur politique de gestion des erreurs. Cette mise a jour regroupe le code de publication du moteur ; elle ne change pas les actions proposees dans l'interface.

Validation : 39 controles communs sous Windows PowerShell 5.1, dont fichiers verrouilles, Unicode, tableaux JSON, enveloppe d'operation et cent remplacements avec lecteur concurrent. Tests des fonctions de publication extraites des sept vrais scripts, sans executer leurs actions. Les 176 controles du moteur, 16 controles ADK/ISO et 40 scenarios de securite disque passent : 271 controles au total.

Integration reelle : plan du disque relu et valide en lecture seule, divergence simulee refusee ; demarrage des 12 pages ; catalogue de 500 ISO et 615 bascules de langue ; diagnostics materiels, graphiques et reseau. Aucune installation, aucun nettoyage de donnees utilisateur, aucun formatage, aucune preparation de disque ni aucun redemarrage reel pour ces tests. Une creation ISO complete et une reinstallation complete n'ont pas ete lancees.

## Recovery et moteur verifie 7.120.21 - 15 octobre 2026

La preparation Recovery et la programmation de son demarrage utilisent maintenant
le moteur commun : identifiant unique, progression, rapport structure et Journal.
La creation du profil Windows est comprise dans cette operation. La progression
n'atteint 100 % qu'apres verification independante du resultat.

Les controles relisent le plan des disques, le profil, l'ISO et les empreintes des
images Windows. Le demarrage exige en plus une tentative correctement identifiee,
les autorisations attendues et une relecture de la sequence unique BCD de Windows.
Un processus en echec ne peut plus etre annonce reussi par son seul rapport JSON.
Les erreurs de plan disque et de preparation ont des explications dediees.

Le redemarrage est une operation distincte du Journal et n'est demande qu'apres
validation complete. En cas d'echec confirme, la neutralisation cible uniquement
la tentative concernee et refuse d'effacer celle d'une autre operation. Un outil
dont l'arret est inconnu n'est pas tue et ne declenche pas de redemarrage automatique.
Le parcours autonome utilise egalement ce moteur.

Validation : compilation autonome reussie ; 310 controles automatises
(40 Recovery C#, 15 Recovery PowerShell, 176 moteur, 39 rapports communs,
40 securite disque), controles BCD et disques reels en lecture seule,
12 pages et 20 cartes affichees, catalogue ISO et analyses materiel/reseau verifies.
Aucun formatage, aucune reinstallation ni aucun redemarrage reel pendant ces tests.
Le parcours destructif complet reste a valider sur une machine de test dediee.
La verification recalcule les empreintes des gros fichiers et peut prendre du temps ;
la relecture du demarrage peut demander une elevation administrateur supplementaire.
## Bilan avant lancement — 7.120.22 — 15 octobre 2026

Réinstallation facile Windows présente un bilan avant la préparation Recovery
et avant le lancement d’une réinstallation interne. Les deux boutons ouvrent
ce bilan ; aucune préparation ne commence à son ouverture.

Le bilan affiche le fichier ISO, l’édition et sa langue, le compte, le PC,
le clavier, les formats régionaux et les options de nettoyage sélectionnées.
Le disque est identifié par son numéro, son modèle, sa capacité et GPT/UEFI.
Chaque partition apparaît avec sa taille et sa décision CONSERVER ou EFFACER.
La conservation ou la recréation de l’EFI est explicite. Le texte distingue
le remplacement des fichiers du média sur D: de l’effacement futur dans Recovery,
et annonce les 15 secondes avant redémarrage pour une réinstallation confirmée.

Les contrôles relisent le stockage et le catalogue de l’ISO, recalculent son
empreinte et vérifient l’édition et la langue enregistrées. Une ISO absente ou
modifiée, un plan divergent, des identités ou mesures incohérentes et une langue
indisponible bloquent le lancement avec une explication. La lecture de l’ISO
peut être longue ; elle utilise les contrôles de signature et de montage existants.

L’espace total et libre de Recovery est relu dans Windows. Le bilan exige la
marge conservatrice d’une copie complète (taille ISO + 2 Go), même si un média
existe déjà. Une conversion ESD vers WIM peut demander davantage ; le bilan ne
garantit pas son encombrement final. Les contrôles du worker restent actifs.
Les options confirmées sont conservées pour la préparation et le démarrage,
sans relire la configuration générale entre ces deux actions.

La confirmation est désactivée au départ et exige un accord explicite sur le
plan et les sauvegardes. Un bilan bloqué reste impossible à confirmer. Fermer
la fenêtre ne lance aucune opération.

Validation : 34 contrôles dédiés au bilan, 40 contrôles Recovery C#, 15 contrôles
Recovery PowerShell et 40 contrôles de sécurité disque réussis (129 contrôles).
Compilation autonome réussie ; 12 pages, 20 cartes, catalogue de 500 ISO,
615 bascules de langue et diagnostics matériel/graphique/réseau vérifiés.
Lecture réelle du plan des partitions et de l’espace libre, refus d’une ISO
absente par le service réel et d’une divergence simulée du disque. Bilan WPF
vérifié avec données simulées, confirmation initiale et blocages contrôlés,
rendu relu visuellement. Aucune préparation de disque, réinstallation, suppression
de fichiers utilisateur ni aucun redémarrage réel pendant ces tests.BASTOS 7.120.23 — Validation Recovery en machine virtuelle — 15 octobre 2026

Validation du parcours réel de réinstallation de Windows 11 Pro 26H2 français
sur un disque virtuel Hyper-V isolé : préparation, contrôle des preuves,
démarrage unique, Windows Setup et retour au Bureau. Deux politiques EFI sont
testées : recréer l’EFI ou la conserver, en préservant la partition Recovery.
Les rapports relisent les GUID des partitions, l’édition, la langue, le clavier,
le compte local et le nom du PC. Les ISO absentes, plans divergents et manque
d’espace réel sont refusés avant lancement.

Corrections apportées pendant ces essais :
- Le rapport de démarrage unique transmet AttemptId, indispensable à sa vérification.
- Le profil Windows Setup utilise un élément Key vide et WillShowUI=Never pour
  éviter la demande de clé au milieu de l’installation. Aucune clé d’activation
  n’est ajoutée ; l’index de l’image sélectionne l’édition.
- Les erreurs de création du raccourci sont écrites par le transcript sans
  rouvrir son fichier verrouillé ; l’erreur d’origine reste propagée.
- Le marqueur de finalisation est écrit après la persistance de l’état réussie.
- Le journal précise les étapes de nettoyage et de création du raccourci.

Tests automatisés : 41 contrôles Recovery C#, 17 contrôles du contrat PowerShell,
15 contrôles du générateur et des erreurs de première connexion, 40 contrôles
 de sécurité disque et 41 contrôles du laboratoire. Compilation et smoke tests
 de l’application réussis : pages, catalogue ISO, changements de langue, bilan,
 diagnostics et stockage en lecture seule.

Les résultats réels concernent Pro français en VM ; ils ne constituent pas une
validation sur chaque matériel ou édition de Windows. Les tests n’ont réinstallé
que le disque virtuel du laboratoire. La VM est conservée arrêtée, sans réseau.

## Erreurs utiles — Bastos 7.120.24 — 15 octobre 2026

Les opérations du moteur présentent maintenant le problème, l’état confirmé ou
incertain et une action concrète. Les retours des services et le Journal utilisent
les mêmes conseils : plan des partitions à réenregistrer, profil ISO à revoir,
ADK à recontrôler après redémarrage, WebView2 à détecter, source/signature refusée,
rapport absent ou résultat impossible à confirmer.

Le Journal affiche séparément « Ce qui est confirmé ou reste incertain » et
« Que faire maintenant ». Les codes, codes de sortie, messages d’origine,
contrôles et détails techniques restent conservés sous « Détails techniques »,
fermé par défaut. La recherche continue de retrouver les anciens messages et codes.

La dernière phase suivie ne prouve pas qu’une écriture est terminée. Un échec
n’annonce donc pas un retour arrière ni une absence de modification sans preuve.
La possibilité de lancement est enregistrée avant l’appel au traitement ; le
refus initial de journalisation indique explicitement qu’aucune action n’a été
lancée pour cette tentative. Les anciens rapports sans ce champ restent lisibles
et sont présentés avec prudence. Une fin de processus incertaine et le suivi des
interruptions sont prioritaires sur les conseils de relance.

Un nettoyage partiel conserve les compteurs fournis par son résultat vérifié.
Une erreur de neutralisation Recovery demande de vérifier le Journal avant tout
redémarrage manuel. Aucun bouton de relance ou de réparation automatique n’est ajouté.

Validation : 24 contrôles dédiés aux conseils, 176 contrôles du moteur, 41 Recovery,
36 Journal et 26 suivi : 303 contrôles réussis. Les tests des erreurs lancent des
workers simulés ; les tests Journal relisent aussi l’historique réel sans le modifier.
Compilation autonome réussie ; rendu des vrais contrôles WPF vérifié avec trois
rapports simulés isolés (profil Recovery, outil encore actif, nettoyage partiel),
détails fermés par défaut puis dépliés. Démarrage des 12 pages, 20 cartes,
catalogue de 500 ISO et 615 bascules de langue vérifiés.
Aucune installation système, réinstallation, modification de partition ou demande
de redémarrage pour ces tests. Le laboratoire Hyper-V reste arrêté.

## Annulation selon la phase — Bastos 7.120.25 — 15 octobre 2026

Réinstallation facile Windows affiche un bouton « Demander l’annulation » avec
une explication de la phase courante. Le bouton est actif uniquement pour une
opération qui accepte cette demande. Une demande envoyée n’est pas annoncée comme
une annulation accomplie ; le résultat du worker et son nettoyage font foi.

L’actualisation du catalogue peut être arrêtée : les requêtes HTTP reçoivent le
signal et la liste précédente est conservée. Les téléchargements ISO ouverts
chez l’hébergeur restent gérés par le navigateur ; le texte indique d’utiliser
sa liste Téléchargements pour les arrêter.

Le bilan Recovery peut être arrêté après le contrôle en lecture en cours.
La préparation accepte une demande jusqu’au point situé juste avant les premières
écritures Recovery. Le worker contrôle cette demande lui-même, puis publie le
verrouillage pour les écritures de partition et la configuration UEFI. Aucun
processus, Robocopy, DISM, installateur ou outil de démarrage n’est tué.
Une demande arrivée après cette frontière ne peut pas interrompre les écritures.
Si elle arrive dans le parcours « réinstaller », elle empêche néanmoins Bastos
de demander automatiquement le redémarrage après la préparation. Le démarrage
Recovery déjà engagé doit aller jusqu’à sa vérification ; aucun bouton ne promet
de l’annuler après programmation.

Le moteur historique de création ISO possède aussi une demande coopérative aux
points prévus entre les traitements. Une copie ou une opération DISM déjà en
cours doit terminer avant le point suivant. La publication finale est verrouillée.
Le rapport d’annulation est désormais publié après le nettoyage ; les montages
et l’absence de sortie incomplète sont contrôlés. Un nettoyage incertain donne
un résultat non confirmé, jamais une annulation réussie. La vérification ou
l’installation des prérequis ADK reste non interruptible dans cette version.

Validation : 16 contrôles C# d’annulation, 13 PowerShell des vraies fonctions et
sondes simulées, 176 moteur, 41 Recovery, 24 conseils d’erreur, 39 fonctions
communes, 40 sécurité disque et 34 bilan : 383 contrôles automatisés réussis.
Le vrai worker Recovery a aussi été exécuté dans la VM isolée avec demande
présente avant la frontière : code 2, annulation avant écritures confirmée,
partitions, BCD, boot.wim et fichier témoin inchangés, ISO démontée. L’état
précédent de la VM a été restauré et elle reste arrêtée. Pas de nouvelle
réinstallation ni de redémarrage du PC physique pendant ces tests.

Compilation autonome et vrais contrôles WPF vérifiés : bouton effectivement lié,
explication visible, demande unique puis bouton désactivé, phases protégées,
12 pages, catalogue ISO et bascules de langue. Le plan de stockage réel est relu
sans modification. Une construction ISO complète n’a pas été relancée pour cette
étape ; ses points d’arrêt et la vérification de nettoyage sont testés isolément.

## Reprise après fermeture — Bastos 7.120.26 — 15 octobre 2026

Le Journal propose « Vérifier les éléments existants » puis « Continuer dans le
module » pour les opérations qui enregistrent une intention de reprise : Rufus,
WebView2, ADK, préparation Recovery Windows officiel et construction ISO.
Ces données sont enregistrées avant le lancement. Aucun argument historique ni
programme indiqué dans un rapport n’est rejoué. Le retour au module sélectionne
l’ISO encore présente dans la bibliothèque ; si elle manque, Bastos le signale
et ne choisit pas une autre ISO pour cette reprise.

Le contrôle compare le rapport au numéro de tentative et réutilise les contrôles
indépendants existants : fichier, taille, empreinte, signature, présence de l’outil,
configuration attendue ou identités du disque et du média selon l’action.
Recovery relit son profil figé et son empreinte, puis utilise uniquement InspectResult.
Aucune programmation de démarrage, préparation, installation ou suppression n’est
lancée par ce contrôle. Si le rapport final manque, une observation des fichiers
connus distingue leur simple présence d’une préparation complète vérifiée.

Le contrôle a son propre rapport .resume.json et conserve les rapports d’origine.
Sa date et son message sont retrouvés à la réouverture du Journal, avec une demande
de revérification si les fichiers ou le disque ont changé. Un ancien résultat
interrompu reste enregistré comme tel ; le contrôle séparé ne le transforme pas
en exécution réussie. Le bilan et les confirmations du module restent nécessaires.

Les nouveaux workers enregistrent PID et heure de démarrage. Le contrôle refuse
une conclusion favorable si le lanceur, le worker ou un outil associé peut encore
travailler, ou si leur état n’est pas suffisamment connu. Des verrous de fichiers
par action empêchent une seconde instance de Bastos de relancer la même opération
pendant que la première continue après fermeture. Un verrou endommagé ou une
identité absente restent bloquants plutôt que de lancer une action à l’aveugle.
Les processus ne sont jamais arrêtés de force par cette fonction.

Les anciens rapports sans intention de reprise restent lisibles avec leurs conseils,
mais ne permettent pas de reconstruire rétroactivement leurs paramètres ou PID.
La reprise ne remet pas à zéro un disque ni un nettoyage partiellement exécuté,
et ne poursuit jamais automatiquement un démarrage ou une réinstallation Windows.
Les fichiers de média Recovery déjà conformes sont recontrôlés et réutilisés par
le parcours normal de préparation ; les copies incomplètes ne sont pas déclarées valides.

Validation : 27 contrôles de reprise, 176 moteur, 41 Recovery, 36 Journal,
26 suivi, 16 annulation et 24 erreurs utiles : 346 contrôles réussis.
Un vrai lanceur de test a été fermé pendant qu’un worker PowerShell inoffensif
continuait : seconde exécution bloquée pendant son activité, contrôle des fichiers
possible après sa fin et nouvelle tentative explicite permise. Les fichiers
modifiés, rapports divergents, preuves manquantes, outils encore actifs et verrous
endommagés sont refusés ; les rapports initiaux restent inchangés.

Interface WPF vérifiée avec rapports simulés isolés : aucune action au chargement,
contrôle explicite, fichier modifié refusé, dernier contrôle retrouvé après
réouverture et retour au module. L’identité du vrai worker de statut du stockage
est enregistrée et vérifiée en lecture seule. Compilation, 12 pages, 20 cartes,
catalogue de 500 ISO, 615 bascules de langue et annulation WPF vérifiés.
Aucune installation système, préparation de disque, réinstallation ou demande de
redémarrage pendant cette étape. Le laboratoire Hyper-V n’a pas été utilisé.
# Bastos 7.120.27 — Bilan après réinstallation

Étape 3 : vérifier Windows après la réinstallation.

- Profil attendu conservé dans le payload OEM : édition, langue de l’image, région, clavier, nom du PC et compte local. La langue de l’image reste indépendante du clavier et du format régional.
- Contrôle automatique au premier démarrage, y compris après une erreur de finalisation. Inspection en lecture seule ; seul le rapport est écrit.
- Huit contrôles : édition, langue, région, clavier principal, nom du PC, compte local actif, raccourci Bastos et finalisation. Le raccourci est vérifié contre les identités GPT et le manifeste de son exécutable.
- Bilan ouvert au lancement de Bastos lorsqu’un profil est présent ; accès permanent dans Journal > Bilan après réinstallation et bouton Recontrôler Windows.
- Valeurs demandées et constatées affichées, avec trois résultats distincts : conforme, écart, non vérifié. Consignes par réglage ; aucune correction automatique.
- Chaque recontrôle produit un rapport corrélé à la demande et au SHA-256 du profil. Rapport ancien, incomplet, contradictoire ou provenant d’un autre profil refusé. Historique conservé dans Journal.

Les anciens médias doivent être préparés à nouveau pour embarquer le profil et le contrôleur. Une installation effectuée avec un ancien média n’est pas déclarée conforme en l’absence de profil.

Validation : tests du générateur et du collecteur réel sous Windows PowerShell 5.1, contrôles C# des rapports et des refus, tests de régression du moteur/Journal/Recovery/reprise/erreurs, contrôle de l’interface WPF et de ses liaisons. Dans la VM Hyper-V isolée déjà réinstallée : huit contrôles conformes et mauvaise édition détectée. La VM est restaurée et arrêtée. Aucune nouvelle réinstallation complète n’a été exécutée pour cette étape ; génération du nouveau payload testée séparément. Aucun redémarrage ni aucune réinstallation du PC hôte.# Bastos 7.120.28 — Export du diagnostic avec aperçu de confidentialité

Étape 4 terminée : Journal > Exporter un diagnostic.

- Choix de l’opération sélectionnée ou des 20 dernières opérations disponibles.
- Résumé technique par défaut : versions numériques de Bastos/Windows, dates, catégories connues, états, codes d’erreur reconnus, codes de sortie et compte des contrôles. Aucun texte libre, chemin, nom de compte/PC, identifiant machine/GPT ou adresse réseau dans ce mode.
- Détails facultatifs avec masquage automatique des identités connues, chemins locaux/UNC, URL, courriels, adresses réseau, SID/GUID/empreintes et lignes portant des secrets. Les valeurs des contrôles personnels sont retirées. Le masquage des textes libres reste à relire ; il ne garantit pas une anonymisation complète.
- Aperçu exact des trois fichiers avant enregistrement : LIRE-MOI.txt, Diagnostic.json et Manifeste.json (tailles et SHA-256 des contenus exportés).
- Un changement d’options invalide immédiatement l’ancien aperçu. L’export utilise uniquement le contenu figé affiché, même si le journal évolue ensuite.
- Création locale d’un ZIP, contrôle de son contenu puis publication. Aucun envoi automatique, aucun écrasement d’un fichier existant, aucun changement des rapports d’origine.
- Journaux et rapports workers bruts, profils d’installation, fichiers personnels, scripts et ISO jamais joints. Les chemins fournis par les rapports ne sont jamais suivis pour collecter des fichiers.
- Rapports corrompus signalés, sélection disparue refusée sans élargir silencieusement le périmètre. Destinations réseau ou redirigées refusées ; contenu et nombre d’opérations bornés.

Validation : 91 contrôles ciblés (confidentialité, projection des champs, erreurs, chemins redirigés, aperçu figé, archive identique, manifeste et originaux intacts) ; 36 contrôles Journal ; test WPF du résumé/détails/liaisons/invalidation/export/rapport disparu ; test du bilan après réinstallation et parcours général des 12 pages. Les fichiers ZIP de test ont été créés uniquement dans des fixtures locales isolées. Aucun fichier envoyé, aucune réinstallation ni modification de Windows.# Bastos 7.120.29 — Réinstallation simplifiée

Dans Réinstallation facile Windows > Réinstallation interne sans clé USB, les deux boutons « Voir le bilan et préparer D: » et « Voir le bilan et réinstaller » sont remplacés par une seule action principale : « Lancer la réinstallation ».

Cette action utilise le parcours complet existant : récapitulatif et confirmation, préparation de D:, vérification du média, puis programmation du redémarrage pour installer Windows. La préparation séparée n’est plus proposée sur cette page. Les descriptions expliquent maintenant cet enchaînement avec des mots simples.

Les contrôles du disque, des partitions, de l’ISO, de l’espace et des options sont conservés, ainsi que la confirmation des conséquences. Une préparation échouée ou une annulation demandée ne déclenche pas le redémarrage suivant.

Validation : compilation, parcours général des 12 pages, test WPF du récapitulatif avec confirmation requise et blocage en cas d’espace insuffisant, 34 contrôles préalables existants. Aucun lancement de préparation réelle, aucune réinstallation et aucun redémarrage du PC.# Bastos 7.120.30 — Classement des réglages par usage

Personnalisation
- Menu Démarrer et interface : profil du menu Démarrer, remplacement du Gestionnaire des tâches, actualités, Réunion maintenant, Cortana/recherche web, Copilot et contenus suggérés.
- Clavier et souris : répétition des touches, raccourcis d’accessibilité et accélération du pointeur. Le réglage de répétition ne prétend plus réduire la latence matérielle du clavier.
- Confidentialité et données : télémétrie, rapports d’erreurs, publicité, historique, localisation et Localiser mon appareil.
- Sécurité et avertissements : contrôle de compte utilisateur et autorisation des téléchargements non sûrs sans avertissement.
- Mises à jour et pilotes : pilotes via Windows Update et partage des mises à jour.
- Nom d’affichage du compte conservé dans Personnalisation.

Optimisations
- Catégories conservées : carte réseau, carte graphique, mémoire vive, jeux et performances.
- Performances Windows : alimentation, HAGS, Mode Jeu, priorité au premier plan, applications en arrière-plan et plein écran.
- Les préférences de clavier/souris et de sécurité/confidentialité ne sont plus présentées comme des optimisations.

Réglages avancés
- Processeur et planification : MMCSS, énergie, interruptions, C-States et priorité CSRSS.
- Mémoire et entrées-sorties : pagination, combinaison de pages, limites et latence E/S.
- Affichage et présentation : MPO, modes Flip, file d’images et P-State 0 NVIDIA.
- Réseau et transferts : Nagle, tampons réseau et limite WebDAV.
- Horloges et minuteries : synchronisation TSC et horloge de plateforme.
- Services, diagnostics et entretien : maintenance/services Windows, regroupement des hôtes, AutoLoggers et nettoyage temporaire.
- Outils tiers, Quantum et calibration écran conservés dans leurs rubriques techniques.

Les groupes sont repliables et leur état ouvert/fermé est conservé lors de l’actualisation. Les réglages déplacés utilisent les mêmes objets, commandes, recommandations et aides détaillées. Aucun script d’application des réglages n’a été modifié. Les cartes de performances sont affichées par collection, avec suppression des anciens index fixes.

Validation : contrôle de couverture de 11 groupes, 18 bascules, 11 choix et 19 cartes, sans perte ni doublon ; commandes d’origine conservées ; cinq cartes de performances affichées une seule fois. Affichage WPF vérifié pour sécurité/avertissements, clavier/souris et maintenance, sans activer les commandes. Parcours des 12 pages, export de diagnostic et confirmation du bilan de réinstallation également vérifiés. Aucun réglage Windows appliqué, aucune préparation de disque ni réinstallation lancée.# Bastos 7.120.31 — Retrait de l’installation Radeon automatisée

Le bloc Installation Radeon automatisée est supprimé d’Optimisations > Carte graphique. Son parcours de nettoyage/reprise automatique, ses deux view-models et son service d’installation sont retirés des sources. Le script Invoke-BASTOS-RadeonClean.ps1 et la copie RadeonSoftwareSlimmer.Bastos propre à cette intégration sont retirés de D:\Application et des manifestes applicatif/installateur.

Le parcours Mise à jour matériel > Installer / mettre à jour le pilote graphique regroupant NVIDIA, AMD et Intel est conservé. L’outil manuel Radeon Software Slimmer de Réglages avancés reste disponible dans son dossier distinct.

Le retrait des fichiers est sauvegardé et vérifié ; un échec du déploiement restaure les fichiers précédents. Aucune installation/désinstallation de pilote n’est exécutée. Aucune reprise Radeon en attente ni tâche correspondante n’a été détectée avant retrait.

Validation : compilation, parcours des 12 pages et vérification existante de la présence du parcours graphique NVIDIA / AMD / Intel, classement des réglages, contrôle des manifestes et absence des fichiers retirés. Aucun réglage Windows ni pilote modifié.# Bastos 7.120.32 — Retrait de la détection graphique en doublon

Optimisations > Carte graphique ne contient plus le bloc Détecter la carte graphique. Son view-model, ses cartes de téléchargement, sa commande d’analyse dédiée et le mode Graphics du worker sont supprimés. Le sous-titre de la catégorie décrit désormais les réglages de performances GPU.

La détection reste centralisée dans Mise à jour matériel. Hardware-Analysis-Worker.ps1 est un script partagé par l’inventaire matériel : il est conservé et allégé du mode graphique seul devenu inutile. Sa détection GPU dans l’inventaire complet et le parcours Installer / mettre à jour le pilote graphique NVIDIA / AMD / Intel sont conservés.

Validation : compilation, parcours des 12 pages, vérification du classement et test réel en lecture seule du service d’analyse matérielle, avec carte graphique présente dans l’inventaire commun. Aucun pilote installé ou désinstallé, aucun réglage Windows appliqué.# BASTOS 7.120.33

Optimisations > Carte graphique affiche uniquement les réglages des fabricants des GPU détectés : AMD, NVIDIA et Intel. Les PC hybrides conservent les réglages des deux marques présentes.

La détection matérielle commune à l'accueil inventorie les identifiants PCI de toutes les cartes graphiques. Les anciens pilotes conservés dans le registre ne déterminent plus les marques affichées. Le cache se met à jour même si seule la carte secondaire change. Une indication explique la détection indisponible ou l'absence de GPU reconnu.

Validation : compilation Release ; navigation 12 pages ; 9 scénarios de filtrage vérifiés dans la vue WPF ; 4 contrôles du cache ; analyse matérielle réelle (19 composants). Sur ce PC, deux GPU AMD détectés. Aucun réglage GPU appliqué pendant les tests.
# Bastos 7.120.34 — Contrôle des fichiers avant exécution

Étape 1 : vérifier les scripts et leurs modules avant chaque lancement depuis Bastos.

- Catalogue SHA-256 embarqué dans l’exécutable : 111 fichiers du moteur (scripts PowerShell, modules et scripts CMD). La référence est indépendante des manifestes modifiables à côté de l’application.
- Contrôle complet à chaque lancement PowerShell : couvre les dépendances choisies dynamiquement et les scripts copiés dans les médias Recovery, sans déduire une liste partielle d’imports. Aucun résultat de vérification des fichiers n’est conservé comme cache entre deux actions.
- Refus avant lancement si un fichier manque, diffère, est illisible, non répertorié ou redirigé. Les fichiers ouverts pour le contrôle restent protégés contre l’écriture et le remplacement pendant leur suivi.
- Protection du lanceur commun, du bilan après réinstallation et du menu des pilotes graphiques. Les commandes Windows intégrées à l’exécutable ne sont pas des scripts externes.
- Erreur utile avec nom précis du fichier et consigne de restauration de la même version. Journal indique Contrôle des fichiers, exécution non engagée et absence de processus lancé. Les codes de contrôle sont inclus dans l’export technique du diagnostic.
- Une modification d’un fichier du moteur bloque les lancements PowerShell tant que l’ensemble n’est pas rétabli. Aucun recalcul automatique de confiance ou réparation silencieuse.
- La livraison refuse un script divergent, un nouveau fichier moteur non ancré ou un catalogue absent. Outil développeur Build/New-EngineIntegrityCatalog.ps1 fourni dans les sources ; toute évolution des scripts exige une régénération explicite et une recompilation.

Validation : 24 contrôles ciblés d’intégrité, dont refus avant effet avec le vrai lanceur sur copies isolées, module/script secondaire absent ou modifié, verrouillage, chemins redirigés, catalogue invalide, remplacement du manifeste externe et retour à un état conforme ; 6 contrôles du vrai garde de livraison ; 373 contrôles de régression du moteur, du Journal, de la reprise, des erreurs, du bilan Windows et de l’export de diagnostic. Soit 403 contrôles automatisés. Test WPF du refus avec erreur précise dans Journal, contrôle de 111 fichiers réels et vrai worker Recovery Status en lecture seule avec reçu PID vérifié. Parcours des 12 pages. Aucune préparation Recovery, installation de pilote, réinstallation ou modification de partitions pendant ces tests.# Bastos 7.120.35 — Journaux et fichiers temporaires

Étape 2 terminée : Journal > Journaux et fichiers temporaires.

- Analyse locale avec taille totale analysée, taille nettoyable estimée et taille conservée. Chaque groupe indique les fichiers concernés et la raison de sa conservation ou de son éligibilité.
- Conservation minimale de 30 jours, réglable à 60/90/180/365 jours. Les 200 opérations valides les plus récentes restent protégées, quelle que soit leur ancienneté.
- Erreurs, opérations incomplètes ou contradictoires, redémarrage demandé, fin de processus inconnue, reprise et références persistantes de suivi sont conservés. Un suivi illisible ou occupé protège les groupes d’opérations.
- Nettoyage limité aux anciennes opérations réussies sans besoin de reprise et à leurs fichiers associés reconnus, ainsi qu’aux anciennes archives du journal natif ne contenant pas de marqueur ERROR. Le journal courant, les options, les fichiers inconnus et les archives d’erreurs restent intacts.
- Aucun parcours récursif de dossiers personnels, de TEMP Windows, des ISO, de Recovery ou des caches d’outils. Les bilans de nettoyage sont conservés dans Logs/Maintenance.
- Aperçu obligatoire, éléments décochables et confirmation avec nombre d’éléments/fichiers et taille. Une modification de durée invalide l’aperçu ; un aperçu de plus de 15 minutes est refusé.
- Nouvelle analyse avant suppression, contrôle des empreintes, tailles, dates, chemins réels et ouvertures exclusives. Un groupe modifié, devenu nécessaire ou occupé est conservé. Suppression par handles vérifiés ; rapport principal supprimé après ses fichiers associés. Un éventuel résultat partiel est signalé.
- Bilan local réservé et enregistré avant toute suppression, mis à jour après les fichiers retirés. Un problème d’écriture arrête la poursuite du nettoyage.
- Rotation du journal natif principal au seuil de 5 Mo : l’ancien fichier est archivé intégralement, sans troncature ni suppression automatique. Écritures concurrentes coordonnées et lecture compatible avec la rotation.

Validation : 48 contrôles ciblés de maintenance et rotation, incluant de vraies suppressions sur fixtures isolées, conservation octet pour octet des rapports utiles, fichiers verrouillés, contenu changé à taille/date identiques, nouvelle référence de suivi, erreurs, aperçu expiré, chemins redirigés, bilan impossible à créer, rotation sans perte et écritures concurrentes. Régression du moteur, de l’intégrité, du Journal, de la reprise, des erreurs, du bilan Windows et de l’export. Test WPF des tailles, protections, choix de durée, cases à cocher et bilan après nettoyage de trois fichiers de fixture. Aucun journal utilisateur supprimé pendant la livraison ; l’interface installée est seulement analysée.

## Correction audio 7.120.37 — 16 octobre 2026

Verification des formats PCM contre les capacites materielles en mode exclusif : 48 kHz / 24 bits utiles avec repli a 16 bits. Suppression de la demande de periode globale refusee par les pilotes. Affichage par nom de peripherique; erreurs techniques conservees dans les journaux. Migration des cibles anciennes sans ecraser leurs valeurs initiales. Application reelle et relecture sur le PC : 6/6 reglages compatibles; 34 controles VM et test d'interface reussis. La sauvegarde de premiere application est conservee.



## Steam permanent 7.120.38 — 16 octobre 2026

Appliquer enregistre la preference permanente GPUAccelWebViewsV3=0 de Steam en plus des arguments de raccourcis. Elle persiste au redemarrage et au lancement par un jeu. La valeur precedente ou son absence sont sauvegardees et restaurables. Un redemarrage de Steam deja ouvert est requis une seule fois apres application. 38 controles VM et test interface reussis.



## Ajouts Kirby adaptes a Bastos 7.120.39 — 16 octobre 2026

Preferences permanentes Chrome/Firefox/Discord, diagnostic MTU par carte, veille USB par propriete exposee, options AC/DC du plan actif, profils souris dans le controle existant et profils visuels reutilisant les commandes/sauvegardes existantes. 43 controles des ajouts et 38 controles de non-regression reussis. Profils souris et visuels verifies dans la session interactive de la VM. Aucun nouveau tweak applique automatiquement sur le PC. Documentation : README-Extras.md dans les sources.



## Courbes de souris 7.120.40 — 17 octobre 2026

Personnalisation > Clavier et souris : choix Defaut, MarkC, CPL et CheeseM avec les courbes numeriques de Kirby. Selection initiale Defaut sans ecriture automatique ; la courbe actuellement enregistree est affichee separement. Sauvegarde partagee avec vitesse/acceleration et compatible avec v39. Restauration des originaux, des valeurs absentes et conservation des changements externes. 20 controles courbes et capture UI en VM reussis. Aucun changement des courbes sur le PC pendant installation.



## Curseurs sombres 7.120.41 — 17 octobre 2026

Carte Personnalisation pour activer W11 Cursor Dark Free by Jepri Creations et restaurer le theme precedent. 17 roles sauvegardes, fichiers copies dans un dossier utilisateur persistant, rechargement natif des curseurs avec indication de reconnexion si necessaire. Aucun pack active automatiquement a installation. 10 controles en VM avec restauration et capture interface reussis. Credits et licence conserves.

Courbes souris 7.120.42 : selection synchronisee avec les valeurs Windows a ouverture et retour sur la page. Choix en cours preserve pendant actualisation. Courbes inconnues identifiees Personnalise. 26 controles VM. Aucun reglage applique a installation.
Audit et persistance 7.120.43 : relecture des profils de performance au retour dans les pages et activation de la fenetre ; etats partiels avec compteur, valeurs clavier enregistrees et de session ; application clavier via API Windows ; sauvegardes natives atomiques et videes sur disque, validation avant modification. 32 controles en VM dont conservation de six profils apres redemarrage et restauration exacte. Aucun reglage du PC modifie a installation. API clavier interactive non testee dans la VM sans utilisateur connecte.
Confidentialite 7.120.44 : verification complete apres activation, code echec si valeurs ou taches non conformes ; etats partiels avec compteurs, etat inconnu explicite sans utiliser une ancienne activation comme preuve ; protection contre un autre compte administrateur ; sauvegardes originales ecrites atomiquement avec vidage disque ; restauration corrigee pour Windows PowerShell 5.1. 62 controles VM sur 13 profils avec registre isole et echecs simules. Aucune autre option appliquee sur le PC a installation. Une modification ulterieure par Windows ou un autre outil reste possible et sera detectee a actualisation.
Widgets et localisation 7.120.45. Strategie adaptee aux definitions Windows disponibles. Registre 64 bits et compte utilisateur explicites. Erreur structuree en cas de refus. 72 controles VM avec migration des sauvegardes et lecteur 32 bits.
# Bastos 7.120.46 — Réactivité

Étape 3 : lecture des compteurs de performances en arrière-plan, chargements à la demande et mesures des durées.

- Initialisation des compteurs GPU/disque et collecte des mesures CPU/GPU/RAM/réseau/disque hors du fil WPF. Les mises à jour des éléments visuels restent sur le fil WPF. Une seule mesure peut être en cours ; les ticks suivants ne créent pas de file de lectures. La fermeture ne bloque pas sur un compteur lent et libère les compteurs après leur lecture.
- Le nom du CPU est lu une fois par instance de collecteur, au lieu de relire le registre chaque seconde.
- Les réglages coûteux des autres pages ne sont plus tous interrogés au démarrage. Les visites de rubriques chargent uniquement les familles utiles ; Carte graphique ne déclenche plus les scans Ethernet, audio ou USB. Les demandes de navigation devenues obsolètes avant démarrage sont abandonnées.
- Les lectures récentes sont réutilisées pendant 30 secondes ; les demandes simultanées d'une même famille rejoignent le travail en cours. Actualiser force une nouvelle lecture (ou rejoint celle qui est déjà en cours). Les commandes explicites de lecture des modules restent disponibles. Les commandes d'application/restauration et le contrôle des fichiers exécutés ne passent pas par ce cache.
- Détection du profil matériel et accès au cache réalisés en arrière-plan. Vingt demandes simultanées sur le même service partagent une seule détection ; la revalidation au démarrage reste présente pour reconnaître un changement de pilote ou de GPU.
- Mesures bornées en mémoire : durée du chargement de la fenêtre, du profil matériel, des échantillons et des lectures de réglages. Nombre, durée moyenne et durée maximale sont consignés dans le journal natif lors des actualisations ; aucun journal écrit chaque seconde.

Validation : 14 contrôles ciblés WPF/services (coalescence, cache court, expiration, forçage, nouvel essai après exception, initialisation hors UI, interface active pendant une lecture bloquée, fermeture, libération unique, détection simultanée et navigation GPU). Navigation GPU mesurée à 5 ms sur ce passage ; première collecte native jusqu'à 981 ms hors du fil UI. Ces mesures locales ne constituent pas une garantie de temps de démarrage.
Régression : parcours des 12 pages, catalogue ISO, classement des réglages, filtrage GPU, contrôle des 114 fichiers du moteur et blocage d'un module modifié dans une copie isolée, inventaire matériel réel de 19 composants, maintenance sur fixture isolée. Aucun réglage Windows appliqué, aucune réinstallation ni suppression de journaux utilisateur.

Les sources de cette livraison proviennent de Source-Current.zip de la version installée 7.120.45 pour conserver les modifications récentes de l'application.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.47 — Validation avant livraison

Une commande regroupe les tests du moteur, annulation, reprise après fermeture réelle d'un lanceur de test, rapports corrompus, Journal, intégrité, erreurs utiles, bilan Windows, export, maintenance et scénarios WPF. Un test de réinstallation complète est requis dans la seule VM de laboratoire autorisée, avec restauration de son état initial.

La livraison demande un rapport positif récent couvrant toutes les suites, lié par SHA-256 à l'exécutable, au manifeste et à l'archive des sources du candidat. Un échec, un scénario absent ou un fichier changé bloque le déploiement. Les journaux de chaque suite et les preuves VM sont conservés hors du paquet utilisateur.

L'étape VM utilise Windows 11 Pro français en UEFI avec EFI conservée. Elle vérifie le compte local sans mot de passe, le clavier, la langue, le nom du PC, les identités des partitions, le témoin D:, le Bureau, la finalisation et le binaire candidat. Elle ne constitue pas un test de réinstallation de toutes les éditions ni de tous les matériels.

Les commandes reproductibles et les sources de tests figurent dans Build et Tests de Source-Current.zip. Aucun scénario de réinstallation n'est exécuté sur le PC hôte.
# Bastos 7.120.48 — présentation guidée

Réinstallation Windows est présentée en trois étapes : Windows à télécharger, ISO et méthode, puis options et lancement. Les boutons Continuer et Retour changent uniquement l’écran ; la préparation reste déclenchée par Lancer la réinstallation et son bilan de confirmation. La progression et l’annulation restent accessibles pendant l’opération.

Bastos Game sépare les jeux de leurs réglages, avec l’état et les commandes du moteur toujours visibles. Explorateur présente le choix du navigateur avant les options facultatives. Les avertissements concernant le remplacement des navigateurs et la perte des profils restent visibles.

Les boutons, les blocs et la navigation sont plus fins. Les explications des réglages peuvent être dépliées ; les états et les avertissements restent affichés. Les commandes, réglages sauvegardés, contrôles d’intégrité et moteurs de préparation ne sont pas modifiés.

La version précédente est conservée par la procédure de livraison. Validation locale et VM requises avant déploiement.
# Bastos 7.120.48 — présentation guidée

Réinstallation Windows est présentée en trois étapes : Windows à télécharger, ISO et méthode, puis options et lancement. Les boutons Continuer et Retour changent uniquement l’écran ; la préparation reste déclenchée par Lancer la réinstallation et son bilan de confirmation. La progression et l’annulation restent accessibles pendant l’opération.

Bastos Game sépare les jeux de leurs réglages, avec l’état et les commandes du moteur toujours visibles. Explorateur présente le choix du navigateur avant les options facultatives. Les avertissements concernant le remplacement des navigateurs et la perte des profils restent visibles.

Les boutons, les blocs et la navigation sont plus fins. Les explications des réglages peuvent être dépliées ; les états et les avertissements restent affichés. Les commandes, réglages sauvegardés, contrôles d’intégrité et moteurs de préparation ne sont pas modifiés.

La version précédente est conservée par la procédure de livraison. Validation locale et VM requises avant déploiement.
# Bastos 7.120.48 — présentation guidée

Réinstallation Windows est présentée en trois étapes : Windows à télécharger, ISO et méthode, puis options et lancement. Les boutons Continuer et Retour changent uniquement l’écran ; la préparation reste déclenchée par Lancer la réinstallation et son bilan de confirmation. La progression et l’annulation restent accessibles pendant l’opération.

Bastos Game sépare les jeux de leurs réglages, avec l’état et les commandes du moteur toujours visibles. Explorateur présente le choix du navigateur avant les options facultatives. Les avertissements concernant le remplacement des navigateurs et la perte des profils restent visibles.

Les boutons, les blocs et la navigation sont plus fins. Les explications des réglages peuvent être dépliées ; les états et les avertissements restent affichés. Les commandes, réglages sauvegardés, contrôles d’intégrité et moteurs de préparation ne sont pas modifiés.

La maintenance prend aussi en charge les chemins locaux de plus de 259 caractères lors de l’ouverture exclusive native. Les contrôles du chemin, des liens, de l’empreinte et du contenu restent requis ; un refus Windows indique son code et conserve le groupe.

La version précédente est conservée par la procédure de livraison. Validation locale et VM requises avant déploiement.
# Bastos 7.120.48 — présentation guidée

Réinstallation Windows est présentée en trois étapes : Windows à télécharger, ISO et méthode, puis options et lancement. Les boutons Continuer et Retour changent uniquement l’écran ; la préparation reste déclenchée par Lancer la réinstallation et son bilan de confirmation. La progression et l’annulation restent accessibles pendant l’opération.

Bastos Game sépare les jeux de leurs réglages, avec l’état et les commandes du moteur toujours visibles. Explorateur présente le choix du navigateur avant les options facultatives. Les avertissements concernant le remplacement des navigateurs et la perte des profils restent visibles.

Les boutons, les blocs et la navigation sont plus fins. Les explications des réglages peuvent être dépliées ; les états et les avertissements restent affichés. Les commandes, réglages sauvegardés, contrôles d’intégrité et moteurs de préparation ne sont pas modifiés.

La maintenance prend aussi en charge les chemins locaux de plus de 259 caractères lors de l’ouverture exclusive native. Les contrôles du chemin, des liens, de l’empreinte et du contenu restent requis ; un refus Windows indique son code et conserve le groupe.

La version précédente est conservée par la procédure de livraison. Validation locale et VM requises avant déploiement.
# Bastos 7.120.49 — écrans harmonisés

Logiciels, Personnalisation et Réglages avancés utilisent des surfaces, espacements et titres cohérents avec la présentation guidée. Les cartes des réglages ne réservent plus de grande hauteur vide. Les choix et leur bouton s’alignent sur une ligne distincte, avec le résultat en dessous, sans marge négative.

Logiciels utilise une grille qui s’adapte à la largeur de la fenêtre ; les catégories restent lisibles, les noms complets et descriptions restent accessibles. La sélection, les favoris et les indicateurs d’installation sont conservés. Les actions sur la sélection sont regroupées sous la liste ; les commandes de mise à jour restent accessibles dans leur section.

Personnalisation présente les curseurs et profils d’apparence en sections dépliables cohérentes avec les autres rubriques. Souris et écran partagent la même taille de titres et les mêmes espacements. Les outils avancés s’adaptent à la largeur disponible.

Les états, recommandations, avertissements et commandes existants sont conservés. Aucun changement du moteur ou des préférences enregistrées. La version précédente est sauvegardée avant livraison.
# Bastos 7.120.49 — écrans harmonisés

Logiciels, Personnalisation et Réglages avancés utilisent des surfaces, espacements et titres cohérents avec la présentation guidée. Les cartes des réglages ne réservent plus de grande hauteur vide. Les choix et leur bouton s’alignent sur une ligne distincte, avec le résultat en dessous, sans marge négative.

Logiciels utilise une grille qui s’adapte à la largeur de la fenêtre ; les catégories restent lisibles, les noms complets et descriptions restent accessibles. La sélection, les favoris et les indicateurs d’installation sont conservés. Les actions sur la sélection sont regroupées sous la liste ; les commandes de mise à jour restent accessibles dans leur section.

Personnalisation présente les curseurs et profils d’apparence en sections dépliables cohérentes avec les autres rubriques. Souris et écran partagent la même taille de titres et les mêmes espacements. Les outils avancés s’adaptent à la largeur disponible.

Les états, recommandations, avertissements et commandes existants sont conservés. Aucun changement du moteur ou des préférences enregistrées. La version précédente est sauvegardée avant livraison.
# Bastos 7.120.49 — écrans harmonisés

Logiciels, Personnalisation et Réglages avancés utilisent des surfaces, espacements et titres cohérents avec la présentation guidée. Les cartes des réglages ne réservent plus de grande hauteur vide. Les choix et leur bouton s’alignent sur une ligne distincte, avec le résultat en dessous, sans marge négative.

Logiciels utilise une grille qui s’adapte à la largeur de la fenêtre ; les catégories restent lisibles, les noms complets et descriptions restent accessibles. La sélection, les favoris et les indicateurs d’installation sont conservés. Les actions sur la sélection sont regroupées sous la liste ; les commandes de mise à jour restent accessibles dans leur section.

Personnalisation présente les curseurs et profils d’apparence en sections dépliables cohérentes avec les autres rubriques. Souris et écran partagent la même taille de titres et les mêmes espacements. Les outils avancés s’adaptent à la largeur disponible.

Les états, recommandations, avertissements et commandes existants sont conservés. Aucun changement du moteur ou des préférences enregistrées. La version précédente est sauvegardée avant livraison.
# Bastos 7.120.50 — hiérarchie des actions

Le bleu est réservé aux actions principales. Actualiser, revenir, fermer et ouvrir les dossiers sont plus discrets. Les choix déjà sélectionnés et les onglets utilisent un fond neutre avec leur repère de sélection, distinct des boutons de lancement.

Les suppressions d’ISO, désinstallations, retraits de la liste de jeux et nettoyages de fichiers portent une couleur de suppression, avec leur libellé explicite. Le bilan final de réinstallation reprend ce repère pour sa confirmation. Les commandes, demandes de confirmation et conditions d’activation sont inchangées.

Le bouton de poursuite avec une ISO existante et la remise à zéro de l’image restent secondaires, afin de distinguer le téléchargement ou l’enregistrement. Les fenêtres de diagnostic, maintenance et journal mettent en avant leur action utile. Les boutons indisponibles sont atténués.

Les réglages enregistrés et moteurs d’exécution ne sont pas modifiés. La version précédente est sauvegardée avant livraison.
# Bastos 7.120.50 — hiérarchie des actions

Le bleu est réservé aux actions principales. Actualiser, revenir, fermer et ouvrir les dossiers sont plus discrets. Les choix déjà sélectionnés et les onglets utilisent un fond neutre avec leur repère de sélection, distinct des boutons de lancement.

Les suppressions d’ISO, désinstallations, retraits de la liste de jeux et nettoyages de fichiers portent une couleur de suppression, avec leur libellé explicite. Le bilan final de réinstallation reprend ce repère pour sa confirmation. Les commandes, demandes de confirmation et conditions d’activation sont inchangées.

Le bouton de poursuite avec une ISO existante et la remise à zéro de l’image restent secondaires, afin de distinguer le téléchargement ou l’enregistrement. Les fenêtres de diagnostic, maintenance et journal mettent en avant leur action utile. Les boutons indisponibles sont atténués.

Les réglages enregistrés et moteurs d’exécution ne sont pas modifiés. La version précédente est sauvegardée avant livraison.
# BASTOS 7.120.51 — Messages plus lisibles

Le résultat apparaît en premier, suivi de l’action utile. Les références et diagnostics techniques sont dépliables dans les messages des modules. Les erreurs connues utilisent des phrases plus courtes ; les messages non reconnus restent intégralement visibles.

Le Journal présente la prochaine action avant l’état détaillé de la tentative. Les fichiers exacts, codes, contrôles et messages originaux restent disponibles dans ses détails techniques. Les erreurs inattendues des cartes, logiciels et navigateurs conservent leur diagnostic copiable sous Détails.

Les consignes de prudence (outil encore actif, bilan partiel, annulation non confirmée, démarrage Recovery) restent visibles. Un indicateur de redémarrage ne remplace plus une interdiction de redémarrage manuel vers Recovery.

Vérification : tests de présentation et de conservation des consignes, contrôles WPF avec messages simulés, validation de livraison et réinstallation dans la VM isolée avant installation. Aucune commande de préparation ou de réinstallation exécutée sur le PC hôte pendant ces contrôles.
# BASTOS 7.120.52 — Comprendre les actions indisponibles

Les actions principales expliquent leurs prérequis à proximité du bouton ; les boutons grisés exposent également leur raison au survol et aux outils d’accessibilité. L’indication disparaît dès que l’action est disponible.

Réinstallation : ISO à sélectionner à l’étape 2, chargement du catalogue et opération en cours. La sélection d’une autre ISO, la suppression et les commandes concurrentes sont suspendues pendant une opération. Le bilan indique pourquoi son lancement reste bloqué ou demande encore la confirmation. Les options Windows indiquent si les éditions se chargent ou si une édition et une langue doivent être choisies.

Logiciels, navigateurs, Journal, profils, curseurs, alimentation, souris et réseau : sélection manquante, état déjà appliqué, matériel non compatible, mesure préalable ou sauvegarde absente. Export : aperçu obligatoire. Nettoyage : analyse préalable, analyse incomplète ou absence de candidat nettoyable.

Les contrôles du média, des partitions, du profil et la confirmation finale restent effectués avant toute action sensible. Les messages sont dérivés des conditions des commandes et ne remplacent pas ces contrôles.

Validation : scénarios WPF de sélection absente, chargement, opération en cours et retour disponible ; tests de non-exécution des commandes bloquées, export et maintenance ; validation complète de livraison et réinstallation dans la VM isolée avant installation.
# BASTOS 7.120.52 — Comprendre les actions indisponibles

Les actions principales expliquent leurs prérequis à proximité du bouton ; les boutons grisés exposent également leur raison au survol et aux outils d’accessibilité. L’indication disparaît dès que l’action est disponible.

Réinstallation : ISO à sélectionner à l’étape 2, chargement du catalogue et opération en cours. La sélection d’une autre ISO, la suppression et les commandes concurrentes sont suspendues pendant une opération. Le bilan indique pourquoi son lancement reste bloqué ou demande encore la confirmation. Les options Windows indiquent si les éditions se chargent ou si une édition et une langue doivent être choisies.

Logiciels, navigateurs, Journal, profils, curseurs, alimentation, souris et réseau : sélection manquante, état déjà appliqué, matériel non compatible, mesure préalable ou sauvegarde absente. Export : aperçu obligatoire. Nettoyage : analyse préalable, analyse incomplète ou absence de candidat nettoyable.

Les contrôles du média, des partitions, du profil et la confirmation finale restent effectués avant toute action sensible. Les messages sont dérivés des conditions des commandes et ne remplacent pas ces contrôles.

Validation : scénarios WPF de sélection absente, chargement, opération en cours et retour disponible ; tests de non-exécution des commandes bloquées, export et maintenance ; validation complète de livraison et réinstallation dans la VM isolée avant installation.

## Correction locale 7.120.57 — désinstallation Open-Shell
Demande administrateur pour la suppression du MSI Open-Shell, absence vérifiée par WinGet, annulation et résultat non confirmé explicites, détails et sélection conservés en cas d’échec. 11 tests et désinstallation réelle réussis. Réinstallation Windows en VM non exécutée.

