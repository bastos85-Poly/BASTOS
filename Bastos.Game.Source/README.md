# Bastos Game 3.6.1 — préparation publique

Le fichier discovery.hpp absent des sources récupérées a été reconstitué. 20 contrôles sur fichiers témoins passent, sans dépendre de jeux installés. L'auto-test du moteur a également réussi sur son processus enfant dédié. Ces résultats locaux ne remplacent pas le laboratoire de livraison. Les paragraphes ci-dessous décrivent l'historique récupéré, pas une nouvelle certification.

Compilation vérifiée avec LLVM-MinGW 20261104 UCRT x86_64 (SHA-256 de l'archive : 552191b5754c49a5a20723276a6fc56541ea1922c4c50b7b669022333fc1b40f), depuis https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104 .

    ./build.ps1 -Toolchain 'CHEMIN/llvm-mingw-20261104-ucrt-x86_64'
    ./Test-Discovery.ps1 -Toolchain 'CHEMIN/llvm-mingw-20261104-ucrt-x86_64' -TestRoot 'CHEMIN/nouveau-test-discovery'
    ./Test-Engine.ps1 -TestRoot 'CHEMIN/nouveau-test-engine'

Les tests exigent des dossiers dédiés neufs. Le remappage des chemins de compilation évite d'inscrire le profil personnel dans les exécutables.

---

# Bastos Game 3.6.0 — trouver les jeux et afficher leur exécutable

Profils par jeu affiche maintenant un chemin complet en lecture seule, sélectionnable et copiable au clavier, sous le jeu choisi. Ajouter un fichier .exe ouvre le sélecteur Windows ; Détecter les jeux Steam relance la recherche des titres pris en charge. La recherche est également effectuée à l'ouverture des réglages.

Cette première détection d'installation prend en charge Aimlabs (Steam 714010, AimLab_tb.exe), Counter-Strike 2 (730, game/bin/win64/cs2.exe) et PUBG (578080). Elle lit la bibliothèque Steam et les bibliothèques supplémentaires déclarées dans libraryfolders.vdf, puis vérifie les manifestes et les exécutables exacts existants. Elle ne lance aucun jeu. Les jeux découverts sont ajoutés à Config.json, donc aussi disponibles dans la liste de Bastos et les profils hors jeu. Les doublons et les exclusions utilisateur sont respectés. Les autres titres peuvent être ajoutés manuellement via leur .exe ; il ne s'agit pas d'un inventaire universel de tous les jeux Steam.

Huit contrôles de détection passent : bibliothèques supplémentaires, absence de doublons et de gestionnaires de crash, ajout avant lancement, idempotence, conservation des réglages, exclusions, rejet de chemins de manifeste sortant de la bibliothèque, exécutable absent et vérification des chemins réels des deux jeux demandés. Vérification visuelle de la disposition et ouverture/annulation du sélecteur Windows. Le moteur d'optimisation reste identique à la version précédente.

Reconstruction du test : compiler tests/DiscoveryTests.cpp avec les mêmes options C++20/Win32 et les bibliothèques user32, shell32, gdi32, advapi32. Lancer DiscoveryTests.exe avec un nouveau dossier de résultats. Le dernier contrôle est propre à cette machine : il attend Aimlabs et CS2 installés. Les autres contrôles utilisent des fichiers témoins, jamais exécutés.
# Bastos Game 3.5.0 — profils accessibles avant le lancement

Réglages standards pour tous les jeux ; Profils par jeu pour préparer les préférences d'un jeu enregistré, même fermé ; Ce qui est appliqué pour les résultats. La liste réunit les jeux autorisés, les profils sauvegardés et les jeux actuellement suivis. Le jeu actif est présélectionné à l'ouverture et marqué en cours. Les rafraîchissements conservent ensuite le choix manuel et les modifications en attente.

L'option du lanceur PUBG reste réservée au profil TslGame.exe, mais peut être préparée et enregistrée avant le lancement. Le moteur applique automatiquement la préférence à ExecPubg dès la détection de PUBG (cycle de vérification d'une seconde), sans ouvrir les réglages. Le moteur d'optimisation ne change pas dans cette version.

Vérifications ciblées d'interface avec données isolées : profil PUBG accessible et enregistrable jeu fermé ; valeur OptimizeAuxiliary relue dans Profiles.json ; présélection d'un autre jeu actif à l'ouverture et absence de l'option PUBG sur ce profil. Les configurations réelles sont préservées lors du déploiement.
# Bastos Game 3.4.0 — réglages standards et profils du jeu actif

