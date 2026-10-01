Tu exécutes UNE étape d'un plan d'implémentation. Dépôt : {{repo}}

Contexte : étape {{step_number}}/{{step_total}} — {{step_title}}
Commits déjà réalisés :
{{commits}}

Étape à implémenter, et rien d'autre :
{{step}}

Règles :
- Implémente uniquement cette étape ; ne touche pas aux étapes suivantes.
- Exécute uniquement la commande `Tests` de l'étape, si elle est présente : l'orchestrateur lancera lui-même {{test_cmd}} après la TUI, ne lance pas cette commande globale.
- Puis crée UN SEUL commit atomique avec exactement ce message : {{commit_message}}
- VCS : {{vcs}}.
- Ne push jamais, ne fabrique pas de commit de fixup, ne réécris jamais un commit antérieur à cette étape.
- Toute correction après coup reste dans le commit de l'étape (`jj squash` avec jj, `git commit --amend` avec git).
- Si l'étape est bloquée ou ambiguë, explique-le et attends ma réponse.
