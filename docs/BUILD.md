# Construire BASTOS

## Application Windows

Sur Windows x64 avec le SDK .NET 8, depuis la racine du dépôt :

```powershell
dotnet publish BASTOS-Native.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/publish
```

Installer le résultat dans `Bastos.Native/BASTOS-Native.exe` d’un runtime BASTOS complet. Les scripts de `InstallerScripts` sont placés à la racine de ce runtime ; leurs modules restent à côté des scripts. Les ressources et outils tiers gardent leurs licences et leur disposition. Le dépôt seul ne reconstruit pas tous les outils indépendants du kit.

## Bastos Game

Voir [le guide du moteur](../Bastos.Game.Source/README.md). Le script `Bastos.Game.Source/build.ps1` accepte le chemin de la toolchain LLVM-MinGW. Il embarque les catalogues de traduction principal et spécifique au module.

## Tests et publication

`Build/Test-Source.ps1` compile et vérifie la présentation. Les tests des langues sont décrits dans [INTERFACE-LANGUAGES.md](INTERFACE-LANGUAGES.md).

Une compilation réussie ne suffit pas pour une livraison. Suivre [la validation complète](../Build/README-ReleaseValidation.md), puis construire et approuver le paquet avec les scripts `Build/Build-PublicSetup.ps1` et `Build/Approve-PublicSetup.ps1`. Les preuves privées et médias Windows ne doivent jamais être publiés.

## Documentation fonctionnelle

- [Bastos Game](features/game.md)
- [Réglages gaming](features/competitive.md)
- [Réglages Windows](features/windows-settings.md)
- [Personnalisation et outils](features/extras.md)
- [Courbes de souris](features/mouse-curves.md)
- [Curseurs](features/cursors.md)

Les guides fonctionnels peuvent décrire des évolutions historiques ; les avertissements et le bilan de l’application restent à consulter avant une action système.