La comparaison des performances et ses commandes sont retirées de l'interface. Trois pages la remplacent : Réglages standards, Personnaliser le jeu actif, Ce qui est appliqué.

Les standards définissent la priorité CPU et les priorités par thread par défaut, la limitation des applications en arrière-plan (EcoQoS/E/S) et la pause globale. La page personnelle ne liste que les jeux actifs issus d'un statut récent du moteur. Un profil propre au chemin du jeu peut remplacer la priorité CPU, les priorités par thread et le mode observation ; décocher le profil personnel fait reprendre les standards. Les profils enregistrés sont conservés après fermeture du jeu mais ne sont affichés que lorsque le jeu est actif.

Alléger le lanceur de PUBG apparaît uniquement sur la page personnelle lorsque le jeu sélectionné est TslGame.exe et encore actif. Le moteur applique cette préférence au seul ExecPubg.exe du même dossier PUBG, pendant le suivi de PUBG. Le profil personnel utilise Games[chemin].OptimizeAuxiliary ; les profils existants conservent le repli sur la valeur historique globale. Games[chemin].ThreadPriorities remplace la valeur standard uniquement pour ce jeu. Les jeux sans profil continuent de suivre les standards.

Validation : 30 contrôles du moteur en VM (dont cinq nouveaux sur les profils et le lanceur PUBG), 18 contrôles de la suite existante. Vérification visuelle et fonctionnelle sur des données de test isolées : aucun jeu, PUBG actif, autre jeu actif, enregistrement du profil. La comparaison n'est plus proposée. Ces scénarios d'interface utilisent des états simulés ; les tests du moteur utilisent des processus témoins réels en VM.
# Bastos Game 3.3.0 — 15 octobre 2026

Trois options indépendantes sont disponibles dans **Mes réglages** et enregistrées dans `Profiles.json` : `ThreadPriorities`, `BackgroundEcoQoS`, `BackgroundIoPriority` (valeur par défaut : true, y compris pour les profils existants). Le contrat Config.json de Bastos est conservé. Les options d'arrière-plan restent subordonnées à **Limiter les autres applications** (`OptimizeBackground`), dont la valeur existante est conservée.

- Threads du jeu : le plus ancien thread accessible et les threads nommés contenant render, audio, wasapi, input, rhi, game thread ou gamethread passent de la priorité relative 0 à +1. Les autres priorités définies par le jeu sont conservées. Les nouveaux threads sont examinés à chaque cycle ; aucun nom de thread n'est une preuve absolue de son rôle. Les jeux sans descriptions de threads ne bénéficient que de la sélection du thread principal présumé. Cette règle est une implémentation indépendante, pas une reproduction de l'algorithme de KRNLGame.
- Applications d'arrière-plan autorisées : EcoQoS via ProcessPowerThrottling (bit ExecutionSpeed dans ControlMask et StateMask, autres bits conservés) et priorité d'E/S VeryLow (0) via NtSetInformationProcess, classe ProcessIoPriority (33), résolue dynamiquement. API native optionnelle : un échec n'est pas présenté comme une réussite. Le lanceur auxiliaire PUBG garde sa politique CPU existante.
- La liste d'applications concernées reste celle du moteur : Discord, Chrome, Edge, Firefox, Opera, Brave, SteamWebHelper, EpicGamesLauncher, Battle.net et OneDrive. Les exclusions utilisateur sont respectées. La notion arrière-plan désigne cette catégorie d'applications pendant un jeu actif, et non uniquement la fenêtre sans focus. Désactiver la limitation si elle gêne un appel ou un stream.
- Restauration : processus liés à PID + date de création + chemin ; threads liés à TID + processus propriétaire + date de création. Valeurs originales et demandées journalisées avant toute écriture. Un changement externe des nouveaux réglages est conservé. Les threads terminés sont retirés uniquement lorsque leur fin ou leur remplacement est confirmé. Les entrées non restaurables restent dans le journal.

Validation en VM Hyper-V Windows 11 : 25 contrôles ciblés réussis, dont les valeurs relues, les interrupteurs, les exclusions, les threads créés tardivement, la pause, le retrait du dernier jeu, la conservation de changements externes et une interruption forcée du binaire final suivie d'une récupération. La suite existante passe également (CPU, GPU, profils, restauration, configuration invalide et CSV). Cela ne mesure aucun gain de FPS et ne garantit pas l'accès aux processus protégés par les anti-cheats.

