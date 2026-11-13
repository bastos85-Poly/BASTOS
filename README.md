# BASTOS

Application Windows en français : réglages, logiciels, diagnostic et préparation de réinstallation. Windows 11 x64.

## Utiliser BASTOS

Lorsqu'une version validée est disponible, télécharger **BASTOS-Setup-7.120.136.exe** depuis les Releases du dépôt. Fermer BASTOS avant une mise à jour, puis lancer l'installateur et choisir Installer. Un seul raccourci BASTOS est créé sur le Bureau. L'application apparaît aussi dans les applications installées de Windows.

L'installation n'applique aucun réglage Windows. Les actions administrateur de BASTOS restent soumises à l'autorisation Windows. La désinstallation conserve les données et sauvegardes ; elle ne restaure pas automatiquement les réglages appliqués auparavant.

Un fichier ReleaseStatus.json dont FullReleaseGatePassed vaut true et les empreintes SHA256SUMS accompagnent la Release validée. Un paquet marqué LOCAL-CANDIDATE-DO-NOT-PUBLISH est un candidat de développement. Les binaires de cette préparation ne sont pas signés.

## Sources et construction

Le dépôt comprend les sources principales C#/WPF (.NET 8 x64), le module de jeu C++, l'installateur/désinstallateur et les scripts/tests. Il ne contient ni historique personnel, journaux du PC, captures de tests, sauvegardes, identifiants privés de VM ou ISO Windows. Les outils historiques et tiers ne se reconstruisent pas tous avec ce seul dépôt ; leurs notices et, lorsque nécessaire, leurs sources accompagnent le kit binaire.

    dotnet publish BASTOS-Native.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/publish

Les symboles sont retirés et les chemins remappés pour éviter d'inscrire le profil personnel du développeur. Voir Bastos.Game.Source, Build/Installer/README.md et Build/README-ReleaseValidation.md. Le laboratoire se configure séparément, sans inclure ses identifiants privés dans le dépôt.

## Confidentialité et sécurité

Voir SECURITY.md, CONFIDENTIALITE.md et PUBLICATION.md. Ne publier aucun journal brut, mot de passe, clé BitLocker, profil navigateur ou export personnel dans les issues. La revue de confidentialité ne prouve pas l'absence de vulnérabilités.

## Licence et soutien

Sources principales sous GPL-3.0-or-later selon le projet d'origine ; texte dans LICENSE.txt. Les outils et bibliothèques indépendants conservent leurs licences et attributions propres. Les notices accompagnent le runtime.

Soutenir le développement : https://ko-fi.com/bastos85
