# BASTOS 7.120.73 — interrupteurs de tous les réglages réversibles

Les cartes « Appliquer / Restaurer mes valeurs » utilisent maintenant le même interrupteur que les cartes « Activer / Restaurer ». Les sept options compétitives (audio, réseau et jeu) sont incluses. L'interrupteur et son libellé sont alignés à droite dans la carte, avec une marge intérieure cohérente.

Les vues indépendantes sont également converties : profil Ethernet, préférence IPv4, liaisons IPv4 uniquement, curseurs sombres, rendu GPU des applications, veille USB, MTU mesurée, options du plan actif, choix d'apparence, planificateur Quantum et courbe du pointeur. Les choix et valeurs restent configurables avant application. Les boutons de sauvegarde de configuration ou d'application d'une valeur sans action inverse associée restent des actions de formulaire.

Les commandes d'application et de restauration d'origine, leurs sauvegardes, leurs prérequis et leurs confirmations sont conservés. Une restauration reste possible lorsque l'application n'est plus disponible. Les opérations partielles disposant encore d'une sauvegarde affichent « Partiellement appliqué » et permettent la restauration. Une lecture invalide retire l'ancien état confirmé.

Validation locale : compilation/publication x64, 19 contrôles des commandes d'interrupteurs, 73 contrôles WPF de couverture, d'état et d'alignement, contrôles existants de présentation. Les tests utilisent des fixtures sans appliquer de réglage d'optimisation. Les vérifications finales sur le paquet installé et les 114 scripts sont décrites dans le bilan de livraison. Les limites de validation complète en VM déjà documentées restent applicables.