Tests supplémentaires : `Test-Features.ps1 -Toolchain <dossier LLVM-MinGW> -TestRoot <nouveau dossier> -IsolatedVm`. Exécuter uniquement dans une VM de test jetable sans navigateurs ou autres applications réelles : le test utilise les mêmes règles de sélection que le produit. Les sources sont dans `tests/FeatureTests.cpp`. Le script construit un témoin et lance aussi le véritable exécutable du moteur ; l'interruption forcée concerne seulement cette instance de test.

Le code/source et la licence open source de KRNLGame n'ont pas été retrouvés ni vérifiés. Aucun code extrait de son binaire n'est intégré. L'implémentation utilise les API Windows et conserve les dépendances déjà présentes dans Bastos. Aucun pilote, injection, plan d'alimentation ou priorité temps réel n'est ajouté.
# Priorités par jeu — Bastos Game 3.2.0

Pour chaque jeu détecté et autorisé, le moteur applique au minimum la priorité CPU « supérieure à la normale » (ou « élevée » si le profil le demande) et la priorité de planification GPU « haute » du processus via les API D3DKMT de Windows. Un ancien profil CPU « normale » est traité comme « supérieure à la normale » ; les profils « élevée » restent inchangés. Le GPU est interrogé après création de son contexte graphique : s’il n’est pas encore lisible, le moteur réessaie lors des cycles suivants. Pendant la partie, les deux priorités sont revérifiées et réappliquées si le jeu ou un autre logiciel les modifie ; éviter donc une règle concurrente dans Process Lasso. Les valeurs initiales sont journalisées avant la modification, vérifiées après application et restaurées à la fin du suivi, en mode observation, lors d’un changement de profil et après récupération d’une interruption. Un refus de Windows ou de l’anti-cheat est affiché comme tel ; aucun gain de FPS n’est garanti.

# Interface simplifiée — Bastos Game 3.1.0

La fenêtre utilise désormais trois onglets : **Mes réglages**, **Ce qui est appliqué**, **Comparer les performances**. L'état affiché en haut provient du dernier résultat du moteur ; un état trop ancien n'est pas présenté comme actif.

- « Observation globale / session A » devient **Mettre les optimisations en pause**.
- Les priorités sont expliquées : **Normale** = priorité Windows normale, **Modérée** = AboveNormal, **Renforcée** = High. Normale ne désactive pas les autres actions du moteur ; la pause sert à tester sans optimisation.
- **Alléger le lanceur de PUBG** correspond à OptimizeAuxiliary ; **Limiter les autres applications** correspond à OptimizeBackground, qui inclut Discord et les navigateurs.
- Les changements restent en attente jusqu'à **Enregistrer mes réglages**. **Annuler les modifications** recharge les valeurs enregistrées. Un changement de jeu est empêché tant que des modifications restent en attente.
- Les informations techniques se trouvent uniquement dans le deuxième onglet. Le troisième explique les mesures et l'import des deux captures ; l'enregistrement des CSV n'est pas automatisé.
- Les réglages existants sont conservés lors de l'installation. Aucun nouveau réglage système n'est ajouté.

Le code de l'interface est dans `interface.hpp`. Les mécanismes du moteur 3.0 décrits ci-dessous sont conservés.
# Bastos Game 3.0.0 — 5 septembre 2026

Ce dossier contient les sources exactes du moteur Win32 reconstruit. Les sources du précédent exécutable n'ont pas été retrouvées ; son binaire est conservé dans la sauvegarde du déploiement. La version globale de Bastos reste 7.99.

## Utilisation

Double-cliquer sur l'icône Bastos Game près de l'horloge, ou choisir **Détails, profils et comparaison** dans son menu. La fenêtre principale de Bastos conserve ses commandes de démarrage, arrêt, jeux autorisés et exclusions.

- Choisir un jeu dans la liste, puis sa priorité : normale, supérieure à la normale ou élevée. Le réglage par défaut reste élevé afin de reprendre le comportement existant.
- **Observation globale** restaure les réglages de tous les processus avant de les observer sans modification. Un jeu peut aussi être placé individuellement en observation.
- Les auxiliaires PUBG (ExecPubg dans la même installation PUBG) et les autres applications ont deux commandes distinctes. Pour les deux catégories, seule la priorité CPU est réduite. Le réglage des autres applications reprend `OptimizeBackground` de Config.json.
- Chaque action indique la valeur initiale, demandée, relue et son résultat. Un refus Windows reste un refus, même si le jeu est détecté.
- Le moteur journalise avant d'agir et restaure les valeurs d'origine lorsqu'il s'arrête, lorsqu'un jeu est retiré ou quand le profil change. Après interruption, il relit le journal. PID, date de création et chemin doivent correspondre. Une modification externe détectée est conservée. Les restaurations en échec restent dans le journal pour être retentées.

