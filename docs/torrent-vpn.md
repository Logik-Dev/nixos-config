# Torrent + VPN (qBittorrent / AirVPN) — hôte hyper

Stack d'acquisition torrent, isolée du reste de l'hôte par un **network
namespace dédié** contenant le tunnel AirVPN. Usenet (SABnzbd) reste le chemin
principal ; le torrent sert pour les trackers privés/alternatifs.

## Vue d'ensemble

Stack d'acquisition torrent, isolée du reste de l'hôte par un **network
namespace dédié** (`vpn`) dans lequel vit le tunnel AirVPN. Usenet (SABnzbd)
reste le chemin principal ; le torrent sert pour les trackers privés/alternatifs.

```
                 namespace hôte                 │        namespace « vpn »
                                                │
Internet ──UDP 1637──> socket WireGuard ────────┼──> wg0 (10.150.11.114/32)
                       (reste ici !)            │     └─ default dev wg0
                                                │
   Traefik ─── 10.200.0.2:8090/9696 ────────────┼──> qBittorrent, Prowlarr,
   Sonarr/Radarr <── 10.200.0.1:8989/7878 ──────┼──   cross-seed, freeleech-farmer
                    veth-vpn-host   veth-vpn    │
                    10.200.0.1/30   10.200.0.2/30
```

**Le fail-closed est structurel** : la seule route par défaut du namespace est
`wg0`. Si le tunnel tombe, il ne reste que le `/30` connecté — les services
reçoivent `ENETUNREACH`, il n'y a aucune règle de pare-feu à maintenir correcte.
Ils restent vivants (dépendance `wants`, jamais `requires`) et repartent seuls.

Seule l'**interface** part dans le namespace : la **socket de transport**
WireGuard reste côté hôte et suit la route normale. C'est le montage canonique
de <https://www.wireguard.com/netns/>, et c'est ce qui explique plusieurs pièges
plus bas.

Le reste de l'hôte (Traefik, Tailscale, AdGuard, *arr, SSH) est intouché.

> Historique de la migration, avec les sept pièges rencontrés et les tests
> d'acceptation : `docs/vpn-netns-plan.md`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `modules/features/downloads/vpn.nix` | `flake.modules.nixos.vpn-torrent` : namespace `vpn`, veth, wg0, resolv.conf d'amorçage, drop-in partagé des services |
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
- L'interface utilise `interfaceNamespace = "vpn"` (`socketNamespace` reste
  `null` : la socket de transport demeure côté hôte), `mtu = 1320`,
  `persistentKeepalive = 15` et `dynamicEndpointRefreshSeconds = 3600`.
  **Ni `table` ni `fwMark`** : la table `main` *du namespace* est la bonne, et
  la marque n'existait que pour tromper le kill-switch, supprimé.
  `nl3.vpn.airdns.org` est un **pool d'entry IP** : une re-résolution trop
  fréquente (ex. 300 s) bascule sur un autre serveur → l'IP de sortie change
  et les connexions pairs tombent. 1 h garde une IP stable tout en conservant
  le failover DNS.
## Isolation (network namespace)

Tout est dans `vpn.airvpn.netns.*` :

