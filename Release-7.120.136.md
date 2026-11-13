# BASTOS 7.120.136 — candidat local d'installateur

Préparation du 13 novembre 2026. Cette version n'est pas encore une livraison publique validée.

- Installateur Windows 11 x64 dans un seul fichier EXE, avec charge utile embarquée : aucun téléchargement de SDK demandé à l'utilisateur.
- Contrôle du paquet et de chaque fichier par SHA-256 avant installation. Sauvegarde de l'installation précédente et refus des destinations redirigées.
- Un seul raccourci BASTOS ; conservation d'une icône existante valide ou utilisation du logo fourni.
- Reconstruction du programme principal sans symboles privés et du module de jeu 3.6.1 avec remappage des chemins. Sources correspondantes et licences jointes.
- Régénération du manifeste historique avec de vrais séparateurs d'espacement, lisibles au premier démarrage.
- Correction du lanceur de test de reprise pour exécuter sa fixture sous Windows PowerShell sans modifier la stratégie globale de Windows.

Les tests locaux de l'installateur couvrent 14 contrôles, dont installation, mise à jour, sauvegarde, intégrité, archive corrompue et jonctions. Le test natif ouvre les douze pages. La suite de reprise passe 27 contrôles. Les suites d'annulation, du Journal, des messages et du bilan postinstallation passent également. Les tests de sécurité utilisant des liens symboliques nécessitent les privilèges correspondants. La suite moteur complète dépend encore de fixtures de laboratoire non récupérées. Aucune réussite globale de livraison n'est annoncée.

L'installateur ne lance pas BASTOS, n'applique pas d'optimisation et ne réinstalle pas Windows. Les tests de réinstallation restent à effectuer dans une VM dédiée. La construction est marquée LOCAL-CANDIDATE-DO-NOT-PUBLISH ; le garde de livraison reste obligatoire. Le fichier EXE n'est pas signé.

Les controles courants ont ete retablis le 14 novembre : les neuf suites locales passent avec les privileges requis, dont 176 controles du moteur. Le test de l'installateur comporte desormais 17 controles avec la desinstallation. Le resultat de livraison final reste porte par ReleaseStatus.json et le rapport public associe.

