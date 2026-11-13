# BASTOS 7.120.133 — installation Glary Utilities

WinGet référence 6.49.0.53 mais l'URL permanente de Glarysoft fournit désormais un autre fichier. Le contrôle d'empreinte WinGet refuse correctement le téléchargement.

Uniquement pour Glarysoft.GlaryUtilities, avec le gestionnaire et la source winget et le code exact d'empreinte divergente, Bastos utilise la source officielle HTTPS sans redirection. Il exige une signature Authenticode valide dont l'éditeur est Glarysoft Ltd, interdit la modification du fichier entre validation et lancement, exécute le commutateur silencieux /S référencé par le manifeste WinGet et vérifie ensuite la présence du paquet. Il ne désactive ni ne contourne le contrôle SHA256 de WinGet. Les autres logiciels, sources et erreurs conservent leur parcours.

19 contrôles Glary, dont vérification du téléchargement officiel réel et refus des signatures divergentes avant lancement simulé ; 40 tests existants des installations groupées et de l'élévation ; compilation x64 autonome. Les tests simulés n'installent pas de logiciel. Le résultat de l'installation réelle figure séparément dans Verification. Validation complète VM et garde général non passés.
