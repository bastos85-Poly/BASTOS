<p align="center"><img src="docs/images/bastos-logo-officiel.png" alt="Logo officiel BASTOS, identique à celui de l’application" width="100%"></p>

<p align="center"><img src="docs/images/bastos-banner.svg" alt="Windows sans clé USB. Préparez votre PC. Libérez son potentiel gaming." width="100%"></p>

<p align="center"><a href="https://github.com/bastos85-Poly/BASTOS/releases/latest"><strong>Télécharger BASTOS</strong></a> · <a href="https://github.com/bastos85-Poly/BASTOS/issues">Faire un retour</a> · <a href="https://ko-fi.com/bastos85">❤️ Soutenir sur Ko-fi</a></p>

# Réinstallez Windows facilement, même sans connaissances techniques

### Sans clé USB ni matériel supplémentaire pour l’installation. Un parcours guidé en français.

> **Mon premier programme, un projet qui grandit avec vous.** BASTOS est encore en cours de développement. Vos retours, vos partages et votre soutien sur [Ko-fi](https://ko-fi.com/bastos85) m’aident à le faire progresser et à y consacrer davantage de temps.

**Pas besoin de savoir créer une clé USB bootable ou préparer les fichiers d’installation à la main. Choisissez votre Windows et laissez-vous guider, étape par étape.** BASTOS rassemble le téléchargement, les contrôles et la préparation dans une même application en français, directement depuis votre PC.

L’objectif est simple : **rendre la réinstallation de Windows accessible, même si vous ne l’avez jamais faite.** Vous choisissez parmi les Windows proposés, BASTOS vous accompagne dans la préparation, puis vous consultez le bilan avant de confirmer. Les contrôles indiquent si votre PC remplit les conditions nécessaires.

**Et après ?** Retrouvez les optimisations gaming, la personnalisation de Windows et l’installation de vos logiciels au même endroit.

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
2. Téléchargez **BASTOS-Setup-7.120.137.exe** pour cette version. Le fichier « Source code » est destiné au développement.
3. Fermez BASTOS s’il est déjà ouvert, puis lancez l’installateur.
4. Retrouvez **un seul raccourci BASTOS sur le Bureau**, ouvrez l’application et choisissez les fonctions qui vous intéressent.

**Configuration : Windows 11 x64.** Le runtime est inclus. Installer BASTOS n’applique aucun réglage Windows et ne lance pas une réinstallation du système. Les actions nécessitant des droits administrateur restent soumises à l’autorisation de Windows.

Les exécutables ne sont actuellement **pas signés** : Windows peut afficher un avertissement. Vérifiez la provenance du téléchargement et les empreintes fournies dans **SHA256SUMS.txt**.

## Un projet à faire progresser ensemble

Les vérifications et leurs limites sont détaillées dans **VERIFICATIONS.md**, joint à la [version publiée](https://github.com/bastos85-Poly/BASTOS/releases/latest). Les tests ne couvrent pas toutes les configurations matérielles.

**Français ou English : à vous de choisir.** Le menu en haut à droite change la langue de l’interface et mémorise votre préférence. Bastos Game, dans la zone de notification, reprend ce même choix. La langue de l’interface ne change pas le Windows que vous choisissez de télécharger.

Un problème, une idée ou un logiciel qui ne s’installe pas ? [Ouvrez une issue](https://github.com/bastos85-Poly/BASTOS/issues) en indiquant la version de BASTOS, l’action tentée, le résultat attendu et le message obtenu. Masquez vos données personnelles dans les captures. Ne joignez aucun journal brut, mot de passe ou clé de récupération BitLocker.

## Avant une réinstallation de Windows

Ce parcours modifie le système et les partitions : **sauvegardez vos données sur un autre support avant de le confirmer**. La partition **D: BASTOS_RECOVERY** est temporaire. Après vérification du premier démarrage, son espace est automatiquement rendu à C: et WinRE est recréé. **Les données restant sur ce D: seront effacées.** Consultez le bilan affiché dans l’application avant de lancer ce parcours.

La désinstallation de BASTOS conserve les données et les sauvegardes ; elle ne restaure pas automatiquement les réglages que vous avez appliqués.

## Soutenir le développement

**BASTOS est mon premier programme.** Je le développe avec l’envie de rendre la réinstallation de Windows plus accessible et de proposer des outils utiles pour le gaming et la personnalisation. Le projet est encore en cours de développement : il évolue, et des bugs peuvent subsister malgré les tests.

J’aimerais pouvoir **m’investir à fond dans BASTOS**. Pour cela, j’ai besoin de soutien : vos dons peuvent m’aider à dégager plus de temps pour développer les fonctionnalités, corriger les problèmes et poursuivre les tests.

Vous pouvez aussi m’aider sans faire de don : en partageant le projet, en signalant un bug avec des explications précises ou en proposant une amélioration. Merci à celles et ceux qui participent à cette aventure.

**[❤️ Offrir un coup de pouce sur Ko-fi](https://ko-fi.com/bastos85)** — le soutien est facultatif.

## Sources, licence et confidentialité

Les sources principales sont disponibles sous **GPL-3.0-or-later** ; les composants tiers conservent leurs licences propres. Le projet utilise C#/WPF et .NET 8 x64, avec un module de jeu C++.

- [Installation et construction des sources](docs/INSTALLATION-ET-SOURCES.md)
- [Guide de construction](docs/BUILD.md) et [validation des livraisons](Build/README-ReleaseValidation.md)
- [Contribuer](CONTRIBUTING.md)
- [Nouveautés](docs/CHANGELOG.md) et [langues de l’interface](docs/INTERFACE-LANGUAGES.md)
- [Confidentialité](CONFIDENTIALITE.md) et [signalement de sécurité](SECURITY.md)
- [Licence](LICENSE.txt)

Le dépôt et les fichiers publiés ont fait l’objet d’une revue de confidentialité. Les journaux personnels, sauvegardes et médias Windows sont exclus. Cette revue ne garantit pas l’absence de vulnérabilités.
