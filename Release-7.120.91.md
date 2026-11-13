# BASTOS 7.120.91 — profil AMD complet d'Ultimate

L'import AMD reprend les réglages du script Ultimate concernant le pilote, AMD Software et les réglages Windows associés : Anti-Lag, V-Sync, filtrage, tessellation, Vari-Bright lorsqu'il existe, résolutions personnalisées et dérogations d'affichage, notifications, gestion des couleurs des écrans, mode MSI des GPU et visibilité des icônes de la barre des tâches. L'aperçu indique le nombre de cibles détectées et mentionne explicitement que les deux indicateurs AMD d'acceptation des conditions d'affichage seront modifiés. Les étapes de téléchargement et d'installation du pilote, les raccourcis, le redémarrage et la configuration de 7-Zip ne sont pas des réglages graphiques importés.

Chaque valeur est sauvegardée avant modification. La sous-clé de notifications est sauvegardée en entier avant sa remise à zéro et peut être restaurée. Les nouvelles cibles apparues depuis la sauvegarde précédente sont ajoutées à celle-ci sans perdre les valeurs d'origine. Le contrôle après import signale les valeurs non conservées par le pilote ou AMD Software.

Validation locale : vérification en lecture seule des cibles AMD, tests de sauvegarde et restauration sur une sous-clé HKCU temporaire, migration de sauvegarde v1/v2 et ajout de nouvelles cibles. Aucun réglage de la carte graphique de l'hôte n'a été modifié pour les tests.
