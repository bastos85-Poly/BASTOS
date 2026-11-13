# 7.120.130 — vérification du profil specialize

Le nouveau parcours de compte sans mot de passe crée le compte dans specialize et omet LocalAccounts de l'OOBE. Le contrôle natif de fin de préparation exigeait encore ce compte OOBE, ce qui plaçait une préparation correcte en état Unconfirmed à 99 %.

Le vérificateur reconnaît désormais le contrat SpecializePasswordlessV1 : profil lié aux options, compte/PC/clavier/langue/édition, empreinte du worker réel, une seule invocation exacte dans specialize sur amd64, absence de second écrivain OOBE et cohérence de l'AutoLogon facultatif. Les médias anciens conservent leur vérification LocalAccounts. Les cas absents, contradictoires ou modifiés restent refusés.

Les tests de cache/vérification couvrent le nouveau parcours et ses divergences. Le même vérificateur a relu et validé la préparation existante d'une tentative utilisateur, sans préparer de média, modifier les partitions ni programmer de redémarrage. Une réinstallation Windows complète de 130 et le garde général de livraison restent non validés.
