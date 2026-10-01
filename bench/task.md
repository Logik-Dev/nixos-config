# Tâche de référence — mesure tokens/coût de `multi-agent-plan`

Tâche **figée** utilisée par le protocole de mesure (`docs/multi-agent-plan.md`).
Les runs baseline s'arrêtent à `final` : ne pas l'implémenter.

## Demande

Ajouter une sous-commande `stats` en lecture seule à la commande
`musique-import` (`modules/features/medias/musique-import.nix`) :

- afficher le nombre d'albums en file d'attente, le total de pistes audio et
  l'espace disque occupé, triés par nom d'album ;
- afficher ensuite les 5 derniers imports du journal beets (`beet.log`) ;
- mettre à jour `usage()` et la documentation d'usage.

## Contraintes

- Aucune écriture : ne touche ni la file d'attente, ni la base beets.
- Réutiliser les helpers existants (`audio`, `du`) ; aucune nouvelle dépendance.
- Aucun accès réseau, aucun redémarrage de service.
- `nix flake check` doit rester vert.
