# Contribuer à Bastos

Conserver l'organisation de navigation sauf décision explicite. Pour l'interface, privilégier les ressources partagées dans App.xaml et contrôler le rendu WPF, les descriptions dépliables, le clavier et le défilement. Ne pas modifier les actions système à l'occasion d'un changement de style.

Chaque modification doit expliquer le problème, le résultat, les tests exécutés et leurs limites. Reproduire les bugs dans des fixtures ou une VM. Conserver les sauvegardes, les contrôles d'intégrité et la restauration des états précédents.

Avant une publication de binaires, suivre Build/README-ReleaseValidation.md et régénérer les manifestes associés. Ne jamais présenter un test simulé comme une validation réelle sur un PC ou dans un jeu.
