Tu exécutes UNE étape d'un plan d'implémentation. Dépôt : {{repo}}

Contexte : étape {{step_number}}/{{step_total}} — {{step_title}}
Commits déjà réalisés :
{{commits}}

Étape à implémenter, et rien d'autre :
{{step}}

Règles :
- Implémente uniquement cette étape ; ne touche pas aux étapes suivantes.
- Commande de test : {{test_cmd}}
- Exécute les tests et corrige jusqu'à ce qu'ils passent AVANT de committer.
- Puis crée UN SEUL commit atomique avec exactement ce message : {{commit_message}}
- VCS : {{vcs}}.
- Ne push jamais, ne fabrique pas de commit supplémentaire, ne modifie pas un commit antérieur.
- Si l'étape est bloquée ou ambiguë, explique-le et attends ma réponse.
