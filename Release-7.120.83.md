# BASTOS 7.120.83 — Nettoyeur plus complet

Le réglage conseillé protège désormais la dernière heure, comme Kudu 3.10.0, au lieu de 24 heures. Les préférences de 7.120.82 qui conservaient le défaut de 1 jour sont migrées vers 0 jour supplémentaire ; les âges personnalisés et les exclusions restent conservés. Le bouton « Conseillées » remet aussi ce réglage à zéro.

L’aperçu peut inclure les caches ouverts avec partage de lecture ; la suppression reste exclusive et revérifie le chemin, l’identité native, la date, la taille et le SHA-256. La limite d’inventaire monte à 250 000 objets. Sont ajoutés les journaux Windows Update DataStore, le cache Windows/Caches, les données du Moniteur de fiabilité et les journaux AppCompat de type log/etl. Les zones sensibles non assimilables à un cache (Windows.old, historique Defender, cache MSI de restauration) restent hors suppression directe.

Validation locale : 33 contrôles moteur, 16 contrôles avancés, 50 contrôles WPF et navigation. Aucune suppression réelle sur le poste ; mesure de fichiers en lecture seule. Le laboratoire VM complet de réinstallation n’a pas été exécuté.