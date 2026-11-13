# Sécurité et confidentialité

Cette application peut demander des droits administrateur et modifier Windows. La revue de confidentialité ne garantit ni absence de vulnérabilité, ni validation complète de chaque fonction. Aucun installateur public n'est fourni dans cette copie de sources.

Ne publier que cette copie dédiée après revue, jamais le dossier de travail Codex, les dossiers AppData/ProgramData du PC, les anciennes versions, médias Windows, journaux, sauvegardes, captures ou exports privés. Un fichier ignoré par .gitignore reste visible s'il était déjà suivi : créer un dépôt neuf à partir de cette copie évite de reprendre un historique non contrôlé.

Les exemples de noms, SID, mots de passe factices et URL example.org dans les tests servent à vérifier la suppression de données sensibles. Ce ne sont pas des secrets de production. Le lien Ko-fi bastos85 est volontairement public ; aucune clé Ko-fi ni donnée bancaire n'est nécessaire pour ouvrir cette page.

Avant une publication, activer et conserver les protections GitHub de détection de secrets, examiner les fichiers ajoutés et contrôler aussi les pièces jointes des Releases. Ne pas publier de journaux bruts dans les issues. En cas de doute sur un fichier, le garder privé jusqu'à examen.

Les binaires actuels du kit personnel contiennent des chemins locaux de compilation et ne doivent pas être joints tels quels à une Release. Le programme principal et le module de jeu ont été reconstruits localement avec remappage des chemins. Les manifestes, le kit complet et le candidat inchangé doivent passer la validation en laboratoire avant chaque livraison installable. Ne pas modifier des octets d'un exécutable pour masquer une chaîne.
