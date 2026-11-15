<p align="center"><img src="docs/images/bastos-banner.svg" alt="BASTOS — Votre PC, vos réglages" width="100%"></p>

<p align="center"><a href="https://github.com/bastos85-Poly/BASTOS/releases/latest"><strong>Télécharger BASTOS</strong></a> · <a href="https://github.com/bastos85-Poly/BASTOS/issues">Faire un retour</a> · <a href="https://ko-fi.com/bastos85">❤️ Soutenir sur Ko-fi</a></p>

# Réinstallez Windows sans clé USB avec BASTOS

**Choisissez le Windows à télécharger, puis préparez et lancez sa réinstallation directement depuis votre PC, sans clé USB.** C’est le point fort de BASTOS : réunir ces étapes dans un parcours en français, avec un bilan avant de lancer l’installation.

## Comment fonctionne l’installation sans clé USB ?

1. **Choisissez votre Windows.** Sélectionnez la version proposée, l’édition et la langue selon les choix disponibles. BASTOS vous accompagne pour télécharger l’image Windows depuis Microsoft ; vous pouvez aussi sélectionner une ISO compatible déjà téléchargée.
2. **Préparez l’installation sur le PC.** BASTOS vérifie l’image et les conditions nécessaires, puis prépare une zone temporaire sur le disque interne pour les fichiers d’installation. Vous n’avez pas de clé USB à créer pour ce parcours.
3. **Vérifiez le bilan et lancez la réinstallation.** Après votre confirmation, le PC redémarre dans l’environnement d’installation. Une fois le premier démarrage vérifié, l’espace temporaire est rendu à C: et l’environnement de récupération Windows est recréé.

Ce parcours nécessite un Windows encore accessible pour la préparation, un disque compatible et suffisamment d’espace disponible. Les contrôles de BASTOS déterminent si votre PC peut l’utiliser. **Sauvegardez vos données sur un autre support avant de confirmer une réinstallation.** Le choix d’une édition ne fournit pas de licence Windows ; son activation nécessite une licence adaptée.

## Ensuite, un Windows à votre goût, prêt pour vos jeux

BASTOS propose aussi des **optimisations pour votre environnement gaming**, des **personnalisations Windows** et un **catalogue de logiciels**. Choisissez les réglages utiles à votre configuration, adaptez l’apparence et retrouvez vos outils habituels depuis la même application.

## Ce que vous pouvez faire

| Votre besoin | Ce que propose BASTOS |
| --- | --- |
| **Installer Windows sans clé USB** | Choix du Windows à télécharger, préparation sur le disque interne, contrôles et bilan avant de lancer la réinstallation. |
| **Optimiser votre environnement gaming** | Des réglages Windows et des outils liés au jeu et au matériel, à choisir selon votre configuration. Les gains dépendent du PC et des jeux ; aucun gain universel de FPS n’est garanti. |
| **Personnaliser Windows** | Mode sombre, transparence, Explorateur et autres réglages Windows dans une interface commune. |
| **Installer vos logiciels** | Un catalogue pour sélectionner et lancer l’installation de vos applications. Une connexion Internet est nécessaire ; certains éditeurs demandent une interaction. |
| **Comprendre votre PC** | Des informations sur le matériel et des outils de diagnostic, avec un journal pour consulter les résultats et les erreurs. |

![Choisir Windows, préparer le disque et installer sans clé USB](docs/images/bastos-parcours.svg)

*Ces visuels sont des illustrations de présentation, pas des captures de l’application.*

## Essayer BASTOS

1. Ouvrez la [dernière version publiée](https://github.com/bastos85-Poly/BASTOS/releases/latest).
2. Téléchargez **BASTOS-Setup-7.120.136.exe** pour cette version. Le fichier « Source code » est destiné au développement.
3. Fermez BASTOS s’il est déjà ouvert, puis lancez l’installateur.
4. Retrouvez **un seul raccourci BASTOS sur le Bureau**, ouvrez l’application et choisissez les fonctions qui vous intéressent.

**Configuration : Windows 11 x64.** Le runtime est inclus. Installer BASTOS n’applique aucun réglage Windows et ne lance pas une réinstallation du système. Les actions nécessitant des droits administrateur restent soumises à l’autorisation de Windows.

Les exécutables ne sont actuellement **pas signés** : Windows peut afficher un avertissement. Vérifiez la provenance du téléchargement et les empreintes fournies dans **SHA256SUMS.txt**.

## Un projet à faire progresser ensemble

La version **7.120.136** a passé les 13 groupes de validation de livraison, avec 21 contrôles de réinstallation réelle et 12 contrôles du paquet final dans une machine virtuelle dédiée. Le test de réinstallation a repris après une pause, après vérification des 499 fichiers sources inchangés. Ces essais ne couvrent pas toutes les configurations matérielles : les détails et limites figurent dans **VERIFICATIONS.md**, joint à la [version publiée](https://github.com/bastos85-Poly/BASTOS/releases/tag/v7.120.136).

Un problème, une idée ou un logiciel qui ne s’installe pas ? [Ouvrez une issue](https://github.com/bastos85-Poly/BASTOS/issues) en indiquant la version de BASTOS, l’action tentée, le résultat attendu et le message obtenu. Masquez vos données personnelles dans les captures. Ne joignez aucun journal brut, mot de passe ou clé de récupération BitLocker.

## Avant une réinstallation de Windows

Ce parcours modifie le système et les partitions : **sauvegardez vos données sur un autre support avant de le confirmer**. La partition **D: BASTOS_RECOVERY** est temporaire. Après vérification du premier démarrage, son espace est automatiquement rendu à C: et WinRE est recréé. **Les données restant sur ce D: seront effacées.** Consultez le bilan affiché dans l’application avant de lancer ce parcours.

La désinstallation de BASTOS conserve les données et les sauvegardes ; elle ne restaure pas automatiquement les réglages que vous avez appliqués.

## Soutenir le développement

BASTOS est un projet indépendant. Si l’application vous est utile, un don peut aider à poursuivre son développement et ses tests. Vous pouvez aussi contribuer avec un retour précis ou une proposition d’amélioration.

**[❤️ Offrir un coup de pouce sur Ko-fi](https://ko-fi.com/bastos85)** — le soutien est facultatif.

## Sources, licence et confidentialité

Les sources principales sont disponibles sous **GPL-3.0-or-later** ; les composants tiers conservent leurs licences propres. Le projet utilise C#/WPF et .NET 8 x64, avec un module de jeu C++.

- [Installation et construction des sources](docs/INSTALLATION-ET-SOURCES.md)
- [Guide de construction](README-Build.md) et [validation des livraisons](Build/README-ReleaseValidation.md)
- [Contribuer](CONTRIBUTING.md)
- [Confidentialité](CONFIDENTIALITE.md) et [signalement de sécurité](SECURITY.md)
- [Licence](LICENSE.txt)

Le dépôt et les fichiers publiés ont fait l’objet d’une revue de confidentialité. Les journaux personnels, sauvegardes et médias Windows sont exclus. Cette revue ne garantit pas l’absence de vulnérabilités.
