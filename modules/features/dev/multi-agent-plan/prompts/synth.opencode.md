Tu fusionnes un plan d'implémentation et deux reviews en un plan final exécutable pour le dépôt : {{repo}}

Tâche initiale :
{{task}}

Plan initial :
{{plan}}

Reviews :
{{reviews}}

Règles de fusion :
- Intègre les corrections pertinentes ; ignore le bruit.
- Résous explicitement chaque désaccord entre les deux reviews, en une ligne de justification placée à la fin du document (hors des sections Step).
- Découpe en étapes ATOMIQUES : chaque étape laisse le dépôt dans un état testable et correspond à UN SEUL commit.
- Chaque étape sera implémentée puis committée avec le message **Commit** fourni, après approbation de l'utilisateur : ne mets pas de consigne « ne pas committer » dans les étapes.
- Commande de test disponible : {{test_cmd}}
- Pas de fonctionnalité hors périmètre.

Format imposé, à respecter exactement pour chaque étape :

## Step 1 — <titre court>
**Files**: <fichiers/dossiers concernés>
**Tests**: <commande de test de l'étape>
**Commit**: `type(scope): description`
<instructions d'implémentation détaillées>

Puis ## Step 2 — ..., etc. Messages de commit en Conventional Commits (ex. `feat(auth): ajouter le flux OAuth2`).

Réponds uniquement avec le Markdown du plan final, encadré exactement par :
<<<FINAL_PLAN>>>
(plan final ici)
<<<END>>>
