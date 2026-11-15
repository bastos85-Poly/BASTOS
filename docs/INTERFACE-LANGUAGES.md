# Langues de l’interface

Le sélecteur Français / English change la présentation en direct. Le choix est enregistré dans `%LOCALAPPDATA%\BASTOS\InterfaceLanguage.txt`. Le français est utilisé par défaut, ainsi qu’en cas de préférence inconnue ou illisible.

Le catalogue anglais embarqué `Assets/Interface.en.json` couvre les pages principales, fenêtres secondaires, descriptions et confirmations de BASTOS. Les modèles `{0}`, `{1}`, etc. conservent les valeurs variables. Les noms de logiciels, chemins, saisies de l’utilisateur et diagnostics bruts restent intacts. Les interfaces d’outils externes et les boutons natifs Windows suivent leurs propres règles de langue.

La traduction porte sur les textes rendus. Elle ne change ni la culture du système, ni la langue du Windows à installer, ni les PageKey, commandes, paramètres ou valeurs de sélection. Les messages inconnus restent dans leur langue d’origine plutôt que d’être traduits approximativement.

Le test `--language-smoke-test` nécessite `BASTOS_LANGUAGE_TEST_DATA` pointant vers un dossier privé dédié. Il vérifie les changements en direct, la sauvegarde, les valeurs sources et champs protégés, puis rend douze pages et neuf fenêtres secondaires avec des données de test pour les bilans. `--expect-english` vérifie le chargement d’une préférence anglaise préalablement enregistrée dans ce dossier. Les captures et rapports de tests restent privés.

Cette évolution d’interface est testée localement. Elle ne constitue pas une nouvelle livraison validée pour la réinstallation de Windows.

L’audit `--language-smoke-test --language-audit-hardware --smoke-test` ajoute une vraie analyse matérielle et une lecture des états réseau, sans installation de pilote ni modification réseau. `BASTOS_TEST_DATA` doit alors viser un dossier de test dans TEMP. Les sections dépliables sont ouvertes pendant la revue. Des cas de régression vérifient les progressions, résultats, noms de sources officielles, compteurs et le retour au texte français, tout en conservant les chemins et valeurs variables.

Bastos Game lit la même préférence, transmise par --language-file. Le module actualise son menu de notification, son infobulle et ses réglages pendant le fonctionnement. Son catalogue spécifique est Bastos.Game.Source/Interface.en.json ; build.ps1 le fusionne avec le catalogue principal pour embarquer les textes, sans requête de traduction réseau. --language-self-test exige un fichier de préférence de test distinct et vérifie le menu, le changement en direct et la conservation de la sélection. Les politiques du moteur et les résultats enregistrés ne sont pas traduits ni modifiés.
