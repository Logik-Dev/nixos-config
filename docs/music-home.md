# Musique maison — Spotify Famille, Alexa, Sonos, Music Assistant

Documentation de la stack « musique multi-utilisateurs » : problème, architecture
retenue, comportement, limites et procédures. Mise en place le **2026-09-26**.

## Problème

Famille de 5 (2 adultes + 3 enfants), abonnement **Spotify Family** (jusqu'à 6
comptes), enceintes **Sonos**, assistants **Alexa**.

La skill Spotify d'Alexa ne se lie qu'à **un seul compte Spotify** par compte
Amazon. Conséquences : tout le monde écoute le compte du titulaire, les lectures
se marchent dessus, et les recommandations sont mélangées. Les profils Amazon
enfant (< 13 ans) ne peuvent de toute façon **pas** lier Spotify.

Un premier contournement existait : de petits scripts Home Assistant exposés en
routines Alexa. Cette doc décrit la version fiabilisée + multi-comptes.

## Architecture

```
Spotify Family (comptes par personne)
        │  providers OAuth
        ▼
Music Assistant (add-on HAOS, v2.10.x, :8095, API WebSocket /ws)
        │  players Sonos + plugin Spotify Connect
        ▼
Home Assistant (VM libvirt « home-assistant » sur hyper, 192.168.21.181)
   ├── script.musique_personne (routage par area)
   ├── Assist (pipeline FR : STT/TTS cloud)
   ├── alexa_media (HACS) + Nabu Casa (Alexa smart home)
   └── Sonos (intégration native) / cast / dlna
```

- **Music Assistant** est un **add-on HAOS** (pas géré par ce dépôt Nix). UI sur
  `http://192.168.21.181:8095`.
- La **VM Home Assistant** et son adressage sont décrits dans
  `modules/hosts/hyper/libvirt.nix` (Traefik `hass`) et `docs/networking.md`.
- Aucune modification du dépôt Nix n'est nécessaire pour cette stack (tout vit
  dans la VM). Seul le pointeur Traefik `hass` est versionné.

## Comptes et profils

| Personne | Compte Spotify (provider MA) | User MA | Playlist MA (Liked Songs) |
|---|---|---|---|
| Cédric | `spotify--BS4tzzio` (« Spotify Cédric ») | `cedric` | `library://playlist/7` |
| Charlotte | `spotify--3moX93oJ` (« Spotify Charlotte ») | `charlotte` | `library://playlist/58` |
| Lou | `spotify--jq8Ln9Rg` (« Spotify Lou ») | `lou` | `library://playlist/55` |
| — (admin) | — | `logikdev` (admin) | — |

> **Léa n'a pas encore de profil** (à ajouter : compte Spotify Family + provider
> MA + user MA + entrée script + wrapper + exposition Alexa).

Les « Liked Songs » sont propres à chaque compte et **non adressables par un
autre compte** : d'où l'importance de router par provider/utilisateur MA.

## Players disponibles

MA expose les Sonos suivants (les autres pièces n'ont qu'un Echo, non ciblable
par MA) :

| Pièce | Player MA | ID Sonos |
|---|---|---|
| Salon | `media_player.playbar` | `RINCON_000E58B01D1D01400` |
| Cuisine | `media_player.cuisine_2` | `RINCON_000E587F617201400` |
| Chambre des enfants | `media_player.unnamed_room` | `RINCON_000E587FC0B801400` |

Sonos « Chambre principale » : **hors service** (`unavailable`).

## Phase A — routage multi-utilisateurs

### Areas

Les **areas** HA sont la clé du routage : quand un Echo est sollicité, on joue sur
le player MA de **la même area**.

| Area | Devices (Echo et/ou player) |
|---|---|
| Salon | `playbar` (MA), `salon` / `salon_3` (Sonos), `vision`, `stick_salon` |
| Cuisine | `cuisine_2` (MA), `cuisine` / `cuisine_4` (Sonos) |
| Chambre des enfants | `unnamed_room` (MA), `unnamed_room_unnamed_room` (Sonos), `les_supers_coquins`, `chambre_des_enfants` |
| Chambre de Lou | `loupiotte` (Echo) — **pas de player MA** |
| Salle de bains | `echo_salle_de_bain` — **pas de player MA** |
| Notre Chambre | `chambre_principale` (Echo), `notre_chambre*` (Sonos offline) |

### Script

`script.musique_personne` (dans la VM HA, pas dans ce dépôt) :

1. `alexa_media.update_last_called` + lecture de l'attribut `last_called` pour
   identifier l'Echo qui a été sollicité (sauf si `lecteur` est fourni).
2. `area_id(echo)` → recherche du `media_player` de l'intégration
   `music_assistant` présent dans la même area (`integration_entities` ∩
   `area_entities`), en excluant les `unavailable`.
3. Si une cible existe → `music_assistant.play_media` avec `username` = personne
   (donc **le bon compte Spotify**) et la playlist du profil.
4. Sinon → **annonce TTS** sur l'Echo : « Désolé, il n'y a pas d'enceinte dans
   cette pièce. »

