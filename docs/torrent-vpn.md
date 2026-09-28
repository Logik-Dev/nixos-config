# Torrent + VPN (qBittorrent / AirVPN) — hôte hyper

Stack d'acquisition torrent, isolée du reste du réseau par un tunnel AirVPN
avec kill-switch fail-closed. Usenet (SABnzbd) reste le chemin principal ;
le torrent sert pour les trackers privés/alternatifs.

## Vue d'ensemble

```
Internet ──UDP 1637──> AirVPN (wg0, table 4242, fwMark 0x4242)
                            │
        ip rule pref 200 : uid qbittorrent/prowlarr ──> table 4242
                            │
   nft « vpn_killswitch » (output) : accepte fwmark, lo, LAN, wg0 ; droppe le reste
                            │
   qBittorrent (natif, group media) ── port forward AirVPN TCP+UDP ──> peers
   Prowlarr (DynamicUser) ── requêtes indexers via VPN, LAN direct autorisé
```

Le reste de l'hôte (Traefik, Tailscale, AdGuard, *arr, SSH) garde la route
normale : aucune route par défaut n'est ajoutée à la table `main`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `modules/features/downloads/vpn.nix` | `flake.modules.nixos.vpn-torrent` : interface wg0, routage par UID, kill-switch, firewall |
| `modules/features/downloads/qbittorrent.nix` | `flake.modules.nixos.qbittorrent` : service, Traefik/Authelia, permissions, backup, notify |
| `modules/hosts/hyper/configuration.nix` | imports + valeurs AirVPN (`vpn.airvpn`) + chemins des secrets |
| `secrets/hosts/hyper/airvpn-private.key.age` | clé privée WireGuard (agenix) |
| `secrets/hosts/hyper/airvpn-psk.key.age` | preshared key WireGuard (agenix) |

## AirVPN

### Côté compte AirVPN

1. **VPN Devices** : un device dédié (clé WireGuard). La clé publique du client
   doit être `jq+IYKs1ZcqP8W+SrmYoMNtzMFqKCJuq0zpkqIGXgFg=` (vérifier avec
   `sudo wg show wg0 public-key`).
2. **Config Generator** → WireGuard : récupérer `Address`, `PrivateKey`,
   `PresharedKey`, `PublicKey` (serveur), `Endpoint`.
