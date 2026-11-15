# Réglages Windows — 5 septembre 2026

Cette version conserve la page Bastos Game déjà livrée et remplace uniquement le contenu d’Optimisations > Réglages Windows.

Six éléments sont présentés : HAGS, Mode Jeu Windows, alimentation, nettoyage temporaire, désactivation de la maintenance et des services Windows, autorisation des téléchargements non sûrs sans avertissement. Les quatre autres options de cette catégorie ont été retirées de la liste ; leur retrait ne modifie pas les paramètres Windows déjà appliqués.

Le sélecteur d’alimentation énumère les plans effectivement installés via PowerEnumerate et affiche leurs noms Unicode. Il sélectionne initialement le plan actif. Le choix seul n’applique rien ; Appliquer passe par le worker natif puis relit PowerGetActiveScheme pour vérifier le résultat. Les identifiants invalides et les plans supprimés sont refusés. Actualiser les plans retrouve les nouveaux plans sans changement de code. Les paramètres internes des plans ne sont pas réécrits. Le plan BASTOS 9800X3D Gaming existant est donc conservé.

Sources Microsoft : https://learn.microsoft.com/en-us/windows/win32/power/managing-power-schemes et https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powerenumerate

Base : source de la livraison précédente, correspondant à l’exécutable installé SHA256 30AFE2E1B97BF3804BEE8BB4E1A2C28F77CED7DAFA229F583DCE466FDC25C391.

Compilation : SDK .NET 10.0.11, cible net8.0-windows, win-x64 autonome.
`dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`

Validation : démarrage et navigation sur les douze pages, inspection visuelle et neuf contrôles ciblés. Lecture réelle des plans et du plan actif, refus réel des identifiants invalides ; simulation des demandes d’activation, de leur refus et de l’ajout futur d’un plan. Le plan actif réel est resté identique pendant les tests.
