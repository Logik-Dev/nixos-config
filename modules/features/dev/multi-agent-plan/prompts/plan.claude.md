Tu prépares un plan d'implémentation pour le dépôt : {{repo}}

Tâche demandée :
{{task}}

Contexte :
- Commande de test : {{test_cmd}}
- VCS : {{vcs}} — messages de commit en Conventional Commits.

Pack de contexte (inventaire git borné, sans LLM ; complète avec Read/Grep si
nécessaire, en lecture seule) :
{{context_pack}}

Méthode :
- Explore le dépôt en lecture seule : structure, conventions (CLAUDE.md / AGENTS.md), tests, outillage.
- Repère les fichiers concernés et les contraintes existantes.
- Élabore un plan d'implémentation ordonné, concret et testable.

Contraintes :
- Ne modifie AUCUN fichier.
- Réponds uniquement avec le Markdown du plan, sans préambule ni conclusion.
- Le plan contient : contexte, étapes ordonnées (une par changement cohérent), fichiers concernés, extraits de code indicatifs si utile, commande(s) de test, risques et points d'attention.
