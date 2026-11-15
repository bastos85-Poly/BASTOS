# Page Bastos Game intégrée — 5 septembre 2026

Cette modification concerne la page Bastos Game de BASTOS-Native, dans la navigation principale.
La fenêtre séparée du moteur Game 3.1 reste disponible.

Base : sources de la version installée le 4 septembre, dont la DLL compilée correspond exactement à la DLL extraite de l’exécutable installé (SHA256 8B040CA5810E7019EB3C0EFCE966DBF296844B375FDB6E22867DC1D2A24F761F).
La copie sur D: était plus ancienne ; cette livraison conserve les fonctionnalités de la copie installée, puis synchronise les quatre copies de l’application.

Modifications limitées à MainWindow.xaml (insertion de la page), PageViewModel.cs (visibilité), MainViewModel.cs (modèle de réglages et sous-titre), et aux nouveaux GamePage.xaml, GamePage.xaml.cs, GamePageViewModel.cs.

La page utilise la largeur disponible, présente l’état récent du moteur, les jeux et les exclusions, et permet de régler la détection, la priorité CPU par défaut, le traitement de l’arrière-plan, le mode observation et les auxiliaires PUBG. Le bouton Appliquer enregistre les choix ; aucune modification des réglages lors de l’ouverture de la page. Les profils propres aux jeux et les champs inconnus sont conservés. État relu toutes les deux secondes lorsque la page est visible ; après dix secondes sans état valide, aucun fonctionnement n’est confirmé.

Compilation : .NET SDK 10.0.11, cible net8.0-windows, Windows x64 autonome.
`dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`

Validation : compilation, démarrage et navigation sur les douze pages via --smoke-test, inspection visuelle de la page, huit contrôles isolés de lecture/enregistrement/préservation des réglages et de fraîcheur du statut. Le moteur Game n’est pas modifié par cette livraison. Aucun gain de FPS n’a été mesuré.
