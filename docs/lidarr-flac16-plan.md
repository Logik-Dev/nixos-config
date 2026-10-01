# Plan — FLAC 16 bits uniquement (Lidarr + slskd)

Étude d'un dispositif pour n'obtenir que du **FLAC 16 bits** via Lidarr
(torrents/usenet) et via slskd (Soulseek), avec **Soularr** comme pont
d'automatisation Lidarr → slskd.

- Statut : **abandonné / non implémenté** (2026-10-01). Décision : le besoin
  ne justifie pas le chantier, car Soularr ne lit que la *wanted-list* Lidarr
  (mainstream) ; le classique, volontairement hors Lidarr (pipeline
  beets/`parentwork`, cf. `docs/music-library-plan.md`), resterait manuel — et
  aucun outil ne peut imposer le 16 bits sur slskd en manuel.
- Périmètre étudié : nouveau `modules/features/medias/{lidarr-quality,soularr}.nix`,
  `modules/features/medias/musique-import.nix`, `secrets/hosts/hyper/{slskd.env,soularr.env}.age`.
- Ce document conserve les constats vérifiés et le plan complet, pour reprise
  éventuelle.

## Constats vérifiés (2026-10-01)

### Lidarr 3.1.0.4875 (live sur hyper)

- Qualités : `FLAC` = **id 6**, `FLAC 24bit` = **id 21**. Le parseur tranche sur
  la profondeur (`QualityParser.cs` : `Codec.FLAC → sampleSize == S24 ?
  FLAC_24 : FLAC`). Un profil n'autorisant que `FLAC` n'accepte donc que du
  16 bits.
- Profils existants : `Any` (id 1, tout autorisé), `Lossless` (id 2, groupe
  « Lossless » autorisé — contient **FLAC 24bit**), `Standard` (id 3).
- Artistes : Orelsan, Nekfeu, ISHA — **tous sur `Lossless`** (id 2).
- Les profils vivent en base (comme `metadataSource`), pas dans `config.xml` :
  aucun réglage Nix, il faut un oneshot API — même motif que
  `lidarr-metadata-switch` (`modules/features/medias/lidarr-metadata.nix`).
- Un scan d'import sans `downloadClientItem` (cas `DownloadedAlbumsScan`) passe
  en mode `Auto → Move`, puis **supprime le dossier source** après import
  réussi (`DownloadedTracksImportService.ProcessFolder`).
- Lidarr tourne `User=lidarr Group=media UMask=0002` ; les répertoires média
  sont en `2775 logikdev:media`.

### slskd 0.26.0

- **Aucun filtre qualité côté serveur ni persistant.** Les filtres de recherche
  sont côté navigateur et par recherche (`parseFiltersFromString`,
  `src/web/src/lib/searches.js` en 0.26.0) : `islossless`, `minbitrate:`,
  `minbitdepth:`, `minlength:`, etc. **Pas de `maxbitdepth`**, et les fichiers
  sans profondeur connue passent le filtre (issues amont #624/#625).
- Les PR amont #1412 (« Default web UI search filter ») et #1434 (« allow saving
  and loading filters in local storage ») sont **toujours ouvertes**.
- La clé API peut être fournie par variable d'environnement : le provider
  maison de slskd ne mappe que les propriétés portant `[EnvironmentVariable]`,
  et `WebAuthenticationOptions.ApiKey` porte `[EnvironmentVariable("API_KEY")]`
  → **`SLSKD_API_KEY`**, syntaxe `role=readwrite;cidr=10.200.0.1/32;<clé>`.
  Le dictionnaire `ApiKeys` (YAML) n'est, lui, **pas** mappable par env — et le
  mettre dans `services.slskd.settings` l'exposerait dans le store.
- Réseau : slskd écoute `:5030` dans le netns `vpn` ; depuis l'hôte on l'atteint
  sur `10.200.0.2:5030` (veth, source `10.200.0.1`).

### Soularr 1.2.x (`ghcr.io/mrusse/soularr:latest`)

