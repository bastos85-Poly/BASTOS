# BASTOS 7.120.88 — correction du parcours graphique allégé

Le contrôle de la carte AMD dans « Mise à jour matériel → version allégée » reconnaît maintenant l'identifiant matériel PCI\VEN_1002. Le bouton attend la fermeture du parcours PowerShell et affiche dans Bastos le résultat ou l'erreur enregistrée, au lieu de seulement indiquer que la fenêtre s'est ouverte.

Validation : syntaxe PowerShell, reconnaissance en lecture seule de la Radeon RX 9070 XT présente, absence correcte de NVIDIA, compte rendu JSON, compilation, tests de démarrage et intégrité, extraction et reconstitution du paquet. Aucun pilote n'a été installé lors de ces tests.
