# BASTOS 7.120.89 — contrôle de l'import graphique

Le module d'import AMD utilisait des valeurs binaires alors que certains pilotes actuels enregistrent ces préférences en chaînes. Il conserve désormais le format trouvé pour chaque valeur. Une sauvegarde créée avec un ancien pilote est archivée avant un nouvel import, afin de capturer les valeurs du pilote courant sans effacer l'ancien état.

Après l'écriture, Bastos relit les réglages et signale toute différence. L'interface les vérifie une seconde fois après 18 secondes pour détecter une réécriture par le logiciel du constructeur. L'action en lecture seule `VerifyImport` permet de refaire le contrôle sans modifier le pilote.

La validation locale couvre la syntaxe du script, un contrôle réel en lecture seule du pilote AMD, la compilation et les tests applicables. Aucun import graphique n'a été lancé sur l'hôte pour valider cette livraison ; la tenue des réglages après redémarrage reste à tester sur une machine de laboratoire.
