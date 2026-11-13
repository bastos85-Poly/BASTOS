# BASTOS 7.120.132 — détection des réglages d'apparence

Le mode sombre était annoncé non appliqué à cause d'un contrôle du fichier de thème incompatible avec ses fins de ligne Windows. La détection utilise désormais les préférences actuelles des applications et de Windows, sans dépendre d'un ancien fichier de thème.

Chacun des huit réglages d'apparence est lu séparément avec vérification du type de valeur. Le bilan distingue Appliqué, Partiellement appliqué, Non appliqué et Non vérifié. Une valeur absente ou inaccessible ne signifie plus désactivé et une ancienne réussite n'est pas conservée après une lecture incomplète. Un détail est disponible au survol. Le menu classique reste une configuration vérifiée, sans prétendre prouver le rendu visuel.

Les boutons d'application/restauration, les sauvegardes et les autres fonctions sont conservés. Le nouveau contrôle d'apparence ne lance pas les diagnostics de fonctionnalités sans rapport avec ces huit lignes.

Validation : 59 contrôles de détection PowerShell 5.1, 11 contrôles WPF en lecture seule avec rendu inspecté, lecture réelle des huit réglages et 59 contrôles du bilan après réinstallation dont le rapport utilisateur. Compilation WPF x64 autonome. Aucune optimisation ni application de profil sur le PC. Les contrôles de livraison complète et de réinstallation VM restent non validés ; aucun rapport général Passed=true n'est revendiqué.