## Comparaison A/B

La version 3 importe les mesures ; elle ne lance pas automatiquement une capture FPS. Faire une capture A avec Observation globale, puis une capture B sans cette option, dans la même scène, à durée égale, sans modifier les autres réglages. Répéter trois fois et comparer les résultats.

Utiliser [PresentMon Console officiel](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md) pour produire un CSV contenant `MsBetweenPresents` (par exemple avec `--v1_metrics`). Exemple à adapter au chemin de l'exécutable PresentMon :

```powershell
& 'CHEMIN\PresentMon.exe' --process_name TslGame.exe --v1_metrics --timed 60 --terminate_after_timed --output_file 'CHEMIN\capture-A.csv'
```

Choisir **Comparer deux CSV** dans Bastos Game : le premier est A, le second B. Le flux application/PID/swapchain contenant le plus de trames est sélectionné séparément dans chaque fichier, et son identité est affichée. Ne pas comparer si ce n'est pas le bon jeu. Les lignes invalides sont exclues et comptées. Au moins 100 trames sont exigées. Les CSV n'enregistrent pas eux-mêmes la preuve des réglages Bastos utilisés.

Définitions : FPS moyen = 1000 / moyenne des temps de trame en ms ; 1 % low = 1000 / moyenne du 1 % de trames les plus lentes (effectif arrondi au supérieur) ; P99 = percentile 99 par rang supérieur. Ces mesures décrivent les présentations de l'application, pas une mesure matérielle de latence d'entrée. Les comparaisons et les historiques de sessions restent en local, dans `%LOCALAPPDATA%\BASTOS\Bastos Game\Sessions`.

## Architecture et limites

- `Config.json` : contrat existant avec Bastos ; jeux, exclusions, activation, lancement automatique et autres applications.
- `Profiles.json` : options nouvelles, distinctes pour que l'ancienne interface ne les efface pas en sauvegardant Config.json.
- `Status.json` v3 : résultats vérifiés, catégories séparées et dernières restaurations. Les champs historiques requis par Bastos sont conservés.
- `Recovery.json` v3 : écrit de façon atomique et durable avant les modifications. Relecture compatible avec le schéma v1 ; l'ancien moteur doit normalement être arrêté proprement avant migration.
- `core.hpp` : détection, API Windows, journal et restauration.
- `main.cpp` : icône, fenêtre de contrôle, comparateur CSV et tests.

La détection de conflit KRNLGame est supprimée. Aucun réglage de partition, démarrage Windows, pilote ou fichier de jeu n'est réalisé. Le moteur ne modifie pas le plan d'alimentation ni MMCSS/DWM : ces anciens indicateurs ne constituent pas une preuve d'amélioration du jeu. Aucune injection et aucune priorité temps réel ne sont utilisées. Une compatibilité universelle avec les anti-cheats n'est pas présumée ; les refus d'accès sont affichés.

Le moteur vérifie les processus toutes les secondes. Les snapshots de statut sont atomiques ; le journal de restauration n'est réécrit que s'il change. Un arrêt forcé est récupérable au prochain démarrage, mais ne peut restaurer immédiatement un processus si aucun moteur ne tourne. Un processus protégé peut refuser l'application ou la restauration ; le résultat le signale.

## Reconstruction

Toolchain : [LLVM-MinGW 20260826 UCRT x86_64](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260826), archive SHA-256 `ae601f4e0f72bbdf441ad2df8bb16f037e2e9251559ea6b37b4057aef39c06c3`.

```powershell
.\build.ps1 -Toolchain 'CHEMIN\llvm-mingw-20260826-ucrt-x86_64'
.\Test-Engine.ps1 -TestRoot 'CHEMIN\tests-bastos-game'
```

Exécutable x64 natif, bibliothèques C++ liées statiquement, API Win32 système. Le moteur utilise la tâche planifiée Bastos existante pour l'élévation ; son manifeste reste `asInvoker`.

Dépendance incluse : nlohmann/json 3.12.0, licence MIT contenue dans `json.hpp`, SHA-256 `aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63`. Les icônes proviennent de Bastos.

## Validation

Tests sur un processus enfant dédié : détection forcée, priorité effectivement appliquée, quatre résultats vérifiés, restauration exacte en observation, changement à chaud, récupération via journal seul, retrait d'un jeu actif, respect d'un changement externe, configuration invalide, suppression du conflit historique, exclusion d'ExecPubg comme jeu, métriques CSV séparant les flux. Ces tests ne constituent pas un benchmark de PUBG.




