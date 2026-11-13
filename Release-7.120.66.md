# 7.120.66 — contrôle des pilotes compatible avec Windows PE minimal

La tentative réelle Attempt-dd9bf933c4f74bbfa24913a782419143 s’est arrêtée le 19 octobre 2026 à 15:50:26 (heure de Paris), avant effacement, code 81. Le journal WinPE valide l’index 6 Professional puis signale l’arrêt de précontrôle et la neutralisation de l’autorisation BootOnce. La photo montre findstr non reconnu. Ce défaut appartient au contrôle du marqueur des pilotes, pas au profil propre ni au réglage OOBE.

Le lanceur BASTOS-Start.cmd utilisait deux appels findstr, absent de cette image WinPE. Remplacement par les commandes internes cmd : lecture du marqueur, contrôle de sa valeur 0/1, taille bornée et une seule ligne non vide. Les marqueurs vides, valeurs différentes et lignes supplémentaires sont refusés avant autorisation destructive. Le chemin /InstallDrivers reste cité et les contrôles du manifeste/répertoire des pilotes sont conservés. Aucune copie de findstr depuis le Windows hôte n’est ajoutée.

Le contrôle de repli sur une ancienne image de démarrage compatible rejette désormais tout appel findstr en commande : il ne doit pas réaccepter le lanceur affecté par cette panne si une reconstruction échoue. L’empreinte du nouveau lanceur invalide le cache du démarrage ; une nouvelle préparation est obligatoire. install.wim nettoyé peut rester réutilisable si ses preuves concordent.

Validation : 38 contrôles pilotes, dont exécution de la branche réelle cmd avec PATH vide, choix 0/1 avec CRLF et sans saut de ligne, marqueurs invalides/vides/multilignes et absence de manifeste ; 36 contrôles de cache ; compilation/publication x64. Les exports de pilotes sont simulés ; aucun pilote installé. Aucun Provision/BootOnce relancé, aucun montage WIM, changement de partitions ni redémarrage déclenché pendant la correction. Le démarrage WinPE complet avec le nouveau lanceur reste à confirmer lors d’un nouvel essai.

Utilisation : fermer et rouvrir BASTOS 7.120.66, puis préparer à nouveau Recovery avant toute nouvelle tentative. Relire le Journal après préparation ; le binaire mis à jour seul ne remplace pas le lanceur déjà intégré à boot.wim.