3. **Ports** : demander un port forward **TCP+UDP** (≥ 2048), lié **au device
   dédié**. Un forward AirVPN a un **port public** (celui que les pairs
   joignent) et un champ `Local` (port d'écoute côté machine). **Ils doivent
   être égaux** : qBittorrent annonce son port d'écoute aux trackers, donc si
   `Local` diffère du public, il annonce un port fermé → **injoignable**.
   Port actuel : **47594** (public = local), reporté dans
   `vpn.airvpn.forwardedPort`.

> ⚠️ Le port forward est lié à la clé/device : si la clé change, réassigner le
> port au nouveau device. Les clés serveur AirVPN (`PyLC...`) sont globales.
> Vérifier la joignabilité : `sudo -u qbittorrent curl -s
> https://ifconfig.co/port/47594` doit renvoyer `reachable:true` (ou bouton
> *TCP Test* vert sur AirVPN).

### Côté NixOS (hyper)

Valeurs non secrètes dans `modules/hosts/hyper/configuration.nix` :

```nix
vpn.airvpn = {
  enable = true;
  address = "10.150.11.114/32";
  publicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
  endpoint = "nl3.vpn.airdns.org:1637";
  forwardedPort = 47594;
  privateKeyFile = config.age.secrets."airvpn-private.key".path;
  presharedKeyFile = config.age.secrets."airvpn-psk.key".path;
};
```

- **Chemins agenix** : `/run/agenix/<nom>` (et non `/run/agenix.d/<nom>` —
  ce dernier contient les générations internes).
- Ajout/renouvellement : `agenix -e secrets/hosts/hyper/airvpn-private.key.age`
  puis `nix run .#agenix-rekey`, `git add` (flake = arbre git).
- L'interface utilise `table = "4242"`, `fwMark = "0x4242"`, `mtu = 1320`,
  `persistentKeepalive = 15` et `dynamicEndpointRefreshSeconds = 3600`.
  `nl3.vpn.airdns.org` est un **pool d'entry IP** : une re-résolution trop
  fréquente (ex. 300 s) bascule sur un autre serveur → l'IP de sortie change
  et les connexions pairs tombent. 1 h garde une IP stable tout en conservant
  le failover DNS.

## Routage (policy routing)

| Priorité | Sélecteur | Table | Rôle |
|---|---|---|---|
| 50 | `fwmark 0x4242` | `main` | paquets de transport WireGuard (ne jamais les router dans le tunnel) |
| 100 | `uidrange <uid>` + `to <LAN>` | `main` | exceptions LAN des UIDs routés |
| 100 | `uidrange <uid>` + `to <Tailscale>` | `52` | MagicDNS (100.100.100.100) des UIDs routés |
| 200 | `uidrange <uid>` | `4242` | trafic applicatif des UIDs routés |

- Table 4242 : `default dev wg0` (ajoutée par le module WireGuard via `table`).
- `lanNetworks` par défaut : `192.168.10.0/24`, `192.168.21.0/24`.
- `tailscaleNetworksV4/V6` : `100.64.0.0/10`, `fd7a:115c:a1e0::/48`, routés
  vers la **table 52** de Tailscale. Indispensable car **Tailscale MagicDNS
  (100.100.100.100) est le resolver système** sur hyper (`/etc/resolv.conf`
  généré par resolvconf) : sans cette exception, les requêtes DNS des UIDs
  routés partent dans wg0 et timeout → les trackers renvoient
  « Host not found (non-authoritative) » (`EAI_AGAIN`) et le torrent ne démarre
  jamais.
- **Ne jamais ajouter `100.64.0.0/10` à `lanNetworks`** : la règle serait
  globale et pointerait vers `main` (au lieu de la table 52), ce qui écrase la
  policy routing de Tailscale (priorité 5210) et coupe le mesh/SSH distant.
- Les règles sont scopées par UID : le reste de l'hôte n'est pas affecté.

## Kill-switch (nftables)

Table dédiée `inet vpn_killswitch` (⚠️ ne pas activer `networking.nftables.enable`
globalement : casserait libvirt/podman). Chaîne `output`, ordre des règles :

1. `meta mark 0x4242 accept` — transport WireGuard
2. `meta skuid != { <uids routés> } accept` — tout le reste de l'hôte
3. `oifname "lo" accept`
4. `ip daddr <LAN> accept`
5. `oifname "wg0" accept` — trafic applicatif encapsulé
6. `counter drop`

Comportement **fail-closed** : si wg0 tombe, les routes de la table 4242
disparaissent et le drop s'applique → aucune fuite WAN.

> ⚠️ Sans le `fwMark`, les paquets de transport WireGuard (générés par le noyau)
> sont droppés par la règle 6 : handshake impossible. C'est le bug qui a coûté
> le plus cher lors de la mise en place.

## qBittorrent

- Service natif (`services.qbittorrent`), `user = qbittorrent`,
  `group = media`, `UMask = 0002`.
- `profileDir = /mnt/ultra/qbittorrent` (config + état, sauvegardé).
- WebUI : `8090` → `https://qbittorrent.hyper.logikdev.fr` (Traefik + Authelia,
  catégorie Glance « Médias », icône `di:qbittorrent`).
- `torrentingPort = 47594` (dérivé de `vpn.airvpn.forwardedPort`, doit
  correspondre au **port public** du forward AirVPN).
- `serverConfig = {}` volontairement : le `qBittorrent.conf` reste inscriptible
  par l'UI (sinon tmpfiles le remplace par un symlink en lecture seule à chaque
  activation et les réglages UI sont perdus).
- **Ne pas binder l'interface réseau sur `wg0`** (Options → Avancé) : les
  requêtes DNS sortiraient avec la source `wg0` et MagicDNS ne répondrait pas.
  Le kill-switch assure déjà l'étanchéité, le bind est inutile.
  Config actuelle : `Session\Interface=` vide.
