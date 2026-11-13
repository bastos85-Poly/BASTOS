# Installateur public BASTOS 7.120.136

Le lanceur WinForms .NET Framework est autonome sur Windows 11 x64. Il embarque l'archive du programme et le script d'installation ; aucun SDK ou runtime .NET 8 à télécharger pour l'utilisateur. Le runtime de l'application est déjà inclus dans le payload.

Le bouton Installer vérifie les SHA-256, extrait dans un dossier provisoire, vérifie chaque entrée, puis installe sous `%LOCALAPPDATA%/Programs/BASTOS`. Une version précédente est conservée en sauvegarde. Le raccourci unique BASTOS reprend une icône valide existante ou le logo fourni. L'installation ne lance ni l'application, ni des optimisations, ni une réinstallation de Windows.

Compilation du programme principal : voir README.md. Préparer un candidat complet à partir du runtime et de ses outils/licences, avec le nouveau programme principal et le module de jeu, puis :

    ./Build/Build-PublicSetup.ps1 -CandidateRoot 'CHEMIN/candidate' -OutputDirectory 'CHEMIN/nouveau-kit'
    ./Build/Installer/Test-Setup.ps1 -KitRoot 'CHEMIN/nouveau-kit' -OutputDirectory 'CHEMIN/nouveaux-tests'

Par défaut la sortie est marquée LOCAL-CANDIDATE-DO-NOT-PUBLISH. Le garde de livraison du projet reste obligatoire. Le lanceur n'est pas signé ; aucun contournement de protection Windows n'est prévu.

Les contrôles utilisent exclusivement `--test-root` et de nouvelles fixtures. `--verify-only` vérifie sans installer. Les journaux de tests restent privés. Une installation GUI réelle, le raccourci réel, la désinstallation et les parcours de réinstallation doivent être vérifiés dans le laboratoire de livraison avant publication.

Une fois le candidat construit, exécuter le laboratoire complet sur ce candidat inchangé, puis `Build/Approve-PublicSetup.ps1 -CandidateRoot ... -KitRoot ... -ReportPath ...`. Cette étape vérifie le garde et les empreintes ; elle ne recrée pas le paquet et refuse un rapport incomplet. Les tests PowerShell 5.1 exigent un dossier suffisamment court pour sa limite de chemins.

Le desinstallateur fourni est reconstruit depuis Uninstall.cs et Uninstall.ps1. Son dossier et ses redirections sont controles avant suppression ; les donnees utilisateur et sauvegardes restent hors perimetre. Le chemin d'un processus eleve illisible interdit une mise a jour/desinstallation reelle plutot que de laisser un raccourci casse.

