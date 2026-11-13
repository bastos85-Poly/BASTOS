# 7.120.62 — installation propre personnalisée BASTOS, facultative

Une case « Installation propre personnalisée BASTOS » est ajoutée dans Compte, clavier et partitions > Nettoyage et confidentialité. Elle est décochée par défaut et exclut le mode conforme Rufus. Lorsqu'elle est choisie, elle active le nettoyage, les options OneDrive/Teams/Outlook/Copilot/widgets et la confidentialité renforcée. Un volet affiche les familles d'applications retirées et les composants conservés. La conservation des pilotes reste un choix indépendant. Aucun nettoyage du Windows actuellement installé n'est exécuté par l'ouverture ou l'enregistrement de cette fenêtre.

## Image préparée avant installation

Pour la réinstallation interne, la copie install.wim est montée dans le staging. Les paquets provisionnés présents dans Get-BastosMinimalAppNames sont retirés par les API DISM prises en charge, puis l'inventaire est relu avant la sauvegarde du montage. La liste est explicite et sans joker global Microsoft : News, Météo, Outlook, Teams, Copilot, Cortana, applications Office facultatives, contacts/courrier, Skype, Téléphone, Conseils/Aide/Commentaires, Solitaire, Clipchamp, To Do, Power Automate, Cartes, Dev Home, Family, applications 3D, multimédia, Photos/Paint/Caméra/Enregistreur, application Xbox et Game Bar, et certaines applications partenaires reconnues. Les identités exactes font partie des sources et des tests ; les applications absentes sont ignorées. OneDrive est traité par les commandes specialize et la désinstallation dédiée à la première session.

Le Store, App Installer, la sécurité Windows, le shell, les frameworks, codecs, Gaming Services, identité Xbox/TCUI, Bloc-notes, Calculatrice et capture d'écran ne sont pas ciblés. Edge/WebView2 sont conservés. Il n'y a pas de retrait manuel de WinSxS, de ResetBase forcé, de désactivation générale des services ni de blocage global des connexions Microsoft. Les paquets inconnus ou futurs ne sont pas supprimés arbitrairement.

La source ISO reste intacte. Ce parcours prépare le média interne D:, pas un nouveau fichier ISO exporté. Le rapport BASTOS-Minimal-Offline.json accompagne le média préparé. Le vérificateur C# exige ce rapport et l'empreinte de l'image lorsque le profil minimal est demandé. Une erreur de suppression entraîne l'abandon du montage ; un dossier encore monté est conservé plutôt que supprimé récursivement. La métadonnée originale de l'édition WIM est restaurée après commit, comme dans le chemin existant.

## Trois épingles et première session

Le raccourci BASTOS est créé dans le menu Démarrer commun et sur le Bureau, avec sa cible relue. Avant le nettoyage de première session, le raccourci est donc disponible. StartPins.json configure exactement Paramètres, Explorateur et BASTOS via ConfigureStartPins/ConfigureStartPinsJSON, avec applyOnce. Les recommandations sont masquées par les politiques prévues à cet effet. Le profil exige une édition Pro/Entreprise/Éducation récente ; la définition ConfigureStartPinsJSON est vérifiée dans l'image avant retrait. La définition a également été retrouvée par lecture seule dans l'édition 6 du WIM actuellement préparé sur D:.

La disposition est enregistrée dans la stratégie locale avec l'API Windows IGroupPolicyObject, puis l'actualisation des stratégies est demandée : ce n'est pas seulement une préférence écrite dans le registre. Les autres paramètres de la stratégie locale sont conservés. Le bilan relit aussi cet enregistrement en mode lecture seule. Une déconnexion/reconnexion peut être nécessaire pour que Démarrer relise sa disposition. Aucune base start.bin/start2.bin ni base de registre interne de PolicyManager n'est copiée depuis un autre PC.

## Confidentialité renforcée

Le profil conserve les paramètres de confidentialité existants et ajoute l'arrêt de l'identifiant publicitaire par politique, la limitation des journaux/vidages de diagnostic, l'arrêt de publication/transfert de l'activité, la désactivation de l'analyse Recall par politique, de Spotlight et des suggestions Web. DiagTrack est arrêté et désactivé. Seules cinq tâches CEIP/Siuf nommées sont ciblées, lorsqu'elles existent ; leur état est relu ainsi que celui du service. Les tâches Defender et Windows Update ne sont pas ciblées. Les accès au micro/caméra ne sont pas bloqués globalement.

AllowTelemetry reste à 1 sur Pro/Famille et à 0 sur les éditions qui prennent en charge ce niveau. La présence des politiques et l'état des tâches/services sont contrôlés, pas l'absence absolue de trafic ou de collecte. Aucun résultat « zéro télémétrie » n'est annoncé.

## Cache et utilisation

CleanupProfile=minimal-1 fait partie de la décision de réutilisation du cache. Cocher ou décocher le profil exige une reconstruction depuis la source officielle si le média préparé ne correspond pas ; cela évite de réutiliser une image débarrassée d'applications pour un choix normal. BootOnce refuse un changement de profil non préparé avant d'armer le redémarrage. Les anciens profils sans ce champ restent des profils normaux. La version du profil est enregistrée dans Installation-Expected.json pour lier le bilan à la demande.

Utilisation : relancer BASTOS, ouvrir Compte, clavier et partitions, cocher la nouvelle case, enregistrer puis préparer de nouveau Recovery. Aucun montage ou effacement réel n'a été déclenché pendant la livraison.

## Validation et limites

59 contrôles PowerShell du profil propre avec DISM/services/tâches et API de stratégie simulés ; compilation réelle de l'interop Windows sans activation COM ; 51 contrôles C# du bilan/cache/vérificateur indépendant ; 53 contrôles du bilan après installation ; 35 contrôles du cache ; 27 contrôles des pilotes ; 84 contrôles de parité Rufus ; 97 contrôles des options. Aperçu WPF et bascule des deux profils vérifiés, compilation x64. L'extraction de la définition ADMX depuis le WIM a été faite en lecture seule. Aucun retrait Appx, modification de service, de stratégie ou de registre, montage DISM ni réinstallation réel sur l'hôte.

Le fonctionnement réel des API DISM sur toutes les éditions, l'installation complète, le rendu Démarrer et les jeux restent à valider dans une machine d'essai. L'analyse antérieure de NTLite a servi à distinguer composants, compatibilité et préférences ; son moteur propriétaire n'a pas été reproduit ni présenté comme entièrement décompilé.

Références Microsoft :
- https://learn.microsoft.com/en-us/windows/configuration/customize-start-menu-layout-windows-11
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start
- https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage
- https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization
