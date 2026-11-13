# Bastos

Application Windows en C#/WPF pour consulter son matériel, gérer ses réglages et préparer ses sessions de jeu.

## Préparation Recovery lorsque C: ne peut pas être réduit

Le moteur en développement utilise d'abord une zone contiguë d'au moins 40 Go déjà non allouée sur le disque Windows. Il crée BASTOS_RECOVERY dans cette zone sans réduire C:. En l'absence d'une telle zone, il conserve le contrôle Windows de la réduction de C: et sa marge de sécurité de 2 Go. Quand la limite exacte peut être mesurée, le résultat l'indique et oriente vers l'installation USB si elle est insuffisante. Le montage temporaire de l'ISO libère D: avant la création de Recovery, puis l'ISO est remontée pour copier les fichiers.

Cette voie permet de réserver l'espace lors d'une installation propre sur un disque réorganisé. Elle ne déplace pas la MFT d'un Windows existant et ne rend pas les données de l'ancien C: récupérables après formatage. Les changements de partitionnement nécessitent les essais du laboratoire VM décrits dans `Build/README-ReleaseValidation.md` avant distribution.

La version 7.120.93 demande explicitement l’édition Windows avant la préparation initiale de BASTOS_RECOVERY lorsque l’ISO en contient plusieurs. Voir Release-7.120.93.md.

La version 7.120.92 débloque la préparation initiale de BASTOS_RECOVERY dans le parcours de réinstallation sans clé USB. Voir Release-7.120.92.md.

La version 7.120.91 étend l'import AMD à tous les réglages graphiques et Windows associés du script Ultimate, avec sauvegarde, contrôle et restauration. Voir Release-7.120.91.md.

La version 7.120.90 corrige l'import graphique en présence d'une sauvegarde AMD créée par une ancienne version, sans effacer cette sauvegarde. Voir Release-7.120.90.md.

La version 7.120.89 adapte l'import des réglages AMD au format du pilote installé, conserve les anciennes sauvegardes après un changement de pilote et vérifie les valeurs après l'import. Voir Release-7.120.89.md.

La version 7.120.88 corrige la détection AMD du parcours graphique allégé et affiche son résultat dans Bastos. Voir Release-7.120.88.md.

La version 7.120.87 ajoute un parcours de pilote graphique allégé pour NVIDIA, AMD et Intel dans « Mise à jour matériel ». Voir Release-7.120.87.md.

La version 7.120.86 ajoute dans « Optimisation carte graphique » un import aperçu/sauvegarde/restauration des réglages AMD, NVIDIA et Intel adaptés de Ultimate. Voir Release-7.120.86.md et ThirdParty/Ultimate-LICENSE.txt.

La version 7.120.85 organise le Nettoyeur en dix rubriques inspirées de Kudu : Système, Navigateurs, Applications, Outils d’IA, Jeux, Corbeille, Raccourcis, Environnement, Bases de données et Traces de confidentialité. Les sous-options sélectionnent réellement les cibles analysées ; les actions spécialisées exigent confirmation et sauvegarde quand elles modifient le Registre ou une base SQLite. La licence MIT de Kudu figure dans ThirdParty/Kudu-LICENSE.txt. Ce dépôt de sources n'est pas un installateur autonome : les outils externes du kit complet ne sont pas tous inclus.

## Interface

Palette sombre bleu ardoise, sélection de navigation accentuée, panneaux arrondis, boutons plus lisibles et repères de focus clavier. Les cartes binaires « Activer / Restaurer » disposent d'un interrupteur : droite pour appliquer, gauche pour restaurer les valeurs précédentes. Les cartes « Activer / Désactiver » utilisent le même contrôle avec leurs commandes d'origine. La position ne change qu'après confirmation du modèle ; un état inconnu est affiché au centre et bloque l'action jusqu'à actualisation.

## Construire

Sur Windows, avec le SDK .NET 8 :

```powershell
dotnet build BASTOS-Native.csproj -c Release
```

Pour compiler un exécutable autonome :

```powershell
dotnet publish BASTOS-Native.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/publish
```

Le résultat doit être assemblé avec les scripts et ressources attendus par le kit. Consulter `README-Build.md` pour son organisation et `Build/README-ReleaseValidation.md` pour la validation complète. Les chemins D: mentionnés dans les documents historiques décrivent une installation de développement ; ils ne sont pas des prérequis à la compilation.

## Validation

`Build/Test-Source.ps1` compile l'application et exécute les tests de présentation des résultats. Les essais de réinstallation et de partitionnement se font uniquement dans le laboratoire prévu par le projet. Un build réussi ne constitue pas une validation de livraison complète.

## Performances en jeu

Aucun gain universel de FPS n'est garanti. Comparer le même jeu, la même scène, les mêmes réglages et plusieurs passages avant/après. Mesurer les temps de trame et les ralentissements, ainsi que les FPS moyens. Conserver une modification seulement si son effet est utile, reproductible et compatible avec le matériel.

## Contribuer

Voir `CONTRIBUTING.md` et `AGENTS.md`. Ne pas inclure de données personnelles, d'images Windows, de journaux de l'utilisateur ou d'identifiants de laboratoire dans le dépôt.

## Licence

La documentation existante indique GPL-3.0-or-later pour le programme intégrant l'adaptation de Rufus. Le texte existant est conservé dans `LICENSE.txt` ; les sources et notices tierces restent dans `ThirdParty/` et `Assets/`. Voir `README-Build.md` pour la provenance de l'adaptation. Ne pas remplacer ces notices par une licence générique.


