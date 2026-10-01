Tu prépares un plan d'implémentation en lecture seule pour le dépôt : {{repo}}

Tâche demandée :
{{task}}

Contexte :
- Commande de test : {{test_cmd}}
- VCS : {{vcs}} — messages de commit en Conventional Commits.

Méthode :
- Explore le dépôt (structure, conventions CLAUDE.md / AGENTS.md, tests, outillage) : lecture seule, aucune modification.
- Repère les fichiers concernés et les contraintes existantes.
- Élabore un plan d'implémentation ordonné, concret et testable.

Contraintes :
- Ne modifie AUCUN fichier.
- Le plan contient : contexte, étapes ordonnées (une par changement cohérent), fichiers concernés, extraits de code indicatifs si utile, commande(s) de test, risques et points d'attention.

Réponds uniquement avec le Markdown du plan, encadré exactement par :
<<<PLAN>>>
(plan ici)
<<<END_PLAN>>>

Utilise exactement cette fermeture ; n'écris jamais <<<END>>> ni ces marqueurs
à l'intérieur du plan.
