# Préparer une publication GitHub

Utiliser un dépôt neuf avec les sources exportées, sans reprendre l'ancien dossier du Bureau, les résultats de tests, l'historique personnel ou les données de laboratoire.

## Procédure de livraison

1. Construire le programme principal et le module de jeu sans symboles ni chemins personnels.
2. Assembler un runtime avec les outils tiers, leurs notices et leurs sources applicables. Le kit comporte notamment les sources GPL du module de jeu, de Scaled Resolution Editor et de Radeon Software Slimmer.
3. Construire l'installateur et sa copie de sources avec Build/Build-PublicSetup.ps1. La sortie est un candidat local, jamais automatiquement validé.
4. Passer les tests de l'installateur, les suites C#/WPF et les contrôles de VM du projet. La réinstallation doit utiliser une VM dédiée, isolée du réseau et des disques physiques, avec une baseline privée connue et un retour à l'état initial.
5. Exécuter Build/Approve-PublicSetup.ps1 avec le rapport complet récent et le candidat inchangé. Un échec, une suite manquante ou un binaire modifié bloque l'approbation.
6. Recontrôler les secrets, les archives et les empreintes du contenu réellement publié. Ne pas téléverser les journaux bruts du laboratoire.
7. Publier les sources, puis une Release avec l'installateur validé, la notice, les licences, les empreintes et un résumé public des vérifications. Le résultat réel figure dans ReleaseStatus.json et le rapport public de livraison, pas dans une promesse de ce document.

## Compte et confidentialité

Destination prévue : bastos85-Poly/BASTOS. Utiliser une adresse de commit GitHub noreply. Activer les protections de secrets disponibles et examiner les fichiers ajoutés ainsi que les pièces jointes des Releases. Une compilation CI réussie ne remplace pas la validation de réinstallation.

Le lien de soutien https://ko-fi.com/bastos85 est public et présent dans .github/FUNDING.yml. Il ne nécessite aucune clé Ko-fi.

## Évolution des sources récupérées

Le fichier discovery.hpp du module de jeu manquait : il a été reconstitué, avec 20 tests sur fichiers témoins et un remappage des chemins de compilation. Les sources du nouvel installateur/désinstallateur sont fournies. Le harnais WebView2 manquant a été rétabli pour simuler le lancement et les lectures Windows, tout en gardant les téléchargements et vérifications Microsoft réels. Les identifiants privés de laboratoire sont conservés à part et ne doivent pas être ajoutés au dépôt.
