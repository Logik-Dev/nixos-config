La session interactive de planification vient de se terminer pour le dépôt : {{repo}}

À partir de l'historique de cette session, restitue le résultat validé, sans rien
modifier et sans relancer de discussion.

Format imposé, exactement dans cet ordre :
<<<BRIEF>>>
Brief concis de la tâche validée (objectif, périmètre, contraintes clés).
<<<END_BRIEF>>>
<<<FINAL_PLAN>>>
Plan d'implémentation complet en Markdown : contexte, étapes ordonnées (une par
changement cohérent), fichiers concernés, extraits de code indicatifs si utile,
commande(s) de test, risques et points d'attention.
<<<END_FINAL_PLAN>>>

Contraintes :
- Ne modifie aucun fichier.
- Réponds uniquement avec ces deux blocs, sans préambule ni conclusion.
- Utilise exactement ces fermetures, une par bloc : <<<END_BRIEF>>> et
  <<<END_FINAL_PLAN>>>. N'écris jamais <<<END>>> ni ces marqueurs dans le contenu.
