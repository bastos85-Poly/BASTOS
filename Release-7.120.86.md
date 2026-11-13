# BASTOS 7.120.86 — importation des réglages graphiques

Dans « Optimisation carte graphique », AMD, NVIDIA et Intel disposent désormais d’une carte « Importer les réglages graphiques ». L’aperçu présente les paramètres adaptés du dépôt Ultimate avant confirmation. L’import cible uniquement les clés du constructeur détecté, sauvegarde les valeurs existantes et propose une restauration. Le programme n’exécute pas le script téléchargé du dépôt et ne télécharge pas de pilote dans cette fonction.

Les changements globaux de Windows, l’acceptation automatique de licences, le nettoyage des notifications et le profil NVIDIA Profile Inspector dépendant d’un identifiant GPU fixe ne sont pas importés. Une validation de laboratoire sur VM et un essai d’application/restauration sur carte réelle restent à effectuer.

Source : https://github.com/FR33THYFR33THY/Ultimate, commit a0a33a57078434201f582b0db5107dcbb502292a. Licence MIT dans ThirdParty/Ultimate-LICENSE.txt.
