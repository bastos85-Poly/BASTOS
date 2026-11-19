# Nouveautés

## 7.120.139

- Correction des refus « Paramètre incorrect » : les services par utilisateur sont configurés via leur modèle Windows, avec effet à la prochaine session indiqué dans le bilan.
- Les tentatives refusées restées sans effet peuvent être relancées, y compris avec une sauvegarde créée par la 138. Les valeurs initiales restent préservées.
- Refus Windows, modifications externes et autres erreurs affichés séparément en français et en anglais.
- Restauration des modèles et compatibilité des anciennes sauvegardes ; les protections Windows et les pilotes noyau restent respectés.

## 7.120.138

- Tuile **Désactiver les services** dans **Optimisations → Jeux et performances**, disponible en français et en anglais.
- Profil de 152 noms de services issus d’Atom Playbook 0.0.8, toutes catégories facultatives comprises, avec aperçu avant application.
- Sauvegarde locale avant chaque changement et restauration des modes de démarrage, y compris automatique différé. Les changements externes sont préservés.
- Résultats vérifiés après application ; services protégés, absents et pilotes noyau signalés. Aucun service supprimé ni pilote noyau modifié.
- Contrôle du laboratoire compatible avec les PC sans lecteur D:.

Le profil reste facultatif et peut désactiver des fonctions importantes, dont sécurité et mises à jour. [Guide et limites](features/services.md).

## 7.120.137

- Choix Français / English mémorisé, avec changement immédiat de l’interface.
- Traduction de la navigation, des fenêtres, des progressions et résultats générés après les actions.
- Bastos Game reprend la même langue dans la zone de notification et ses réglages.
- Présentation GitHub recentrée sur la réinstallation guidée de Windows sans clé USB.
- Documentation regroupée dans `docs` ; anciennes notes de développement retirées de la racine. L’historique Git conserve les versions précédentes.

Les vérifications du paquet et leurs limites accompagnent chaque téléchargement public dans `VERIFICATIONS.md` et `ReleaseStatus.json`.