Wrappers `script.musique_cedric` / `musique_charlotte` / `musique_lou` → exposés à
**Alexa** via Nabu Casa. Les routines Alexa existantes continuent de les appeler.

## Phase B — Spotify Connect via Music Assistant

Plugin **Spotify Connect** de MA (moteur **Soloist**, officiel) :

- Cibles publiées = les 3 Sonos (Salon, Cuisine, Chambre des enfants), noms
  « player only ».
- Chaque membre, depuis **son** app Spotify (son compte) → sélecteur d'appareil →
  choisit la pièce. Le son sort dessus depuis son propre compte.
- Nécessite une **clé API Soloist** (créée sur
  `https://developer.spotify.com/dashboard/soloist` avec un compte Premium ;
  stockée chiffrée par MA).

> ⚠️ **Réseau** : Spotify Connect se découvre en **mDNS (5353)**, qui ne traverse
> pas les VLAN. Les mobiles doivent être sur le **même VLAN que MA** (`vlan21` /
> `br-iot`), ou prévoir un **reflector mDNS (Avahi)**. Sinon les cibles
> n'apparaissent pas.

## Phase C — Assist (voix) en français

Pipeline Assist **« Assist FR »** créé et défini **par défaut** :

- STT/TTS = **Home Assistant Cloud** en **`fr-FR`** (le cloud n'accepte pas le
  code `fr` nu).