- Lit les albums *wanted* de Lidarr (`missing`, `cutoff_unmet`, ou `all`) et les
  télécharge via slskd, puis importe par `DownloadedAlbumsScan`.
- `allowed_filetypes` est une liste de préférence (la plus préférée d'abord) ;
  une entrée `flac 16/44.1` **impose** bitDepth 16 et sampleRate 44100 (les
  fichiers sans attributs sont rejetés). Un seul 16/44.1 (pas de 16/48).
- Le `config.ini` supporte l'interpolation d'environnement (`${VAR}`, via
  `EnvInterpolation`) → les clés API peuvent rester dans un secret agenix.
- L'image accepte les arguments `--config-dir` / `--var-dir` (run.sh les
  transmet à `soularr.py`) ; `WEBUI_ENABLED=false` évite de lancer la WebUI.
- `nixpkgs` (`virtualisation.oci-containers`) supporte `environmentFiles`
  (→ `--env-file`) et `cmd` (surcharge du CMD, l'entrypoint `tini` est
  conservé).

## Plan complet étudié

### 1. Secrets (agenix)

Générer la clé (`openssl rand -hex 32`), puis depuis `nix develop` :

- `agenix edit secrets/hosts/hyper/slskd.env.age` → ajouter
  `SLSKD_API_KEY=role=readwrite;cidr=10.200.0.1/32;<clé>`.
- `agenix edit secrets/hosts/hyper/soularr.env.age` (nouveau, auto-découvert
  par `security/secrets.nix`) :
  `SOULARR_LIDARR_API_KEY=<clé lue dans /mnt/ultra/lidarr/config.xml>` et
  `SOULARR_SLSKD_API_KEY=<même clé slskd>`.
- `agenix rekey -a`.

### 2. `modules/features/medias/lidarr-quality.nix` (nouveau)

Oneshot `lidarr-quality-switch` calqué sur `lidarr-metadata-switch` : clé API
lue dans `/mnt/ultra/lidarr/config.xml`, `Type=oneshot`,
`RemainAfterExit=true`, `path = coreutils/curl/jq/gnused`,
`RequiresMountsFor=/mnt/ultra`, timer `OnBootSec/OnUnitInactiveSec=5min`,
`notify.services`, import dans `medias/default.nix`.

Script idempotent :

1. Construire le profil depuis `GET /api/v1/qualitydefinition` (ordre canonique,
   ids stables) :
   `name="FLAC 16 bits"`, `upgradeAllowed=true`, `cutoff=6`,
   `minFormatScore/cutoffFormatScore=0`, `formatItems=[]`, `items` = liste
   plate avec `allowed = (quality.id == 6)`.
   POST si absent, sinon PUT (corrige la dérive).
2. Réassigner **tous** les artistes (`GET /api/v1/artist` puis PUT de l'objet
   avec `qualityProfileId` du profil).
3. Supprimer les autres profils (`DELETE /api/v1/qualityprofile/<id>`), après
   réassignation → impossible d'ajouter un nouvel artiste sur un autre profil.
4. Vérifier (profil unique, tous les artistes dessus), sinon `exit 1` → le
   timer relance.

### 3. `modules/features/medias/soularr.nix` (nouveau)

Conteneur podman gaté sur `config.vpn.airvpn.enable` (motif `slskd.nix`),
calqué sur `bindery.nix` :

- `image = "ghcr.io/mrusse/soularr:latest"` ;
  `environmentFiles = [ config.age.secrets."soularr.env".path ]` ;
  `environment.TZ = config.time.timeZone`, `SCRIPT_INTERVAL=300`,
  `WEBUI_ENABLED=false` ;
  `cmd = [ "/app/run.sh" "--config-dir" "/config" "--var-dir" "/var" ]` ;
  `extraOptions = [ "--network=host" "--user=1000:991" "--umask=0002" ]`.
