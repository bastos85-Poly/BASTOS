# Repères pour les assistants de développement

- Projet C#/WPF, net8.0-windows, x64. Scripts Windows PowerShell dans InstallerScripts.
- Lire README.md, docs/BUILD.md et Build/README-ReleaseValidation.md avant de préparer une livraison.
- Préserver les douze destinations et leurs PageKey lors d'un travail visuel. Styles partagés : App.xaml. Fenêtre principale : Bastos.Native.MainWindow.xaml.
- Modifier séparément présentation et actions système. Ne jamais lancer une optimisation, une réinstallation ou une suppression pour vérifier seulement une interface.
- Compiler avec le SDK .NET 8 ; rendre les pages affectées et vérifier la navigation clavier et les états désactivés.
- Pour une modification du moteur, exécuter les suites appropriées dans Tests/Release et le laboratoire requis. Documenter les tests non exécutés.
- Les rapports de performance doivent venir de mesures répétées. Ne pas inventer de FPS, de gain de latence ou de score d'optimisation.
- Préserver LICENSE.txt et les notices tierces. Ne pas intégrer de secrets, de données de la machine, d'ISO ou d'identifiants de VM dans le dépôt.