- Agent de conversation = `conversation.home_assistant` (intent local, **pas de
  LLM** — suffisant pour l'intent média « Search and Play » + MA).
- Players MA exposés à Assist.

**Important — exposition à Assist** : n'exposer à l'assistant `conversation` que
les players **Music Assistant** (`playbar`, `cuisine_2`, `unnamed_room`). Si
plusieurs `media_player` (Sonos natifs, cast, jellyfin…) sont exposés dans la même
area, le ciblage par pièce échoue (`no_valid_targets`, ambiguïté). Les autres
players restent visibles d'Alexa/HA mais sont retirés d'Assist.

Formulations qui marchent (testées) :

- par **pièce** : « joue Stromae dans la cuisine », « mets l'album Random Access
  Memories dans le salon », « mets liked songs lou maunier dans la chambre des
  enfants » ;
- par **player** : « … sur le playbar ».
- Les requêtes vagues (« joue de la musique ») échouent (`no_valid_targets`) : il
  faut nommer un titre/album/playlist **existant** dans la bibliothèque.
- Certains artistes à forte discographie peuvent échouer (`failed_to_handle`) :
  cibler un album/titre plutôt que l'artiste.

Front-end possible : **app HA / Assist iOS** (« Assist in app » + raccourci Siri
ou Voice Control), et à terme un **HA Voice PE**.

## Limites connues

- **MA ne peut pas jouer sur les Echo** nativement (Amazon ne l'autorise pas) :
  il faudrait le **player provider Alexa** de MA, un skill custom expérimental
  (Docker + SSL public + compte dev Amazon). Donc les pièces sans Sonos (Lou,
  salle de bains, Notre Chambre) n'ont **pas** de lecture, seulement l'annonce.
- Pas de profil **Léa** (4e compte Spotify Family à créer).
- « Notre Chambre » : Sonos hors service.
- Le routage dépend de `alexa_media.update_last_called` (latence ~1 s).

## Procédures d'exploitation

### Ajouter une personne

1. Créer un **compte Spotify Family** (email distinct, **pas** un compte Spotify
   Kids qui partage les identifiants du titulaire).
2. MA → *Réglages → Providers* → ajouter un provider **Spotify**, se connecter
   avec le nouveau compte (créer un user MA du même nom).
3. Mettre à jour les `profils` de `script.musique_personne` (playlist + user).
4. Ajouter un wrapper `script.musique_<personne>` (alias + appel du script).
5. Exposer le wrapper à Alexa (Nabu Casa) et créer la routine.

### Ajouter une playlist nommée (voix déterministe)

La recherche média intégrée fait du **matching flou** : « joue la playlist Léa »
peut tomber sur une playlist Spotify publique (ex. « charlotte aux fraises »). Pour
un nom personnel, on **mappe la phrase exacte** vers l'URI de la playlist :

- `script.musique_playlist` — mapping `playlists` (clé → `{uri, utilisateur}`),
  résolution de la pièce par **nom** (slot) et repli sur `media_player.playbar` ;
- des **automatisations** à déclencheur `conversation` (phrases
  « joue/mets [la] playlist <Nom> [dans <pièce>] », « joue/mets <Nom> ») ;
- des **wrappers** `script.musique_playlist_<clé>` exposés à **Alexa** (routines).

Table actuelle :

| Clé / phrase | Playlist (URI) | Compte (`username`) |
|---|---|---|
| `lea` / Léa | `library://playlist/62` | charlotte |
| `lou` / Lou | `library://playlist/57` (« M'y Lou ») | cedric |
| `charlotte` / Charlotte | `library://playlist/58` | charlotte |
| `cedric` / Cédric | `library://playlist/7` | cedric |
| `miraculous` / Miraculous | `library://playlist/59` | lou |

Pour en ajouter une : entrée dans `playlists` du script, automation
`conversation` sur le même modèle, wrapper + exposition Alexa.

### Ajouter une pièce

1. Affecter l'**area** à l'Echo et au player MA correspondants.
2. Vérifier que le player MA est **exposé à HA** et disponible.
3. (Option) Publier le player dans le plugin Spotify Connect.

### Dépannage — « il joue n'importe quoi » (recherche Spotify HS)

Symptôme : « joue Stromae … » lance une **radio TuneIn** (« Xtrema ») au lieu de
l'artiste. Cause : la **recherche catalogue du provider Spotify de MA est
bloquée** ; elle ne renvoie que la bibliothèque, l'intent média tombe alors sur le
premier résultat radio.

Vérifier (token HA) :

```bash
curl -s -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
  -X POST -d '{"config_entry_id":"<MA_entry_id>","name":"stromae"}' \
  "http://192.168.21.181:8123/api/services/music_assistant/search?return_response" \
  | jq '.service_response | {artists:(.artists|length),albums:(.albums|length),tracks:(.tracks|length),radio:(.radio|length)}'
```

Si `artists/albums/tracks = 0` mais `radio > 0` → provider bloqué.

Corriger : **recharger le(s) provider(s) Spotify** (MA → *Réglages → Providers* →
reload, ou API `config/providers/reload`). Après reload, la recherche remonte
(`artists=5 albums=5 tracks=5`).

### Vérifier le routage

```bash
# Depuis n'importe où avec le token HA :
curl -s -H "Authorization: Bearer $HA_TOKEN" \
  http://192.168.21.181:8123/api/states/media_player.playbar | jq '{state,media_title}'
```

## Sécurité / secrets

- **Aucun secret dans ce dépôt.** La clé API Soloist est stockée chiffrée par MA.
- Les tokens HA (long-lived) et MA (API) sont révocables :
  - HA : *Profil → Sécurité → Tokens*.
  - MA : *Réglages → Jetons d'API*.
- Home Assistant n'est **pas** derrière Authelia (cf. audit SEC-2) ; en tenir
  compte pour l'exposition.

## Suivi — reste à faire

État au **2026-09-26** (fin de session). Détail par bloc.

### Fait (pour mémoire)

- [x] Areas assignées (Salon, Cuisine, Chambre des enfants, Chambre de Lou,
      Salle de bains, Notre Chambre) ; `script.musique_personne` route par area
      (+ TTS de repli). Testé.
- [x] Pipeline **Assist FR** par défaut (STT/TTS cloud `fr-FR`), players non-MA
      retirés d'Assist. Testé.
- [x] Plugin MA **Spotify Connect** (Soloist) → 3 Sonos publiés.
- [x] Dépannage « recherche Spotify bloquée » (reload provider) documenté.
- [x] Playlists nommées : `script.musique_playlist` + déclencheurs de phrase
      (lea, lou, charlotte, cedric, miraculous) + wrappers Alexa exposés. Testé.

### À faire — côté utilisateur (hors API)

- [ ] **Révoquer/régénérer les tokens HA et MA** exposés en session.
- [ ] **iPhone** : créer le raccourci « Assist in app » (pipeline *Assist FR*)
      et **désactiver « On-device STT »** (sinon dictée Apple au lieu du cloud FR).
- [ ] **Alexa** : créer une routine par playlist → `script.musique_playlist_<clé>`.
- [ ] **Vérifier Spotify Connect** dans l'app Spotify (cibles Salon/Cuisine/
      Chambre des enfants visibles) → dépend du **mDNS/VLAN** (cf. § Phase B).
- [ ] **Confirmer les associations** des playlists nommées (surtout Lou =
      « M'y Lou », Charlotte = « Liked Songs Boulet », Cédric = Liked) et
      indiquer les **noms supplémentaires** à brancher.

### À faire — implémentation (peut être assistée via API)

- [ ] **Léa** : créer le profil complet (compte Spotify Family + provider MA +
      user MA + entrée `profils`/`playlists` + wrapper + exposition Alexa).
- [ ] **Phase D** : 1× **HA Voice PE** en pièce de vie, puis extension (Chambre de
      Lou, chambre des enfants) — voix locale mains-libres.
- [ ] **Option E (labo)** : player provider Alexa de MA pour cibler les Echo
      (pièces sans Sonos : Lou, salle de bains, Notre Chambre).
- [ ] **Playlists nommées** : ajouter les autres noms demandés au même modèle.
- [ ] **Assist sans pièce** : le défaut est `media_player.playbar` (Salon) —
      éventuellement rendre la cible dépendante de la pièce de l'appareil Assist.
- [ ] Surveiller le **provider Spotify MA** (search bloquée de nouveau ?) → reload.

### Doc / repo

- [ ] Ces changements de doc ne sont pas commités (`docs/music-home.md`,
      `docs/audit-2026-09.md`, `AGENTS.md`) — committer au prochain passage
      (`nix flake check` inutile : aucun `.nix` touché).
