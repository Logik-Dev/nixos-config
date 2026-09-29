# `/config` de l'ancienne VM HAOS — archive de lecture

Copie des fichiers YAML de la VM Home Assistant OS, récupérée le 2026-09-29 juste
avant son arrêt. **Rien ici n'est actif** : c'est une trace lisible, conservée le
temps que la migration soit close (le qcow2 l'est aussi, cf. lot D du dossier).

Ce qui a été repris, et où :

| Origine | Devenu |
|---|---|
| 3 automatisations `rankoder_*` + capteurs MQTT de `configuration.yaml` | `modules/features/medias/rankoder.nix` |
| 3 automatisations d'arrosage + `binary_sensor.il_va_pleuvoir` | `modules/features/home/home-assistant-arrosage.nix` |

Tout le reste a été **écarté sciemment** : musique (5 automatisations, 11 scripts),
médias (2 automatisations + `script.notifier`), mouvement chambre des enfants,
`script.dejeuner`, capteurs Mealie, `input_boolean.poubelles_sorties`.

Les défauts trouvés dans ces fichiers sont documentés en §11 de
[`../home-assistant-nix-plan.md`](../home-assistant-nix-plan.md) — ils expliquent
pourquoi la reprise n'a pas été une simple traduction.