| Option | Défaut | Rôle |
|---|---|---|
| `name` | `vpn` | nom du namespace ; dérive `veth-vpn-host` / `veth-vpn` (15 car. max) |
| `hostAddress` | `10.200.0.1` | bout hôte de la veth |
| `namespaceAddress` | `10.200.0.2` | bout namespace — l'adresse où Traefik joint qBittorrent/Prowlarr |
| `prefixLength` | `30` | un /30 : la route connectée ne couvre que le pair, donc aucun chemin vers le LAN ou le WAN par la veth |
| `resolver` | `10.128.0.1` | résolveur **dans le tunnel** pour les services |
| `hostPorts` | `[8989 7878]` | ports hôte ouverts **sur la veth seulement** (synchro d'apps Prowlarr → Sonarr/Radarr) |
| `services` | `[ ]` | unités déplacées dans le namespace — **chaque module s'ajoute lui-même** |

`netns-vpn.service` crée le namespace une fois et **ne le détruit jamais** : un
`ip netns del` laisserait les services attachés dans un namespace fantôme, sans
route et **sans échouer**. L'unité n'a aucune option de sandboxing (le
bind-mount de `/run/netns` doit rester visible) et est idempotente.

Une table nft `vpn_guard` dans le namespace épingle la veth à son pair. Elle
n'est pas que défensive : qBittorrent lie un listener au device veth et y envoie
du trafic pair, que cette règle jette (voir Pièges).

## Ce qui traverse la frontière

| Sens | Chemin |
|---|---|
| Traefik → qBittorrent / Prowlarr | `10.200.0.2:8090` / `:9696` (`traefik.services.<n>.host`) |
| Prowlarr → Sonarr / Radarr (synchro d'apps) | `10.200.0.1:8989` / `:7878` |
| Sonarr / Radarr → qBittorrent | `10.200.0.2:8090` (runtime, UI) |
| Bindery → qBittorrent / Prowlarr | `10.200.0.2:8090` / `:9696` (runtime, UI) |
| cross-seed / freeleech-farmer → qBittorrent | `127.0.0.1:8090` — **inchangé**, même namespace |
| Prowlarr → PostgreSQL | socket Unix `/var/run/postgresql` — **inchangé**, indifférent au réseau |

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
- **Binder l'interface réseau sur `wg0`** (Options → Avancé) est désormais
  **recommandé**, et ne l'était pas avant : l'ancienne objection (la source `wg0`
  cassait la résolution MagicDNS) est levée puisque le namespace résout par le
  tunnel. Sans ce bind, qBittorrent écoute aussi sur la veth et y envoie du
  trafic pair pour rien (jeté par `vpn_guard`, cf. Pièges).
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
- cross-seed est dans `vpn.airvpn.netns.services` : il vit dans le même
  namespace que qBittorrent et Prowlarr, donc ses requêtes trackers sortent par
  le VPN et ses appels `127.0.0.1:8090` / `:9696` fonctionnent inchangés.
- Ajouter un tracker = ajouter son URL Torznab Prowlarr dans le secret + rekey.
- Vérifs : `journalctl -u cross-seed`, torrents dans la catégorie
  `cross-seed-link` de qBittorrent.
- Doc upstream : <https://www.cross-seed.org>

## freeleech-farmer (ratio sans rien chercher)

`modules/features/downloads/freeleech-farmer.{nix,py}` — timer systemd (toutes
les 30 min) qui interroge les Torznab de la config cross-seed, ne garde que le
**freeleech** (`downloadvolumefactor=0`) et l'ajoute à qBittorrent dans la
catégorie `freeleech`.

- Tourne sous l'utilisateur `cross-seed`, dans le namespace VPN (il s'y ajoute
  via `vpn.airvpn.netns.services`) ; réutilise le secret `cross-seed-secrets.json.age`
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

## Prowlarr (DynamicUser) — un non-problème désormais

`services.prowlarr` tourne en **DynamicUser** : son UID n'existe qu'à partir du
démarrage de l'unité. C'était la faiblesse centrale de l'ancienne isolation par
UID (règles à réappliquer à chaque restart, d'où une fuite WAN silencieuse quand
le backup restic faisait `stop`/`start`).

L'appartenance au namespace étant fixée **par unité** au démarrage
(`NetworkNamespacePath`), rien de tout cela ne subsiste : Prowlarr est traité
exactement comme les autres. Son accès PostgreSQL passe par la socket Unix,
insensible au namespace réseau.
## Exploitation / diagnostics

> **`wg0` n'apparaît plus dans un `ip a` sur l'hôte** — c'est normal, il est dans
> le namespace. Presque toute commande réseau doit être préfixée.

```bash
# Tunnel (wg0 vit dans le namespace)
sudo ip netns exec vpn wg show wg0        # handshake + transfert
sudo ip netns exec vpn ip route           # default dev wg0 + 10.200.0.0/30
sudo ip netns exec vpn ip -br a           # lo UP, veth-vpn, wg0

# Sortie effective
sudo ip netns exec vpn curl -s https://api.ipify.org   # IP AirVPN
curl -s https://api.ipify.org                          # IP WAN de l'hôte

# Ce que voit un service donné (son namespace réseau ET son resolv.conf)
P=$(systemctl show -p MainPID --value qbittorrent)
sudo nsenter -t "$P" -n -- curl -s https://api.ipify.org   # doit être l'IP AirVPN
sudo nsenter -t "$P" -m cat /etc/resolv.conf              # doit être 10.128.0.1
sudo readlink /proc/"$P"/ns/net                            # != celui de /proc/1/ns/net

# Port forward (critique pour le ratio)
sudo ip netns exec vpn curl -s https://ifconfig.co/port/47594   # reachable:true
sudo ip netns exec vpn ss -tlnp | grep 47594  # DOIT inclure un listener sur wg0

# Fail-closed (structurel : plus de route du tout)
sudo systemctl stop wireguard-wg0
sudo ip netns exec vpn ip route               # plus que le /30
sudo ip netns exec vpn curl --max-time 5 https://api.ipify.org  # échoue
sudo systemctl start wireguard-wg0

# Garde-fou veth
N=$(ls -d /nix/store/*-nftables-*/bin/nft | head -1)
sudo ip netns exec vpn "$N" list table inet vpn_guard
# Pour voir *quoi* est droppé, le `log` nft d'un namespace non-init est
# silencieusement jeté : sudo sysctl -w net.netfilter.nf_log_all_netns=1

# Santé du boot — `systemctl --failed` vide ne suffit PAS
systemctl is-system-running
sudo journalctl -b | grep "ordering cycle"    # doit être vide
```

> ⚠️ **Deux tests qui mentent.** Un `curl` lancé *depuis hyper* vers sa propre IP
> LAN passe par `lo` et est accepté par le pare-feu : il ne prouve rien sur
> l'ouverture d'un port — tester depuis une autre machine, ou lire `iptables -S`.
> Et Traefik n'écoute que sur `192.168.10.100`, donc `https://127.0.0.1` renvoie
> `000` sans que rien ne soit cassé.

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

## Ajouter un service au VPN

C'est désormais **par unité**, pas par utilisateur.

1. Dans le module du service, ajouter `vpn.airvpn.netns.services = [ "<unite>" ];`
   — **depuis son propre module**, pas depuis `vpn.nix`, pour qu'une unité
   conditionnellement activée ne laisse pas d'unité fantôme (cf. FAC-5).
2. Si le service doit joindre un service de l'hôte, ajouter son port à
   `vpn.airvpn.netns.hostPorts` (ouvert **sur la veth uniquement**).
3. S'il **écoute** pour des connexions entrantes par le tunnel, lui ajouter
   `partOf` + `wantedBy` sur `wireguard-wg0.service` (voir qBittorrent) : sinon
   il ne se réattachera pas à un `wg0` recréé et son port deviendra injoignable
   en silence.
4. Redéployer, puis vérifier :
   `sudo readlink /proc/$(systemctl show -p MainPID --value <unite>)/ns/net`
   (différent de `/proc/1/ns/net`) et la sortie effective via `nsenter -n`.

> ⚠️ Ne **jamais** donner un défaut non vide à `vpn.airvpn.netns.services` : un
> défaut n'est pas une définition, les contributions des modules le
> **remplaceraient** au lieu de l'étendre, et des services sortiraient du
> namespace sans que rien ne le signale.

## Pièges connus / leçons

- **`systemctl --failed` vide ≠ boot sain.** Un cycle d'ordonnancement systemd
  fait *supprimer* un job de démarrage sans aucune unité en échec : le tunnel ne
  démarrait pas du tout au boot (`is-system-running` = `degraded`, `--failed`
  vide). Ne jamais remettre d'ordonnancement DNS sur `wireguard-wg0` — créer
  l'interface ne résout aucun nom. Vérifier `journalctl -b` sur « ordering cycle ».
- **qBittorrent ne se réattache pas à un `wg0` recréé.** Il énumère les
  interfaces au démarrage ; si le tunnel est recréé sous lui il n'écoute plus que
  sur `lo`/veth, le port forwardé devient injoignable et **le ratio tombe à zéro
  sans unité en échec**. D'où `partOf` + `wantedBy` sur `wireguard-wg0.service`.
  Vérif : `ip netns exec vpn ss -tlnp | grep wg0`.
- **qBittorrent envoie du trafic pair sur la veth.** Il lie un listener au device
  veth (`10.200.0.2%veth-vpn:47594`) et y émet du UDP pair/DHT vers des adresses
  publiques — ~460 paquets dans les 40 s suivant un restart du tunnel. Ça ne
  fuite pas (le `/30` n'est pas masqueradé, `tcpdump` sur le WAN le confirme),
  mais c'est du trafic mort ; la table `vpn_guard` le jette. **Correction propre,
  à faire côté UI** : fixer l'interface réseau de qBittorrent sur `wg0`
  (Options → Avancé), ce qui est désormais sans risque — l'ancienne objection
  (le bind cassait MagicDNS) est levée puisque le namespace résout par le tunnel.
- **`wg show` ment sur l'émission** : il compte les octets remis à la pile, pas
  ceux réellement partis. Le seul diagnostic fiable d'un transport bloqué est
  `tcpdump -nni management udp port 1637`.
- **Le `log` nft d'un namespace non-init est jeté en silence** : pour voir ce que
  `vpn_guard` droppe, `sudo sysctl -w net.netfilter.nf_log_all_netns=1`.
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
- **DNS tunnelisé** (depuis la migration netns) : les services résolvent via
  `10.128.0.1`, le résolveur AirVPN, *dans* le tunnel. Deux `resolv.conf`
  distincts coexistent — celui du namespace (`/etc/netns/vpn/resolv.conf` →
  AdGuard par la veth) sert à l'**amorçage**, parce que `wg set … endpoint`
  s'exécute dans le namespace et doit résoudre avant que le tunnel existe.
  `NetworkNamespacePath` ne bind-montant pas `/etc/netns/*`, les services ont le
  leur par `BindReadOnlyPaths`. Un bind raté ne fuite pas : il donne un timeout.
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
- **Historique — fuite au backup Prowlarr** (résolue par la migration) : le
  backup restic fait `stop` puis `start` de Prowlarr ; les unités d'isolation
  avaient `partOf=prowlarr.service`, qui propage le **stop** mais pas le
  **start** → règles `ip rule` et table nft supprimées jusqu'au reboot, et
  sortie par l'IP WAN. C'est cette classe de bug — l'isolation recalculée à
  partir d'un UID à l'exécution — que le namespace élimine par construction.
  La leçon `partOf` sans `wantedBy` reste valable ailleurs (cf. qBittorrent et
  `wireguard-wg0`).
- **ACME dépend du DNS public** : si `logikdev.fr` ne résout pas publiquement
  (zone Cloudflare `moved`, `clientHold` registraire…), Traefik sert son
  certificat par défaut (`ERR_CERT_AUTHORITY_INVALID`) pour tout nouveau
  hostname. Vérifier `nslookup qbittorrent.hyper.logikdev.fr 1.1.1.1` et
  `journalctl -u traefik | grep -i acme`.
- **Sécurité** : ne jamais committer un `.conf` AirVPN en clair
  (`.gitignore` : `AirVPN_*.conf`) ; si exposé (Nix store, git), rotater la clé.
