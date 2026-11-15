# Bastos 7.120.38 — optimisations pour les jeux

Les commandes sont ajoutées à Optimisations. La navigation et la lecture des états n'appliquent aucun de ces nouveaux réglages.

| Catégorie | Option | Action |
|---|---|---|
| Son | Audio pour les jeux compétitifs | Choisit du PCM à 48 kHz / 24 bits utiles (conteneur 24 ou 32 bits), avec repli à 16 bits, après vérification matérielle en mode exclusif. Conserve les canaux et désactive les effets et le spatial accessibles. Ne force aucune période globale. |
| Son | Garder le codec audio éveillé | ConservationIdleTime, PerformanceIdleTime et IdlePowerState à zéro sur les pilotes audio présents. |
| Carte réseau | Traitement rapide des petits paquets UDP | FastSendDatagramThreshold et FastCopyReceiveThreshold à 1 500 sous AFD. Les réglages du pilote réseau restent indépendants. |
| Jeux et performances | Souris 1 000–8 000 Hz | MouseDataQueueSize = 1 024 ; aucune modification du polling USB ni du clavier. |
| Jeux et performances | Timers pour les jeux | GlobalTimerResolutionRequests = 1 et disabledynamictick = yes pour l'entrée de démarrage courante ; aucune modification de HPET, TSC, NX ou résolution permanente à 0,5 ms. |
| Jeux et performances | Interface Steam | Enregistre GPUAccelWebViewsV3=0 (DWORD) dans HKCU\Software\Valve\Steam si Steam est installé pour cet utilisateur. Cette préférence est celle enregistrée par le client Steam actuel via Interface > rendu accéléré GPU désactivé. Elle persiste après redémarrage et ne dépend pas du raccourci. Ajoute aussi -cef-disable-gpu aux démarrages automatiques et raccourcis Steam existants, en conservant leurs autres arguments ; ne crée pas d'autostart, ne ferme pas Steam et ne lance pas les jeux. |
| Jeux et performances | SDL3 | Variables utilisateur SDL_WINDOWS_RAW_KEYBOARD=1, SDL_WINDOWS_RAW_MOUSE_NOLEGACY=1, SDL_WINDOWS_CLOSE_ON_ALT_F4=1. Seuls les jeux utilisant une version de SDL compatible sont concernés ; NOLEGACY nécessite SDL 3.6 ou ultérieure. |

## Application et restauration

Chaque option s'applique séparément avec Appliquer et dispose de Restaurer mes valeurs. Les commandes sont vérifiées par le catalogue d'intégrité embarqué de Bastos. Les résultats détaillés sont enregistrés dans les journaux locaux de Bastos.

Manage-BASTOS-Competitive.ps1 sauvegarde les valeurs et types initiaux avant toute écriture. Les journaux sont atomiques et vidés sur disque, sous ProgramData\BASTOS\CompetitiveTuning\SID. Un mutex empêche deux commandes de cette famille de se modifier simultanément. Une nouvelle application ne remplace pas la sauvegarde originale. Les changements externes sont conservés lors de la restauration ; les erreurs de restauration restent sauvegardées pour réessai.

Pour l'audio, tous les champs lisibles sont sauvegardés avant la première modification, car changer le format peut réinitialiser les effets ou la période. La restauration vérifie l'appartenance des valeurs avant de restaurer le premier champ. Un périphérique débranché ou inaccessible garde ses entrées en attente. Les périphériques incompatibles avec le format demandé sont laissés inchangés. Le résultat est partiel lorsque certains paramètres ne peuvent pas être confirmés.

L'adaptateur audio est une implémentation C# indépendante via Core Audio et les interfaces de politique audio Windows. Certaines de ces interfaces sont non documentées et peuvent être refusées ou évoluer ; les appels et valeurs relues sont contrôlés. Aucun exécutable de KirbyOS, service LowAudioLatency ou pilote tiers n'est installé. La période reste gérée par Windows et les applications : la méthode de réglage globale était refusée par les pilotes du PC. Les anciennes entrées de sauvegarde restent restaurables.

Les réglages peuvent augmenter la consommation ou modifier le fonctionnement des effets audio. Aucun gain de FPS, de ping ou de régularité des temps de trame n'est garanti. Les besoins de redémarrage ou de nouvelle session sont indiqués dans l'interface. Les options n'ont pas été activées en bloc sur le PC de l'utilisateur lors de la livraison.

## Validation

- Compilation WPF .NET 8, publication autonome x64.
- 38 contrôles en VM Hyper-V : lecture sans modification, application vérifiée, sauvegarde avant écriture, idempotence, restauration des types d'origine, conservation des changements externes, BCD, SDL3, codec sur pilote témoin, arguments et raccourcis Steam.
- Les tests audio simulés valident aussi la migration d'une ancienne cible non appliquée sans écraser les valeurs originales.
- Application réelle et relecture sur le PC après la demande de correction : deux sorties PCM 48 kHz / 24 bits utiles dans un conteneur 32 bits, microphone PCM 48 kHz / 16 bits, améliorations désactivées. Six réglages appliqués et vérifiés. Le spatial non exposé est signalé. Les valeurs originales sauvegardées lors de la première application sont conservées.
- Test d'interface en VM : sept options réparties 2/1/4, navigation Son/Réseau/Jeux, lecture des résultats via le contrôle d'intégrité et captures d'écran. La VM sans audio physique signale correctement l'absence de cible compatible.

Les sources de tests sont dans Tests/Competitive. Exécuter uniquement dans la VM de laboratoire prévue : le test modifie puis restaure de vrais réglages Windows et utilise des pilotes et raccourcis témoins. Les contrôles d'interface sont accessibles via --competitive-smoke-test dans une copie de laboratoire de l'application complète.

La préférence Steam précédente (valeur, type ou absence) est sauvegardée avant modification et restaurée par Restaurer mes valeurs. Si Steam est ouvert, un seul redémarrage de Steam est nécessaire après la première application; aucun redémarrage manuel supplémentaire n'est requis après un redémarrage du PC. Pas de fermeture forcée du client ou des jeux.
