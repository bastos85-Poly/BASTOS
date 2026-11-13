# BASTOS 7.120.87 — pilote graphique allégé

La page « Mise à jour matériel » contient un second parcours « Installer / mettre à jour le pilote graphique — version allégée ». Il propose NVIDIA, AMD et Intel. L'utilisateur télécharge le pilote depuis le site officiel et choisit son exécutable signé ; Bastos vérifie le constructeur et la signature, extrait une copie temporaire, retire ou désactive des éléments facultatifs, puis lance l'installateur. Le parcours normal reste disponible.

NVIDIA : retrait de NView, FrameView, télémétrie, audio virtuel et ShadowPlay dans la copie, en conservant le pilote d'affichage, l'audio HDMI, PhysX et le panneau de configuration. AMD : désactivation de modules facultatifs (analyse, mise à jour, Link, relanceur) dans les XML de la copie. Intel : installation avec l'option `--noExtras`. Les suppressions de services, de pilotes audio et de fichiers système présentes dans le script d'origine ne sont pas reproduites. L'import des paramètres graphiques demeure dans « Optimisation carte graphique ».

Source adaptée : https://github.com/FR33THYFR33THY/Ultimate/blob/a0a33a57078434201f582b0db5107dcbb502292a/5%20Graphics/4%20Driver%20Debloat%20Install%20%26%20Settings.ps1, licence MIT dans ThirdParty/Ultimate-LICENSE.txt.

Validation : analyse syntaxique PowerShell, plan des trois constructeurs, compilation WPF, tests de démarrage et intégrité, extraction/reconstitution du paquet. Installation réelle de pilotes et validation complète VM non effectuées.
