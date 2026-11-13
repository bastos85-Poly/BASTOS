# 7.120.68 — contrôle du clavier QWERTY avec Windows français

Erreur réelle du 20 octobre 2026 : opérations de préparation 9ceaf0c9aac149e18ea70f4c75a33ccd puis 7c5f700795ae471eaebd5ba25fe6e098, rejet final « le profil d’installation est différent des options enregistrées ».

Le générateur associait correctement la disposition physique QWERTY américain 00000409 à la langue Windows fr-FR, produisant InputLocale=040C:00000409. Le vérificateur C# comparait cette valeur au choix brut 0409:00000409. Il déclarait donc à tort le profil divergent.

Le vérificateur reconstruit désormais le code attendu avec la même règle que le générateur : identifiant de langue de l’interface Windows, puis identifiant physique complet du clavier. Cette règle s’applique aussi aux attentes enregistrées dans les rapports de reprise. Le contrôle ne se contente pas d’ignorer le préfixe : langue française, toutes les phases XML, compte et nom du PC restent vérifiés. Une disposition américaine ne peut pas être remplacée par une britannique ni par AZERTY. Les dispositions malformées restent refusées.

Reproduction : le nouveau test FR + QWERTY échoue sur le code 7.120.67. Après correction : 63 contrôles du bilan de préparation/vérificateur réussis, dont 12 contrôles supplémentaires clavier/langue. Les tests de cache, intégrité des WIM et sauvegarde de pilotes restent actifs.

Contrôle réel : le média existant de la tentative 7c5f700795ae471eaebd5ba25fe6e098 a passé le vérificateur corrigé, avec relecture des empreintes ISO, WIM et pilotes. Contrôle en lecture seule ; aucun démarrage armé et aucune nouvelle réinstallation lancée. L’ancien rapport d’échec n’est pas modifié.

Aucun réglage de clavier du Windows courant n’a été changé. Il faut fermer et rouvrir Bastos après mise à jour. Le nouveau lancement doit toujours contrôler le média et les options courantes avant tout démarrage ; la présente relecture ne remplace pas la confirmation de réinstallation.
