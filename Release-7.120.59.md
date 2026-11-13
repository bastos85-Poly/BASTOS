
## 19 octobre 2026 — mode conforme Rufus pour réinstallation interne (7.120.59)

Le menu de réinstallation sans clé USB propose par défaut « Mode conforme à Rufus 4.15 ». Les choix confidentialité et QoL reprennent les réglages confirmés dans le binaire Rufus 4.15.2396 et sa source GPL : ProtectYourPC=3 pour les questions de confidentialité ; les six commandes specialize et quinze réglages de première session pour QoL. Le chemin de démarrage interne, le compte local BASTOS, la sélection de Windows et les contrôles des partitions restent ceux de BASTOS.

En mode conforme, les préférences supplémentaires BASTOS sont conservées mais ignorées dans le profil effectif : aucune désinstallation supplémentaire de Copilot, Microsoft News ou du paquet OneDriveSync, aucun réglage additionnel AllowTelemetry, widgets ou ContentDeliveryManager. QoL retire Outlook et Teams, bloque OneDrive et retire les deux installateurs système comme Rufus, désactive Copilot, les actualités et Fast Startup et reprend les autres valeurs Rufus. Désactiver QoL retire ces actions du prochain profil généré ; cela ne restaure pas les applications d'une installation existante. Le comportement effectif des stratégies reste dépendant de la version de Windows, comme avec Rufus.

RufusExperienceVersion=4.15 distingue le profil conforme des anciens profils, qui conservent leur sémantique. Le contrôle confidentialité vérifie l'archive OOBE produite avec le fichier réponses et l'annonce comme configuration, sans prétendre mesurer les données envoyées par Windows. Le bilan QoL relit les valeurs et inventaires du nouveau Windows. Les options supplémentaires redeviennent accessibles si le mode conforme est décoché.

Validation : 84 contrôles de parité et de combinaisons QoL/confidentialité sous PowerShell 5.1 ; 97 contrôles du moteur d'options ; 51 contrôles du bilan ; compilation WPF x64 autonome ; test de bascule du mode et inspection visuelle. Aucune réinstallation réelle, aucun formatage et aucun redémarrage d'essai. Les fichiers d'installation déjà préparés sur D: doivent être régénérés avec cette version avant la prochaine réinstallation.

Référence : ThirdParty/Rufus/wue-qol-v4.15.c dans Source-Current.zip et analyse statique locale Tools/Rufus-analysis/Scan-REA-Rufus.md. Licence GPL-3.0-or-later conservée.
