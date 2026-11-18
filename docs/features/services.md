# Désactiver les services — profil Atom

Dans **Optimisations → Jeux et performances**, la tuile avec une roue dentée ouvre **Désactiver les services**. L’ouverture lance uniquement une analyse.

Le catalogue reprend les 152 noms distincts visés par les désactivations ou suppressions de services d’Atom Playbook 0.0.8, toutes catégories facultatives comprises. BASTOS les traite comme une demande de désactivation du démarrage : aucun service n’est supprimé.

## Appliquer

1. Relire la liste des services détectés et leur démarrage actuel.
2. Cliquer sur **Désactiver les services** et confirmer le profil complet.
3. Consulter les résultats : chaque changement est relu et vérifié. Les services absents, pilotes noyau et refus de Windows sont indiqués.
4. Redémarrer Windows lorsque vous êtes prêt. BASTOS ne force pas de redémarrage et n’arrête pas les services en cours d’exécution.

Ce profil est agressif. Il inclut des services liés à la sécurité, Windows Update, Bluetooth, impression, Xbox, notifications, sauvegardes, heure et Bureau à distance. Certaines fonctionnalités deviennent indisponibles après arrêt des services ou redémarrage. Aucun gain de FPS n’est garanti.

## Restaurer

**Restaurer le démarrage** remet les valeurs sauvegardées, y compris le démarrage automatique différé. Un service déjà désactivé avant l’application reste désactivé. Les changements faits entre-temps par un autre outil sont signalés plutôt qu’écrasés. Un redémarrage peut être nécessaire pour relancer les fonctions concernées.

La sauvegarde locale est écrite avant chaque changement sous `ProgramData\BASTOS\ServiceProfiles`, dans un dossier protégé propre au compte. Réappliquer le profil ne remplace pas les valeurs initiales sauvegardées. Une interruption laisse les sauvegardes disponibles pour restauration.

## Limites

Les services protégés par Windows ou la protection contre les falsifications peuvent refuser le changement. BASTOS ne contourne pas ces protections et ne présente pas ces refus comme des réussites. Les pilotes noyau, y compris ceux cités dans Atom, sont exclus : le profil ne modifie que les services recensés par `Win32_Service`.

Le bouton ne reproduit pas les autres modifications d’Atom : suppression d’applications, réglages réseau, démarrage système, nettoyage de fichiers, désactivation de Smart App Control ou suppression de WinRE.

L’interface est disponible en français et en anglais. Les noms système et diagnostics bruts restent tels que Windows les fournit.
