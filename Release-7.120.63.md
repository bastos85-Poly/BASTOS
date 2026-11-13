# 7.120.63 — conservation des outils de connexion et d’assistance

Le profil Installation propre personnalisée BASTOS conserve Mobile connecté (Microsoft.YourPhone) et Assistance rapide (MicrosoftCorporationII.QuickAssist), lorsqu’ils existent dans la source Windows. Mobile connecté est retiré de la liste de suppression partagée avant et après installation ; Assistance rapide était déjà conservée. Des tests protègent les deux applications.

Les trois épingles restent Paramètres, Explorateur et BASTOS. Les deux outils restent accessibles dans la liste des applications.

Le cache du profil passe à minimal-2 : une image minimal-1 doit être reconstruite depuis l’ISO d’origine, afin de ne pas réutiliser une image dont Mobile connecté avait été retiré. Le schéma des options reste compatible. Aucun changement au Windows actuellement installé, aucune réinstallation déclenchée.

Validation : 63 contrôles du profil, 36 contrôles de cache et 51 contrôles C# de préparation et vérification ; publication x64. Les opérations DISM et changements de services sont simulés dans les tests.
