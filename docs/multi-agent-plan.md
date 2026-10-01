# multi-agent-plan — protocole de mesure tokens/coût

L'outil `multi-agent-plan` (`modules/features/dev/multi-agent-plan/`) enchaîne
`plan → reviews → final → execute`. Ses optimisations n'ont de sens que
mesurées : ce document fige la **tâche de référence**, la **méthode** et les
**numéros baseline**, pour que chaque baisse annoncée soit vérifiable.

## Tâche de référence

`bench/task.md` : petite fonctionnalité en lecture seule sur `musique-import`,
**figée** et jamais exécutée (tous les runs de mesure s'arrêtent à `final`).

## Protocole

Pour chaque configuration à comparer, un seul run :

```
multi-agent-plan --repo ~/Homelab/Nixos --task-file bench/task.md --stop-after final
```

1. `--task-file bench/task.md`, jamais `--task` en ligne : la tâche doit être
   identique d'un run à l'autre.
2. `--stop-after final` couvre `plan → reviews → final`, jamais `execute` (TUI
   interactif, hors mesure).
3. Lire `.agent-plans/<horodatage>/meta.json` (`phases` + `summary`) et ajouter
   une sous-section « Résultats » ci-dessous, sur le même modèle que la baseline.

Notes :

- Un run par configuration est un **ordre de grandeur**, pas une moyenne :
  affinité de cache Anthropic, charge serveur et variabilité OpenCode font
  varier le coût ; un écart doit rester dans le même sens à la relance.
- Ne comparer que des runs de la même tâche, de la même machine (m4) et du même
  outillage.
- Les tokens `cache_read`/`cache_write` sont comptés séparément (l'input frais
  coûte bien plus cher) ; `total_tokens` du résumé les additionne.
- Le coût OpenCode vient de la base locale (`opencode.db`, `session_metrics`),
  le coût Claude de la sortie JSON de `claude -p`.
- `.agent-plans/` est ignoré par git : ce document est la seule trace versionnée
  des `meta.json`.

## Résultats

### Baseline — 0.2.0 (dépôt a819c847, étapes 1–2 : parsing + métriques)

- Date : 2026-10-01, sur m4 ; planification encore Claude (plan + review) et
  OpenCode (review + synth).
- Run : `.agent-plans/20261001-144734/` (dossier gitignoré, conservé sur disque).
- Lancé depuis le script du dépôt (le binaire installé datait d'avant
  l'étape 2) :

  ```
  python3 modules/features/dev/multi-agent-plan/orchestrator.py \
    --repo ~/Homelab/Nixos --task-file bench/task.md --stop-after final
  ```

| Phase | Agent | Durée (s) | Coût ($) | Tokens |
| --- | --- | ---: | ---: | ---: |
| plan | Claude Opus | 446.3 | 2.7013 | 215 629 |
| review-opencode | DeepSeek V4.1 Flash | 108.1 | 0.0127 | 140 876 |
| review-claude | Claude Opus | 185.1 | 0.7247 | 225 156 |
| synth | DeepSeek V4.1 Flash | 88.8 | 0.0143 | 274 878 |
| **Total** | | **828.3** | **3.4530** | **856 539** |

Lectures :

- Claude = 3.4260 $, soit **99,2 %** du coût ; OpenCode 0.0270 $ (0,8 %).
- Le plan seul pèse 78,2 % du coût total : c'est le premier levier (étape 5,
  plan OpenCode par défaut), avant l'effort de review Claude (étape 10).
- Reviews parallèles (185 s ≈ phase 2), synthèse 89 s.
- Run sain : 2 étapes atomiques détectées, aucun échec de phase.
