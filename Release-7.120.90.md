# BASTOS 7.120.90 — sauvegardes de réglages graphiques

L'import graphique échouait avec « La propriété Targets est introuvable » lorsqu'une sauvegarde au format 1 existait déjà. Le programme reconnaît maintenant ce format, archive la sauvegarde historique et crée une sauvegarde du pilote courant avant d'appliquer les réglages. Une sauvegarde au format 2 est comparée aux cibles actuelles ; un fichier incomplet est refusé avec un message explicite.

Le correctif a été vérifié avec des sauvegardes fictives aux formats 1 et 2, ainsi qu'avec les contrôles de syntaxe et d'intégrité du paquet. La carte graphique de l'hôte n'a pas été modifiée pendant les tests.
