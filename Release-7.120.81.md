# BASTOS 7.120.81 — Nettoyeur système

« Assistance distante » est remplacée dans la navigation par « Nettoyeur ». L'analyse du Nettoyeur est en lecture seule et présente les fichiers proposés, leur taille et leur catégorie. L'utilisateur peut filtrer, trier, décocher, exclure un chemin ou conserver les sélections recommandées. La suppression définitive exige une confirmation et est enregistrée dans le Journal.

Le catalogue indépendant s'appuie sur l'observation statique de Kudu 3.10.0 : fichiers temporaires, caches système et d'applications, navigateurs, jeux et outils de développement. Les caches de shaders et Prefetch, ainsi que les catégories de diagnostic, restent désélectionnés par défaut. Les fichiers de moins d'une heure, modifiés, utilisés, exclus ou situés derrière un lien sont conservés. Un nouveau scan est nécessaire après nettoyage.

La maintenance des composants Windows, du cache Delivery Optimization et de la corbeille est isolée du nettoyage des fichiers. Chaque action exige une analyse puis une confirmation. Les deux premières requièrent des droits administrateur. La taille récupérable est inconnue sauf pour la mesure instantanée de la corbeille. Ces opérations n'appliquent pas les exclusions et sont donc bloquées quand une exclusion existe.

Cette réalisation ne reproduit pas les fonctions de Kudu sur les raccourcis, les variables d'environnement, les bases SQLite et les traces de confidentialité. Ces catégories méritent des parcours propres et une validation distincte ; elles ne sont pas annoncées comme nettoyées par BASTOS.

Validation locale : compilation Release, 29 contrôles du moteur sur fixtures, 28 contrôles WPF/Journal sur fixtures. Aucune catégorie du PC n'a été nettoyée pendant la validation. La validation complète du laboratoire VM, requise par le processus de release, n'a pas été effectuée ; les limites antérieures du kit demeurent.