- `config.ini` non secret via `pkgs.writeTextDir`, monté `:/config:ro`, clés en
  `${SOULARR_*}` (échappées `''${` en Nix). Paramètres clés :
  - `[Lidarr] host_url=http://127.0.0.1:8686`,
    `download_dir=/mnt/storage/medias/downloads/slskd` ;
  - `[Slskd] host_url=http://10.200.0.2:5030`, mêmes chemins ;
  - `allowed_filetypes = flac 16/44.1`, `search_source = all`
    (missing + cutoff_unmet), `failed_import_denylist=True`,
    `rename_download_folders=True`, `number_of_albums_to_grab=10`,
    `log_to_file=False`.
- Volumes : `${configDir}:/config:ro`, `/mnt/ultra/soularr:/var`,
  `/mnt/storage/medias:/mnt/storage/medias` (chemins identiques hôte/conteneur
  → `download_dir` valable des deux côtés, comme Bindery).
- `tmpfiles` `d /mnt/ultra/soularr 2775 logikdev media`,
  `RequiresMountsFor=/mnt/storage /mnt/ultra`,
  `notify.services=["podman-soularr"]`, `backups.sources.soularr` (état seul).

### 4. Garde `musique-prepare` (`modules/features/medias/musique-import.nix`)

- Ignorer explicitement `failed_imports` dans le `case` (Soularr y déplace ses
  échecs, dans le dossier slskd).
- Sauter les entrées dont un fichier a un mtime < 15 min
  (`find "$entry" -type f -newermt "-${settle} minutes"`) : laisse Lidarr finir
  l'import (qui supprime la source) avant que la file classique ne s'en empare.

### 5. Docs

- `docs/music-library-plan.md` : section Soularr + profil Lidarr (et journal).
- `docs/services.md` : Soularr (conteneur, état, backup, pas de port exposé) et
  profil Lidarr.
- `AGENTS.md` : stack (Soularr, `allowed_filetypes`), quirks « slskd n'a pas de
  filtre qualité serveur ; `SLSKD_API_KEY` via env ; `musique-prepare` gate
  mtime/`failed_imports` ».

### 6. Validation

1. `git add` des nouveaux fichiers (le flake lit l'arbre git) puis
   `nix flake check` (+ `--all-systems --no-build`).
2. `nh os switch --hostname hyper --target-host logikdev@hyper --build-host logikdev@hyper -e passwordless`.
3. Runtime : vérifier via l'API Lidarr que seul `FLAC 16 bits` existe et que
   les artistes le portent ; tester la clé API slskd depuis hyper
   (`curl -H "X-API-Key: …" http://10.200.0.2:5030/api/v0/session`, source
   `10.200.0.1` compatible CIDR) ; suivre `journalctl -u podman-soularr`, un
   import réel (dossier créé puis **supprimé** par Lidarr, fichiers dans
   `musique/populaire`) et `musique-prepare` (aucun déplacement vers la file
   classique).

## Points d'attention

- `flac 16/44.1` est strict : les fichiers sans attributs bitDepth/sampleRate
  (certains clients Soulseek) sont ignorés, et les 16/48 ou 16/96 aussi. C'est
  le prix de l'enforcement ; assouplir (`…,flac`) réautoriserait des 24 bits.
- Soularr ne couvre que les albums présents dans Lidarr ; le classique slskd
  reste manuel — filtre UI `islossless minbitdepth:16` (pas de `maxbitdepth`).
- Supprimer `Any`/`Standard`/`Lossless` est réversible à la main en UI, et le
  service les re-supprime à chaque boot.
- Le déploiement redémarre slskd (modification de son `environmentFile`).
- Interaction `musique-prepare`/Soularr : sans garde, la passe 5 min peut
  déplacer un album en cours d'import Lidarr vers la file beets.

## Conditions de reprise

- Besoin confirmé d'automatiser slskd pour le mainstream (Lidarr) **et**
  acceptation que le classique reste manuel.
- Ou évolution amont : filtre de recherche par défaut côté slskd (PR #1412) —
  le besoin d'enforcement automatique pour le classique pourrait alors être
  couvert sans Soularr.
