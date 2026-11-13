# Bastos 7.120.39 — ajouts issus de l'inspection de KirbyOS

Les scripts tiers ne sont pas exécutés ou embarqués. L'implémentation Bastos est indépendante et les fonctions déjà disponibles sont réutilisées.

| Emplacement | Fonction | Commande et propriété possédées |
|---|---|---|
| Optimisations > Jeux et performances | Rendu des applications en arrière-plan : Chrome, Firefox, Discord | Manage-BASTOS-Extras.ps1 ; une préférence par application. Steam reste dans sa carte existante. |
| Optimisations > Carte réseau | Diagnostic MTU IPv4 et application facultative par carte | Manage-BASTOS-Extras.ps1 ; NlMtu uniquement, ActiveStore/PersistentStore sauvegardés séparément. |
| Optimisations > Périphériques | Veille USB WDF par instance exposée | Manage-BASTOS-Extras.ps1 ; IdleInWorkingState existant, DWORD 0/1. Aucun ajout de valeur sur pilote incompatible. |
| Optimisations > Jeux et performances | Alimentation avancée | Manage-BASTOS-Extras.ps1 ; états minimal et maximal du processeur du plan actif, secteur/batterie, sans nouveau plan. |
| Personnalisation > Clavier et souris | Profils souris, vitesse, accélération, restauration | MouseProfileService, partagé avec l'ancien bouton d'accélération. Les courbes X/Y sont conservées. |
| Personnalisation | Profils Sobre, Classique, Confort personnalisables et aperçu des choix | Les huit clés déjà définies dans WinScript-Feature-Definitions.ps1 et leur worker Manage-BASTOS-WinScriptFeature.ps1 ; mêmes commandes et mêmes sauvegardes. |

## Fonctionnement

La lecture automatique ou Actualiser ne change pas les réglages Windows. Appliquer et Restaurer sont individuels; les profils visuels ne touchent que les cases choisies. Aucun jeu ou programme n'est fermé automatiquement.

Chrome et Firefox utilisent leur stratégie utilisateur d'accélération graphique. Une stratégie machine contradictoire bloque l'application et est signalée, sans fausse confirmation. Les chemins usuels et App Paths sont utilisés pour détecter les installations. Les installations portables non enregistrées peuvent ne pas être détectées. Une stratégie peut être présentée comme gérée dans le navigateur. La relecture confirme la configuration; le navigateur déjà ouvert doit être relancé pour l'utiliser.

Discord doit être fermé. Seul enableHardwareAcceleration est modifié dans settings.json. Les autres champs, y compris imbriqués et ajoutés ultérieurement, sont conservés. Un JSON invalide n'est pas écrasé. Le profil doit exister; aucun profil vide n'est inventé.

La MTU est mesurée à la demande, vers une destination IPv4 choisie. La route doit utiliser la carte sélectionnée. Une absence de réponse est indéterminée, jamais assimilée à une preuve de fragmentation. Le diagnostic n'applique aucune valeur. L'application exige une mesure récente, le même adaptateur, la même MTU de départ et une route cohérente. Aucun réglage DNS, TCP, voisinage ou DAD n'est modifié. Une mesure vers un serveur ne prouve pas la MTU vers tous les jeux et ne promet pas un gain de ping.

La veille USB est une option de dépannage par propriété WDF du pilote, différente de la suspension sélective globale du plan. Un hub peut partager son réglage avec plusieurs appareils. Aucun périphérique n'est déconnecté; le pilote peut nécessiter une reconnexion ou un redémarrage. L'effet en fonctionnement n'est pas prouvé par la seule relecture du registre.

Les options d'alimentation s'appliquent au GUID du plan sélectionné et conservent les valeurs AC/DC originales. Le minimum doit rester inférieur ou égal au maximum. Si le plan actif a changé depuis la sélection, l'application est refusée. Modifier les pourcentages n'est pas une garantie de fréquence, de latence ou de performances. Les autres réglages de plans restent dans leur interface existante.

La souris utilise SystemParametersInfo pour l'application immédiate et persistante. Le profil Windows règle les seuils 6/10, l'accélération à 1 et la vitesse à 10/20; les courbes personnalisées ne sont pas remplacées. Le profil sans accélération conserve la vitesse actuelle. Les jeux utilisant Raw Input peuvent ignorer ces réglages du pointeur Windows. La restauration conserve les champs modifiés en dehors de Bastos.

## Sauvegardes et intégrité

Manage-BASTOS-Extras.ps1 sauvegarde avant écriture sous ProgramData/BASTOS/Extras/SID. Les sauvegardes atomiques sont vidées sur disque et un mutex sérialise ces opérations. Les nouvelles applications ne remplacent pas les originaux. La restauration vérifie les chemins autorisés pour chaque fonction; les changements externes sont conservés et les échecs gardent la sauvegarde pour réessai. Discord sauvegarde la propriété, pas une ancienne copie complète du fichier à remettre aveuglément.

MouseProfileService partage une seule sauvegarde LocalAppData/BASTOS/MouseProfile.json entre le bouton existant et les nouveaux profils. Les profils visuels réutilisent les sauvegardes déjà gérées par le moteur WinScript de Bastos.

Le catalogue d'intégrité embarqué compte 114 fichiers de moteur, dont le nouveau worker. Les sources courantes et les manifestes d'installation sont mis à jour avec la même version.

## Validation

- Publication autonome WPF .NET 8 x64.
- 43 contrôles en VM : lectures sans modification, stratégies Chrome/Firefox avec originaux présents/absents, réapplication, stratégie machine contradictoire, préservation de JSON Discord, JSON invalide, alimentation réelle AC/DC et bornes, refus des cibles inconnues, recherche MTU indéterminée/fragmentation, cibles USB et deux magasins MTU contrôlés, validation des cibles de restauration.
- Les écritures USB et MTU sont testées avec des adaptateurs contrôlés : elles ne prouvent pas la prise en charge de chaque périphérique réel. L'inventaire natif a aussi été lu sur le PC sans y appliquer ces réglages.
- Test graphique en session interactive de la VM : six vues, profils souris réellement appliqués et restaurés, conservation des modifications externes, application/restauration des profils visuels par le moteur existant.
- Vérification de classification existante : 11 groupes, 18 bascules, 11 choix, 19 cartes et 5 cartes de performances conservés sans perte ni duplication des objets existants.
- 38 contrôles de non-régression des précédentes optimisations.

Les scripts Tests/Extras et le mode --extras-smoke-test sont réservés au laboratoire. Ce mode applique et restaure des réglages dans la VM; ne pas le lancer sur la machine de production.

Les options écartées dans le rapport (cache disque prétendument protégé, blocage de composants du Bureau, MSI et affinités forcés, remplacement d'Explorer, priorité temps réel de csrss) ne font pas partie des ajouts.
