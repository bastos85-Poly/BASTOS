# 7.120.128 — finalisation du contrôle de compte et du profil direct

L'installation 127 a ouvert la session BastOS et le Bureau automatiquement,
y compris après un démarrage à froid. La sonde réelle confirme l'identité,
le SID normal -1000, le compte actif et PasswordRequired=false. Windows renvoie
1327 à LogonUser avec le mot de passe vide, et 1326 avec un mot de passe erroné
jamais configuré. Cette restriction de l'API n'est pas une erreur de mot de
passe et n'a pas empêché la connexion console effectivement observée.

Le worker 128 accepte cette preuve différentielle uniquement si le compte ne
requiert pas de mot de passe, si le vide renvoie exactement 1327 et si un secret
aléatoire non configuré est rejeté par 1326. Le reçu distingue ce mode d'une
authentification API réussie. Les autres erreurs restent refusées. Aucune
politique de sécurité n'est modifiée et aucun secret temporaire n'est configuré.

Le bilan Installation-Options de 127 est positif pour les huit groupes demandés.
Le reçu de finalisation manquait cependant parce que Get-Volume avec filtre de
label lançait une exception sur un média direct sans partition BASTOS_RECOVERY.
Le générateur énumère maintenant les volumes puis filtre la collection ;
l'absence de cette partition n'est pas un échec. Une erreur réelle du diagnostic
reste journalisée et bloque la finalisation, afin de ne pas autoriser une
suppression de la partition de récupération après un diagnostic incomplet.
Les erreurs des logiciels/options restent également bloquantes pour ce reçu.

Les tests ajoutent la restriction différenciée, le refus d'une restriction sans
preuve suffisante et le refus d'un compte requérant un mot de passe. Le mock de
volume reproduit désormais l'exception réelle d'une recherche filtrée sans
résultat. La version 128 doit faire l'objet d'une nouvelle installation complète
et d'un contrôle de ses reçus ; cette note n'annonce pas ce résultat à l'avance.