- `extraArgs = [ "--confirm-legal-notice" ]` (évite le prompt au premier boot).
- `systemd.services.qbittorrent-permissions` : `chown -R qbittorrent:media`
  du profil avant démarrage (reliquats d'anciens tests).
- Firewall : port 47594 TCP+UDP ouvert **sur wg0 uniquement** ;
  `checkReversePath = "loose"` (sinon le rp_filter strict droppe l'ingress P2P).
- Backups : `backups.sources.qbittorrent = /mnt/ultra/qbittorrent` ;
  `notify.services = [ "qbittorrent" ]`.

## cross-seed (ratio automatique)

`modules/features/downloads/cross-seed.nix` — croise la bibliothèque avec les
trackers pour seeder le même contenu sur plusieurs trackers **sans
télécharger** (gros levier de ratio, aucun risque de H&R).

- `dataDirs` = branches `/mnt/medias1/medias` + `/mnt/medias2/medias` (pas le
  pool mergerfs : cross-seed choisit le `linkDir` par device, condition pour
  que le hardlink fonctionne).
- `linkDirs` = `/mnt/medias{1,2}/cross-seed-links` (tmpfiles `2775
  cross-seed:media`).
- Torrents injectés dans qBittorrent, catégorie `cross-seed-link`, save path
  sous le linkDir du tracker.
- `matchMode = "partial"`, `linkType = "symlink"` (mergerfs),
  `useGenConfigDefaults = true`, `searchLimit = 300`.
- Secret `cross-seed-secrets.json.age` : `apiKey`, `torznab` (URLs Torznab
  Prowlarr : C411 id 4, YggReborn id 5), `torrentClients`
  (`qbittorrent:http://user:pass@127.0.0.1:8090`, mot de passe URL-encodé si
  nécessaire).
- Le module s'active dès que le secret existe (`config.age.secrets ? …`) :
  créer le secret, `nix run .#agenix-rekey`, `git add`, puis déployer.
- cross-seed est dans `vpn.airvpn.routedUsers` (uid 972) : ses requêtes
  trackers (via Prowlarr) sortent par le VPN, comme qBittorrent, et il est
  couvert par le kill-switch.
- Ajouter un tracker = ajouter son URL Torznab Prowlarr dans le secret + rekey.
- Vérifs : `journalctl -u cross-seed`, torrents dans la catégorie
  `cross-seed-link` de qBittorrent.
- Doc upstream : <https://www.cross-seed.org>

## freeleech-farmer (ratio sans rien chercher)

`modules/features/downloads/freeleech-farmer.{nix,py}` — timer systemd (toutes
les 30 min) qui interroge les Torznab de la config cross-seed, ne garde que le
**freeleech** (`downloadvolumefactor=0`) et l'ajoute à qBittorrent dans la
catégorie `freeleech`.

- Tourne sous l'utilisateur `cross-seed` (uid 972, déjà routé VPN +
  kill-switch) ; réutilise le secret `cross-seed-secrets.json.age`
  (`torznab` + `torrentClients`).
- Filtres/limites (env du service) : `FARMER_MAX_ADDS=5`,
  `FARMER_MAX_SIZE_GB=20`, `FARMER_MAX_TOTAL_GB=100`, `FARMER_MIN_FREE_GB=200`,
  `FARMER_CLEAN_RATIO=2.0`, `FARMER_CLEAN_DAYS=14`, catégories Torznab
  autorisées (préfixes 2/3/5/7, XXX exclu).
- Nettoyage : les torrents `freeleech` sont supprimés (fichiers compris) au
  ratio ≥ 2 ou après 14 jours.
- Cible principale : YggReborn (freeleech auto sur les torrents peu seedés) ;
  C411 a peu de freeleech mais est scanné aussi.
- Logs : `journalctl -u freeleech-farmer` ; test manuel :
  `sudo systemctl start freeleech-farmer`.

## Prowlarr (DynamicUser)

`services.prowlarr` tourne en **DynamicUser** : son UID n'existe qu'à partir du
démarrage de l'unité. Les services `vpn-policy-routing` et `vpn-killswitch` sont
donc :

- `after = [ "prowlarr.service" ]` (résolution de l'UID correcte),
- `partOf = [ "prowlarr.service" ]` (réapplication à chaque restart de Prowlarr),
- `before = [ "qbittorrent.service" ]` (fail-closed avant qBittorrent).

qBittorrent, lui, est un utilisateur système classique (uid stable).

## Exploitation / diagnostics

```bash
# Tunnel
sudo wg show wg0                       # handshake + transfert + fwmark
ip rule show                           # 50 / 100 / 200
ip route show table 4242               # default dev wg0

# Kill-switch (nft n'est pas dans le PATH utilisateur)
N=$(ls -d /nix/store/*-nftables-*/bin/nft | head -1)
sudo "$N" list table inet vpn_killswitch

# Sortie effective par UID
sudo -u qbittorrent /run/current-system/sw/bin/curl -s https://api.ipify.org
sudo -u prowlarr    /run/current-system/sw/bin/curl -s https://api.ipify.org
# → IP de sortie AirVPN ; l'utilisateur logikdev doit voir l'IP WAN

# Test fail-closed
sudo systemctl stop wireguard-wg0
sudo -u qbittorrent curl --max-time 5 https://api.ipify.org   # doit timeout
curl -s -o /dev/null -w '%{http_code}' http://192.168.10.100:8090  # LAN OK
sudo systemctl start wireguard-wg0

# Capture bas niveau (handshake)
TCP=$(nix build --no-link --print-out-paths nixpkgs#tcpdump)/bin/tcpdump
sudo timeout 30 "$TCP" -ni management udp port 1637
```

## Configuration *arr (runtime, non déclarative)

1. **qBittorrent** (WebUI) :
   - mot de passe permanent (Options → WebUI) ; le mot de passe temporaire est
     dans `journalctl -u qbittorrent | grep -i "mot de passe temporaire"` ;
   - chemins : `/mnt/storage/medias/downloads` (complets),
     `.../downloads/incomplete` (incomplets) ;
   - catégories `movies` / `series` avec save paths dédiés (miroir SABnzbd) ;
   - Seeding Limits : ratio atteint → « Remove torrent and its files »
     (le seed s'arrête, la copie bibliothèque reste).
2. **Sonarr / Radarr** : Download Client qBittorrent (`127.0.0.1:8090`),
   catégories `series`/`movies`, **Completed Download Handling → Remove = No**
   (garde le seed).
3. **Import en copie** : il n'y a pas de réglage explicite. Tant que le torrent
   est en seed, l'arr **copie** (ou hardlink) au lieu de déplacer. Avec mergerfs
   (`category.create=mfs`), le hardlink ne fonctionne que si download et
   bibliothèque sont sur la même branche ; sinon copie (doublon temporaire
   jusqu'à la fin du seed).
4. **Prowlarr** : indexers (C411, YggReborn…), synchronisation des apps.
   Prowlarr sort par la même IP VPN que qBittorrent (cohérence tracker).

### Qualité & codecs (x265 > x264, AV1 exclu)

Configuré via les API Sonarr/Radarr (runtime, pas Nix). Custom formats à
scores **additifs** + `cutoffFormatScore = 200` (upgrade jusqu'à x265) :

| Format | Score | Cumul |
|---|---|---|
| x265 | 200 | 200 |
| x265 MULTI | 50 | 250 |
| x264 | 100 | 100 |
| x264 MULTI | 50 | 150 |
| AV1 | 0 | 0 → **rejeté** |
| AV1 MULTI | 0 | 0 → **rejeté** |

AV1 est volontairement **rejeté** (score 0 < `minFormatScore`) : le P4000
n'a pas de décodage AV1 matériel, Jellyfin transcoderait en CPU. Les custom
formats AV1 restent définis, il suffit de changer leur score pour les
réactiver.

Le codec domine le bonus MULTI ; l'ordre des qualités du profil
(2160p > 1080p) reste prioritaire sur les scores. `minFormatScore` :
50 (Radarr) / 49 (Sonarr) → les releases sans codec identifiable sont
refusées (comportement existant).

Plafonds de taille (MB/min) : 2160p WEBDL/WEBRip 220, Bluray 320, Remux 480 ;
1080p Bluray 150, Remux 250 ; Sonarr Remux 1080p 220.

## Ajouter un utilisateur au VPN

1. Ajouter le nom dans `vpn.airvpn.routedUsers` (défaut :
   `[ "qbittorrent" "prowlarr" "cross-seed" ]`).
2. Si le service est un **DynamicUser**, ajouter son unité aux listes
   `after`/`partOf` de `vpn-policy-routing` et `vpn-killswitch` (voir Prowlarr).
3. Redéployer, puis vérifier `ip rule show` et la sortie effective
   (`sudo -u <user> curl ifconfig.me`).

## Pièges connus / leçons

- **fwMark obligatoire** : sans lui, le kill-switch droppe le transport
  WireGuard (handshake OK sans kill-switch, KO avec).
- **DNS & Tailscale** : hyper résout via **Tailscale MagicDNS**
  (100.100.100.100, `/etc/resolv.conf` géré par resolvconf). Les UIDs routés
  ont besoin de l'exception scopée vers la table 52 (`tailscaleNetworksV4/V6`),
  sinon leurs requêtes DNS partent dans wg0 → `EAI_AGAIN` → les trackers
  répondent « Host not found (non-authoritative) » et le torrent ne démarre pas.
- **Jamais `100.64.0.0/10` dans `lanNetworks`** : règle globale vers `main`,
  écrase Tailscale (priorité 5210) et coupe le mesh/SSH distant (vécu).
- **Redémarrer qBittorrent après un changement de routage DNS** : son cache
  négatif de résolution persiste (« Host not found ») même une fois le DNS
  réparé.
- **agenix** : les secrets sont à `/run/agenix/<nom>` ; l'auto-découverte exige
  le `git add` des `.age` (flake = arbre git).
- **Config AirVPN en CRLF** : comparer les clés en strippant `\r` (un hash naïf
  donne de faux « mismatch »).
- **Handshake ≠ données** : un handshake réussi ne garantit pas la validité de
  l'adresse ; mais une clé/adresse d'un autre device donne handshake OK et zéro
  donnée.
- **DNS non tunnelisé** : qBittorrent/Prowlarr résolvent via AdGuard (DoT Quad9
  depuis l'IP WAN). Pas de fuite en clair, mais pas d'isolation DNS totale.
- **IP de sortie mutualisée** : certains trackers privés la tolèrent plus ou
  moins ; le port dédié améliore la connectabilité.
- **Torrents cross-seed en rouge (`state=error`)** : le log qBittorrent
  (`/api/v2/log/main`) montre `file_open (.../<release>.nfo) error: Permission
  non accordée`. Cause : cross-seed crée les sous-dossiers de
  `cross-seed-links/` avec `UMask=0022` → mode **2755** (groupe `media` sans
  écriture). Les torrents YggReborn/C411 embarquent un `.nfo` absent de la
  bibliothèque (l'import *arr ne garde que le `.mkv`), donc qBittorrent doit le
  créer/télécharger, mais il tourne en `qbittorrent:media` et n'a pas le droit
  d'écriture sur le dossier → `EACCES` → torrent en `error`. Fix : `UMask=0002`
  sur `cross-seed.service` (+ règle tmpfiles `Z` pour rattraper les dossiers
  existants). cross-seed ne reprend pas ces torrents lui-même (« Will not
  resume ... state is error ») : les `resume` une fois les droits corrigés.
- **Kill-switch / policy routing tombés après le backup Prowlarr** : le backup
  restic de Prowlarr fait `systemctl stop prowlarr` puis `start`
  (`restic.nix`, `manageService`). Comme `vpn-policy-routing` et
  `vpn-killswitch` ont `partOf=prowlarr.service`, le **stop** se propage mais
  pas le **start** : les règles `ip rule` et la table nft sont supprimées et ne
  reviennent pas → qBittorrent/Prowlarr/cross-seed sortent par l'IP WAN
  (fuite) jusqu'au reboot. Fix : ajouter `wantedBy = [ "prowlarr.service" ]` aux
  deux unités pour qu'un `start` de Prowlarr les remonte. Vérif :
  `systemctl status vpn-policy-routing vpn-killswitch` + `ip rule show`.
- **ACME dépend du DNS public** : si `logikdev.fr` ne résout pas publiquement
  (zone Cloudflare `moved`, `clientHold` registraire…), Traefik sert son
  certificat par défaut (`ERR_CERT_AUTHORITY_INVALID`) pour tout nouveau
  hostname. Vérifier `nslookup qbittorrent.hyper.logikdev.fr 1.1.1.1` et
  `journalctl -u traefik | grep -i acme`.
- **Sécurité** : ne jamais committer un `.conf` AirVPN en clair
  (`.gitignore` : `AirVPN_*.conf`) ; si exposé (Nix store, git), rotater la clé.
