# Plan — isoler le trafic VPN dans un network namespace dédié

État des lieux et plan de migration de l'isolation VPN torrent, de l'approche
actuelle (**policy routing par UID + kill-switch nft**) vers un **network
namespace dédié** (`vpn`).

- Statut : **migration terminée** le 2026-09-28. Lots A→E déployés, persistés
  et validés par deux reboots. `docs/torrent-vpn.md` et les *Known quirks* d'
  `AGENTS.md` décrivent désormais l'état netns ; ce document reste l'historique
  du raisonnement et des sept pièges rencontrés.
- Périmètre : `modules/features/downloads/{vpn,qbittorrent,cross-seed,freeleech-farmer}.nix`,
  `modules/features/networking/traefik/`, config runtime Sonarr/Radarr/Prowlarr/Bindery.
- Référence de l'implémentation actuelle : `docs/torrent-vpn.md`.

## Verdict

**Faisable, et le netns supprime plus de code qu'il n'en ajoute.** Les unités
`vpn-policy-routing` et `vpn-killswitch` (≈170 lignes de `ip rule` + nft)
disparaissent entièrement, ainsi que le `fwMark 0x4242`, la table de routage
`4242`, les exceptions Tailscale (`tailscaleNetworksV4/V6`) et la gymnastique
`after`/`partOf`/`wantedBy` autour du `DynamicUser` de Prowlarr.

Le fail-closed devient **structurel** au lieu d'être une règle nft à maintenir :
dans un netns dont la seule route par défaut est `wg0`, la chute du tunnel donne
`ENETUNREACH`, pas une fuite WAN.

Le coût réel n'est pas dans le réseau, il est dans les **quatre points de contact
loopback** qui cassent (dont trois sont de la config runtime non déclarative) et
dans l'**ordonnancement systemd** des quatre services déplacés.

## Pourquoi changer

L'isolation actuelle dépend de la **résolution d'UID à l'exécution**. C'est une
faiblesse structurelle, pas un détail d'implémentation : elle a déjà produit une
fuite WAN silencieuse (backup restic de Prowlarr → `stop` propagé par `partOf`,
`start` non propagé → règles `ip rule` et table nft supprimées jusqu'au reboot).
Le correctif (`wantedBy = [ "prowlarr.service" ]`, commit `cb6d146`) reste un
contournement : la classe de bug subsiste.

Un netns n'a pas cette classe de bug : **l'appartenance au namespace est fixée au
démarrage du service**, elle ne se recalcule pas et ne dépend d'aucun UID.

Bénéfices secondaires acquis au passage :

- **DNS enfin tunnelisé** (limitation connue aujourd'hui : qBittorrent/Prowlarr
  résolvent via AdGuard depuis l'IP WAN).
- Diagnostic plus simple : un seul `ip netns exec vpn …` au lieu de croiser
  `ip rule` / `ip route show table 4242` / `nft list table`.
- `networking.firewall.checkReversePath = "loose"` devient du **code mort**
  — voir l'encadré rpfilter plus bas. Attention : ce n'est **pas** un gain de
  durcissement, et le retirer ne change rien (Tailscale l'impose de toute façon ;
  vérifié en runtime : la valeur reste `loose`).

## Support upstream (vérifié)

nixpkgs épinglé `34ab9907…` (nixos-unstable 26.11),
`nixos/modules/services/networking/wireguard.nix` :

| Option | Valeur cible | Effet |
|---|---|---|
| `socketNamespace` | `null` (défaut) | socket de transport dans le namespace **hôte** → le trafic chiffré sort par la route normale, **sans marque** |
| `interfaceNamespace` | `"vpn"` | `ip link set wg0 netns vpn` (`:605-609`), puis tout le reste via `ip netns exec` (`nsWrap`, `:631-640`) |
| `table` | **retirer la ligne** | `"main"` est déjà le défaut (`:119-129`) ; c'est `allowedIPsAsRoutes = true` (défaut, `:137-144`) qui pose `default dev wg0` dans la table main **du netns** |
| `fwMark` | **retirer la ligne — mais seulement quand le kill-switch part** | tant que le kill-switch existe il droppe le transport non marqué : voir l'encadré ⛔ du lot A |

C'est le montage canonique décrit par <https://www.wireguard.com/netns/> :
socket dehors, interface dedans.

## Ce qui casse, précisément

Un netns a son **propre loopback** : tout appel en `127.0.0.1` qui traverse la
frontière tombe. Il faut une paire veth.

Plan d'adressage retenu : **`10.200.0.0/30`** — vérifié libre (aucun conflit avec
`192.168.10/21`, Tailscale `100.64/10`, wg `10.150.11.114`, libvirt
`192.168.122/24`, podman `10.88/16`).

| Bout | Interface | Adresse |
|---|---|---|
| hôte | `veth-vpn-host` | `10.200.0.1/30` |
| netns | `veth-vpn` | `10.200.0.2/30` |

### Ce qui continue de marcher sans rien toucher

- **Prowlarr → PostgreSQL** : `_servarr.nix:11` passe par la socket Unix
  `/var/run/postgresql`, objet du système de fichiers → indifférent au namespace
  réseau.
- **Tous les accès `/mnt/…`** : un netns ne change pas les montages.
- **Le secret `cross-seed-secrets.json`** reste valide **tel quel**, donc
  **aucun rekey** : cross-seed et freeleech-farmer appellent qBittorrent en
  `127.0.0.1:8090` et les Torznab Prowlarr en `127.0.0.1:9696`, or les trois
  services sont dans le **même** netns.
- **Les bind des WebUI** : Sonarr `:8989`, Radarr `:7878`, qBittorrent `:8090`,
  Prowlarr `:9696` écoutent sur `*` → joignables par le veth sans changer leur
  configuration d'écoute.
- **Le port 53 vers l'hôte** : `adguard.nix:26-28` pose
  `allowedTCPPorts`/`allowedUDPPorts = [ 53 ]`, qui sont **globaux (toutes
  interfaces)** → rien à ouvrir pour le veth.
- **SSH / Tailscale / Traefik / AdGuard / *arr** : restent dans le namespace
  hôte, intouchés. Aucun risque de verrouillage à distance.

### Déclaratif, trivial

| Quoi | Où | Changement |
|---|---|---|
| Backend Traefik qBittorrent | `traefik.services.qbittorrent.host` | `localhost` → `10.200.0.2` |
| Backend Traefik Prowlarr | `traefik.services.prowlarr.host` | `localhost` → `10.200.0.2` |
| Pare-feu veth | `networking.firewall.interfaces.veth-vpn-host` | ouvrir **8989/7878** (Sonarr/Radarr) — **et rien d'autre** : 53 est déjà global |

L'option `host` existe déjà dans `traefik/options.nix:16-19`, et `glance.nix:44`
dérive sa `check-url` du même champ → le dashboard suit automatiquement.

### Runtime, dans les UI (non déclaratif)

- **Sonarr / Radarr** → client de téléchargement qBittorrent :
  `127.0.0.1:8090` → `10.200.0.2:8090`.
- **Prowlarr, synchro d'apps — bidirectionnelle** :
  - ses entrées « Applications » visent Sonarr/Radarr en `127.0.0.1` →
    `10.200.0.1:8989` / `10.200.0.1:7878` ;
  - l'URL « Prowlarr Server » qu'il s'annonce → `10.200.0.2:9696`.
- **qBittorrent** : si `WebUI\AuthSubnetWhitelist` ou le bypass
  d'authentification localhost est activé, Traefik arrive maintenant depuis
  `10.200.0.1` et non `127.0.0.1` → re-whitelister.

### Runtime, le plus incertain

**Bindery** tourne en `--network=host` et joint Prowlarr (9696) et qBittorrent
(8090) en loopback. `bindery.nix:41` porte déjà
`BINDERY_DOWNLOAD_ALLOW_LOOPBACK = "1"` parce que les liens de téléchargement
fournis par Prowlarr pointent sur `127.0.0.1` et étaient rejetés par son
garde-fou SSRF. Ces liens deviendront `10.200.0.2` : **plus du loopback, mais
toujours une plage privée (RFC 1918)**. Selon la façon dont Bindery filtre,
l'autorisation actuelle peut ne plus suffire. **Seul point non prédictible sans
test.**

## Les pièges non évidents

### 1. DNS : `NetworkNamespacePath` ne bind-monte pas `/etc/netns`

`ip netns exec` bind-monte `/etc/netns/<ns>/*` par-dessus `/etc/*`.
**`NetworkNamespacePath=` de systemd ne le fait pas** : il ne change que le
namespace réseau. Les services placés dans le netns liraient donc le
`/etc/resolv.conf` de l'hôte → MagicDNS Tailscale `100.100.100.100`,
**injoignable depuis le netns**. Il faut un `BindReadOnlyPaths` par service.

> `NetworkNamespacePath=` implique `PrivateMounts=` — sans effet utile ici :
> `PrivateMounts` ne bind-monte **pas** `/etc/netns/*`. Ce n'est donc pas une
> atténuation du piège, juste un fait à connaître pour les tests.

**Piège dans le piège** (lu dans `generatePeerUnit` de nixpkgs, `:450`,
`:502-535`) : le `wg set … endpoint nl3.vpn.airdns.org:1637` est lui aussi
exécuté via `ip netns exec vpn`. **La résolution du nom d'hôte AirVPN se fait
donc à l'intérieur du netns**, qui n'a pas encore de route par défaut au premier
démarrage → amorçage impossible si le netns n'a aucun résolveur atteignable.

Résolution retenue, en deux fichiers distincts :

| Fichier | Contenu | Consommateur |
|---|---|---|
| `/etc/netns/vpn/resolv.conf` via `environment.etc."netns/vpn/resolv.conf"` | `nameserver 10.200.0.1` (AdGuard via veth) | `ip netns exec` → résolution de l'endpoint AirVPN par `wg`, **avant** que le tunnel soit monté |
| store path + `BindReadOnlyPaths=…:/etc/resolv.conf` | `nameserver 10.128.0.1` (résolveur AirVPN) | qBittorrent, Prowlarr, cross-seed, freeleech-farmer |

Passer par `environment.etc` (et non par un `echo` dans `netns-vpn.service`) rend
l'ordre **non-problématique** : le fichier est posé à l'activation, donc avant
n'importe quelle unité.

Nuance d'implémentation : `environment.etc` produit par défaut un **symlink**
(`/etc/netns/vpn/resolv.conf` → `/etc/static/…` → store). Ça fonctionne, parce
que `mount(2)` résout les liens symboliques dans ses arguments : le
`mount --bind` fait par `ip netns exec` bind en réalité le fichier du store, dans
le namespace de montage privé qu'il crée (rien n'est visible côté hôte). Si
l'indirection dérange, donner à l'entrée un `mode = "0444"` explicite matérialise
un vrai fichier dans `/etc` au lieu d'un symlink.

**Le mode de défaillance de ce piège est un timeout, pas une fuite.** Un service
dont le `BindReadOnlyPaths` n'aurait pas pris lirait le `resolv.conf` de l'hôte et
interrogerait `100.100.100.100` — adresse pour laquelle le netns n'a d'autre route
que le défaut via `wg0`. La requête part donc **dans le tunnel** et expire :
`EAI_AGAIN`, exactement le symptôme déjà documenté dans `docs/torrent-vpn.md`
(« Host not found (non-authoritative) » côté trackers). C'est important pour la
recette : le test associé (§ Tests d'acceptation n°3) est une vérification de
**correction**, pas d'étanchéité.

> ⚠️ `10.128.0.1` est la valeur documentée par AirVPN (« DNS server address is
> the same as gateway »), mais c'est **la** valeur à confirmer en runtime depuis
> le netns : une erreur ici donne un service qui démarre et ne résout rien.
> Repli zéro-dépendance si l'amorçage pose problème : résoudre l'endpoint en IP
> littérale côté hôte — au prix de la perte du failover DNS du pool `airdns`.

### 2. Le namespace doit être persistant, idempotent et créé hors sandbox

`ip netns add vpn` crée un bind-mount dans `/run/netns/vpn`. L'unité qui le crée
doit tourner dans le **namespace de montage de l'hôte** : **pas** de
`ProtectSystem`, `PrivateTmp` ni `PrivateMounts`, sinon le montage reste
invisible du reste du système.

`ip netns add` **échoue si le netns existe déjà** (cas d'un `switch` qui rejoue
l'unité sans reboot) : il faut un garde **test-et-saute**, pour le netns comme
pour le veth.

```bash
ip netns list | grep -qx vpn || ip netns add vpn
ip link show veth-vpn-host >/dev/null 2>&1 || ip link add veth-vpn-host type veth peer name veth-vpn netns vpn
```

> ⛔ **Ne jamais faire `ip netns del vpn` avant l'`add`**, ni au `stop`, ni au
> `restart`. Détruire le netns **orpheline** tous les services déjà attachés par
> `NetworkNamespacePath` : ils conservent un namespace fantôme, sans interface ni
> route, et **sans échouer bruyamment** — un qBittorrent vivant et muet, soit
> exactement le profil de la fuite du backup Prowlarr qu'on cherche à éliminer.
> Cycle de vie visé : **créé une fois, `wg0` monte et descend dedans**. Donc le
> `ip netns add` ne va **pas** dans le `preSetup` de WireGuard, mais dans une
> unité dédiée `netns-vpn.service` (`RemainAfterExit = true`, pas de `preStop`
> destructeur).

Ne pas oublier de **monter `lo` dans le netns** (il est `DOWN` par défaut dans un
netns neuf) : sinon la WebUI qBittorrent et les appels cross-seed → qBittorrent
tombent.

### 3. Ordonnancement : chaque service déplacé dépend du netns

C'est le point le plus facile à sous-estimer. Un service dont le
`NetworkNamespacePath` pointe sur un `/run/netns/vpn` inexistant **échoue au
fork**. Il faut donc, sur les quatre services :

- `Requires=` + `After=netns-vpn.service` (existence du namespace) ;
- `After=wireguard-wg0.service` (le namespace peut exister sans tunnel).

Et il faut **remplacer**, pas seulement supprimer, les dépendances existantes :
`qbittorrent.nix:36-45` (`after`/`wants` sur `wireguard-wg0`,
`vpn-policy-routing`, `vpn-killswitch`) et `freeleech-farmer.nix:22-27`
(`after` sur `vpn-killswitch`).

Implémentation recommandée : **un drop-in partagé** (fonction ou attrset dans
`vpn.nix`) appliqué aux quatre unités, portant `Requires`/`After`,
`NetworkNamespacePath` et le `BindReadOnlyPaths` du resolv.conf — plutôt que de
dupliquer quatre fois la même chose dans trois modules différents.

### 4. Le veth est la seule surface de fuite restante, et l'hôte forwarde

`services.tailscale.useRoutingFeatures = "both"` est défini à
`modules/hosts/hyper/configuration.nix:63` (et non dans
`features/networking/tailscale.nix`, qui ne porte qu'`enable` + `authKeyFile`).
Conséquence côté nixpkgs (`services/networking/tailscale.nix:252-254`) :
`net.ipv4.conf.all.forwarding = true`. La stack conteneurs (podman) le pose aussi
au runtime, mais **Tailscale en est la cause déclarative** — c'est la seule
visible dans la config NixOS.

En pratique le netns n'enverra jamais rien vers le WAN par le veth : sa seule
route par défaut est `wg0`, et la route connectée du `/30` ne couvre que `.1`.
Mais ça mérite une ceinture :

- une petite table nft **dans le netns** limitant la sortie `veth-vpn` au `/30` ;
- éventuellement un drop de forwarding depuis `veth-vpn-host` côté hôte — avec
  la même prudence que celle déjà notée dans `docs/torrent-vpn.md` : **ne pas
  activer `networking.nftables.enable` globalement** (casserait libvirt/podman),
  rester sur une table dédiée.

**IPv6** : AirVPN ne fournit ici qu'un `/32` IPv4. Dans le netns, absence de
route IPv6 = fail-closed par construction ; un
`net.ipv6.conf.all.disable_ipv6 = 1` appliqué **dans le netns** rend l'intention
explicite.

### 5. `checkReversePath` est du rpfilter iptables, par namespace — pas un sysctl

Piège de raisonnement à éviter, et **non-objectif** du plan.

L'option est implémentée dans `firewall-iptables.nix:126-143` : une chaîne
`nixos-fw-rpfilter` dans la table **mangle**, appelée depuis `PREROUTING`, avec
le match `-m rpfilter --validmark [--loose]`. Ce sont des **règles iptables**, et
les règles iptables sont **par namespace réseau**. Le script du pare-feu NixOS ne
tourne que dans le namespace init.

Donc **aucune règle rpfilter n'existera dans le netns `vpn`** :

- il n'y a **rien à desserrer** dans le netns, l'ingress P2P de `wg0` fonctionnera
  sans action. Les sysctls `net.ipv4.conf.*.rp_filter` observables sur hyper sont
  **orthogonaux** : NixOS ne s'en sert pas pour cette option ;
- `vpn.nix:132` devient du code mort **à retirer par propreté**, mais le retirer
  ne change **aucun comportement** : `services/networking/tailscale.nix:260-262`
  pose `networking.firewall.checkReversePath = "loose"` en **définition simple
  (pas `mkDefault`)** dès que `useRoutingFeatures` vaut `client` ou `both`. La
  valeur restera `"loose"` sur l'hôte ;
- « repasser l'hôte en strict » est donc **irréalisable** sans `lib.mkForce` ou
  sans renoncer au rôle de subnet router — et n'apporterait rien au netns. Ce
  n'est pas un lot du plan.

> À verser dans les *Known quirks* : si les deux définitions simultanées
> (`vpn.nix:132` + Tailscale) n'explosent pas à l'évaluation, c'est uniquement
> parce que le type de l'option est `either bool (enum ["strict" "loose"])` et
> que la fusion accepte des valeurs **égales**. Écrire `true` dans `vpn.nix` pour
> « durcir » fait échouer l'éval en conflit de définitions, avec un message qui
> ne pointe pas vers Tailscale.

### 6. Un service qui écoute sur le tunnel doit redémarrer avec lui

Le piège le plus sournois de la migration, parce qu'il ne produit **aucune unité
en échec**.

qBittorrent énumère les interfaces au démarrage et lie son listener **par
adresse** ; il ne s'y rattache jamais ensuite. Si `wg0` est recréé sous lui — ce
que fait **toute activation qui redémarre `wireguard-wg0`** —, il continue
d'écouter sur `lo` et la veth seulement. Conséquence : le port forwardé devient
injoignable de l'extérieur et **le ratio tombe à zéro en silence**.

Constaté en runtime : `ss -tlnp` dans le netns ne montrait que
`127.0.0.1%lo:47594` et `10.200.0.2%veth-vpn:47594`, **sans** ligne
`10.150.11.114%wg0:47594`, et `ifconfig.co/port/47594` renvoyait
`reachable: false`. Un simple `systemctl restart qbittorrent` rétablit les trois
listeners et `reachable: true`.

Correctif déclaratif sur `qbittorrent` en mode netns :

```nix
partOf  = [ "wireguard-wg0.service" ];  # propage le stop
wantedBy = [ "wireguard-wg0.service" ]; # propage le start
```

**Les deux sont nécessaires** : `partOf` seul ne remonte pas l'unité — c'est
exactement l'asymétrie qui avait fait disparaître le kill-switch après le backup
Prowlarr (`AGENTS.md`, commit `cb6d146`). Vérifié : `restart wireguard-wg0` →
le PID de qBittorrent change, le listener `wg0` revient, port `reachable: true`.

Scopé à qBittorrent volontairement : c'est le seul des quatre services à **lier
un listener entrant** à l'adresse du tunnel. Prowlarr, cross-seed et
freeleech-farmer n'émettent que des connexions sortantes et n'ont rien à
réattacher — les redémarrer serait du bruit (Prowlarr est un `DynamicUser` avec
des connexions Postgres).

### 7. Le cycle d'ordonnancement systemd qui supprime le tunnel

**Le bug que seul un reboot révèle**, et il ne produit ni unité en échec ni
message d'erreur sur le service concerné.

`wireguard-wg0` portait de longue date `after = [ "adguardhome.service" ]` (pour
que le DNS soit prêt avant la résolution de l'endpoint). Or AdGuard est `after
network.target`, et le module nixpkgs met `wireguard-wg0` **`before`
`network.target`**. Cycle :

```
wireguard-wg0 → after adguardhome → after network.target → before wireguard-wg0
```

systemd le casse en **supprimant le job de démarrage du tunnel** :

```
network.target: Found ordering cycle: wireguard-wg0.service/start after
  adguardhome.service/start after network.target/start - after wireguard-wg0.service
network.target: Job wireguard-wg0.service/start deleted to break ordering cycle
```

Résultat au boot : le netns et la veth sont créés, mais `wg0` n'existe pas, le
netns n'a aucune route par défaut, `systemctl is-system-running` dit `degraded`
et `systemctl --failed` est **vide**. Le tunnel est simplement absent.

**Le cycle est antérieur à la migration** (présent au boot précédent). Il était
masqué parce que `qbittorrent.nix`, en mode uid, portait
`wants = [ "wireguard-wg0.service" ]` : rien ne l'ordonnait, mais ça **remontait
le tunnel après coup**. Le drop-in netns n'avait volontairement que `after`, pour
que les services démarrent et échouent fermés — ce qui a retiré le masque.

Correctif en deux temps :

1. **Supprimer l'ordonnancement sur AdGuard**, cause racine. Il n'a jamais été
   nécessaire sur *cette* unité : créer l'interface ne résout aucun nom
   (`ip link add`, `ip addr add`, `wg set private-key`, `ip link set up`). Seule
   l'unité *peer* résout l'endpoint, et elle tourne avec
   `WG_ENDPOINT_RESOLUTION_RETRIES=infinity`, donc `wg` attend en interne que le
   DNS réponde au lieu d'échouer.
2. **Remettre le filet** : `wants = [ "wireguard-wg0.service" ]` dans le drop-in
   netns (jamais `requires`). Une dépendance faible remonte le tunnel si rien
   d'autre ne l'a fait, tout en laissant le service démarrer tunnel baissé — le
   fail-closed est préservé.

**Leçon de méthode** : `systemctl --failed` vide ne veut pas dire « boot sain ».
Vérifier `systemctl is-system-running` **et**
`journalctl -b | grep "ordering cycle"`.

### 8. qBittorrent envoyait du trafic pair sur la veth (corrigé)

Découvert en instrumentant la table `vpn_guard` du lot D. qBittorrent lie un
listener à **chaque** interface du namespace, veth comprise — `ss -tlnp` montre
`10.200.0.2%veth-vpn:47594`, la notation `%iface` signalant un
`SO_BINDTODEVICE` — et émet depuis cette socket du UDP pair/DHT vers des
adresses publiques. Mesuré : **~460 paquets dans les 40 s suivant un restart du
tunnel**.

**Ce n'est pas une fuite**, et il faut le vérifier plutôt que le supposer : le
`/30` n'est pas masqueradé (le `MASQUERADE` de netavark est scopé à
`10.88.0.0/16`, `iptables -t nat -S POSTROUTING` le confirme) et un `tcpdump`
sur le lien WAN filtré sur `src net 10.200.0.0/30` capture **zéro paquet**. Ces
paquets mouraient à l'hôte. La règle `vpn_guard` les arrête une étape plus tôt.

**Corrigé le 2026-09-28** en fixant l'interface réseau de qBittorrent sur `wg0`
(Options → Avancé). C'était déconseillé avant la migration parce que le bind
cassait la résolution MagicDNS ; l'objection est levée puisque le namespace
résout par le tunnel.

Mesuré après coup : `ss -tlnp` dans le namespace ne montre plus que
`10.150.11.114%wg0:47594` (TCP et UDP), le listener veth a disparu, et le
compteur de `vpn_guard` est **figé** — 0 paquet sur 90 s, et 0 après un restart
de `wireguard-wg0`, qui était justement la condition produisant le pic. Le bind
ne touche pas la WebUI (toujours sur `*`), donc Traefik la joint sans changement,
et le port forward reste `reachable: true`. `vpn_guard` redevient purement
défensive : si son compteur repart, ce réglage est le premier à vérifier.

> Méthode : le `reset counters` de nft n'a pas remis le compteur à zéro ici — la
> mesure fiable est un **delta** entre deux lectures espacées, pas une valeur
> absolue.

Deux outils à connaître pour ce genre d'enquête : le `log` nft d'un namespace
**non-init est jeté en silence** tant que `net.netfilter.nf_log_all_netns=1`
n'est pas positionné sur l'hôte ; et le compteur de la règle ne bouge que si l'on
reproduit la bonne condition (ici, un restart du tunnel, pas un simple
rechargement de la table).

## Plan d'action

### Lot A — l'ossature, sans déplacer de service

**Statut : déployé en `nixos-rebuild test` et validé en runtime** (2026-09-28).
⚠️ **Non persisté** : la génération au prochain boot est encore l'ancienne (mode
`uid`). Un reboot annule tout ; il faut un `switch` pour graver.

1. `vpn.airvpn.isolation` à valeurs `"uid"` (actuel) / `"netns"` pour garder les
   deux implémentations côte à côte → retour arrière en un seul changement.
   Options d'adressage sous `vpn.airvpn.netns` (`name`, `hostAddress`,
   `namespaceAddress`, `prefixLength`) plutôt que des constantes en dur.
2. `netns-vpn.service` : `oneshot` + `RemainAfterExit`, **aucune option de
   sandboxing**, **gardes idempotents** (§ piège 2), **aucun `preStop`
   destructeur**. Il fait `ip netns add vpn`, **`ip link set lo up` dans le
   netns**, crée la paire veth, adresse les deux bouts, désactive l'IPv6 dans le
   netns.
3. Basculer `wg0` : `interfaceNamespace = "vpn"`, **retirer `table = "4242"`
   mais GARDER `fwMark`** (voir l'encadré fwMark ci-dessous), `requires` +
   `after` `netns-vpn.service` (`Requires` et pas seulement `After` : un netns
   qui échoue doit faire échouer le tunnel bruyamment).
4. `environment.etc."netns/vpn/resolv.conf"` avec `mode = "0444"` (→ `10.200.0.1`).
5. `networking.firewall.interfaces.wg0` gaté sur le mode `"uid"` (code mort en
   netns : `wg0` n'est plus dans le namespace hôte).
6. Assertion sur la longueur du nom d'interface dérivé (`veth-<ns>-host` ≤ 15).

> ⚠️ **Correction de séquencement trouvée à l'implémentation.** L'assertion
> d'exclusivité (`routedUsers`/`lanNetworks`/`tailscaleNetworks*` interdits en
> mode `netns`) était initialement placée dans ce lot : **c'est une erreur, elle
> appartient au lot B.** Au lot A les services sont encore dans le namespace
> hôte ; retirer `routedUsers` et le kill-switch à ce moment-là les laisserait
> sans aucune règle, donc leur trafic repartirait par la table `main`
> **directement sur le WAN** — une fuite, pas un fail-closed. Les deux unités
> UID (`vpn-policy-routing`, `vpn-killswitch`) restent donc actives **dans les
> deux modes** jusqu'au lot B.

**État transitoire attendu après déploiement du lot A** : `wg0` étant parti dans
le netns, la table 4242 est vide et le kill-switch droppe le trafic des trois
utilisateurs routés. **La stack de téléchargement est donc hors ligne mais
étanche** — c'est voulu, et c'est la bonne direction de défaillance. Le lot B la
remet en service.

> ⛔ **`fwMark` doit rester tant que le kill-switch existe — y compris en mode
> netns.** C'est l'erreur qui a coûté le premier déploiement du lot A. Le plan
> disait « retirer `table` **et** `fwMark` » : seul `table` doit partir.
>
> Raison : seule l'**interface** part dans le netns, la **socket de transport
> reste dans le namespace hôte** (c'est tout l'intérêt du montage). Les paquets
> chiffrés traversent donc toujours le hook `output` de l'hôte, où le kill-switch
> vit. Or ces paquets sont générés par le noyau : ils n'ont **aucun `skuid`** à
> matcher (la règle `meta skuid != {…} accept` ne s'évalue donc pas à vrai, elle
> ne matche pas du tout et l'évaluation continue), et `oifname "wg0"` ne peut
> plus matcher non plus puisque `wg0` a quitté ce namespace. Sans la marque ils
> tombent sur `counter drop` et **le handshake ne quitte jamais la machine**.
>
> Symptôme trompeur : `wg show` affiche des octets « sent » qui augmentent et
> `0 B received`, parce que ce compteur mesure ce que WireGuard a remis à la pile,
> pas ce qui est réellement parti. **Le diagnostic décisif est un `tcpdump` sur le
> lien WAN** : `sudo tcpdump -nni management udp port 1637` → *0 paquet capturé*
> alors que `wg` prétend émettre. C'est le même piège que celui déjà documenté
> dans `docs/torrent-vpn.md` ; il se represente à l'identique en mode netns.
>
> Le `fwMark` part au lot B, **en même temps** que le kill-switch.

> ℹ️ **Accept transitoire pour l'adresse du netns.** Même mécanisme, autre
> victime : les paquets que le noyau de l'hôte génère *vers* le netns (réponses
> ICMP, RST…) n'ont pas de `skuid` non plus et tombaient sur le `drop`. Résultat,
> `ping 10.200.0.1` depuis le netns échouait alors que la veth était parfaitement
> fonctionnelle (`ping` dans l'autre sens marchait, parce qu'émis par un
> processus root donc accepté par la règle `skuid`). Une règle
> `ip daddr <namespaceAddress> accept` a été ajoutée au kill-switch pour la durée
> de la transition : inoffensive (le /30 ne mène qu'au netns, qui ne route rien)
> et elle évite un diagnostic qui ment. Disparaît avec le kill-switch au lot B.

**Vérifié à l'évaluation** (`nix flake check --all-systems --no-build` : OK) :

- `wg0` → `interfaceNamespace = "vpn"`, `socketNamespace = null`,
  `table = "main"`, `fwMark = null` ;
- `netns-vpn.service` ne contient **que** `Type`, `RemainAfterExit` et
  `Environment` — aucune option de sandboxing, aucun `ExecStop` ;
- `wireguard-wg0` : `requires = ["netns-vpn.service"]`,
  `after = ["network-pre.target" "adguardhome.service" "netns-vpn.service"]` ;
- `/etc/netns/vpn/resolv.conf` : vrai fichier `0444`, `nameserver 10.200.0.1` ;
- `networking.firewall.interfaces` ne contient plus `wg0` (`br-iot`, `podman0`
  seulement) ;
- **confirmation empirique du piège 1** — l'unité peer générée est bien
  `ip netns exec "vpn" "wg" set wg0 … endpoint "nl3.vpn.airdns.org:1637"`, et la
  route est posée par
  `ip netns exec "vpn" "ip" route replace "0.0.0.0/0" dev "wg0" table "main"`.
  La résolution de l'endpoint a donc réellement lieu dans le netns, ce qui rend
  le `resolv.conf` d'amorçage indispensable et non précautionnel.

**Résultats runtime du 2026-09-28** (après correction du `fwMark`) :

| Vérification | Résultat |
|---|---|
| `netns-vpn.service` | `active` / `Result=success` ; `run-netns-vpn.mount` apparaît côté hôte → le bind-mount est bien visible hors sandbox |
| `wg0` dans le namespace hôte | absent (`Device "wg0" does not exist`) |
| handshake | OK, trafic **bidirectionnel** (6,30 KiB reçus / 4,41 KiB envoyés) |
| routes du netns | `default dev wg0` + `10.200.0.0/30` connecté — **aucune** route par défaut via la veth |
| `lo` dans le netns | `UP`, `127.0.0.1/8` |
| IP de sortie | netns → `213.152.161.101` (AirVPN) ; hôte → `90.120.124.121` (WAN, inchangée) |
| DNS d'amorçage | `getent hosts nl3.vpn.airdns.org` depuis le netns → OK via `10.200.0.1` ; endpoint résolu par `wg` |
| **étanchéité** | `sudo -u qbittorrent curl` et `sudo -u cross-seed curl` → **vide** (pas l'IP WAN) ; LAN toujours joignable (WebUI 200) |
| veth | bidirectionnel après l'accept transitoire (0 % perte dans les deux sens) |
| IPv6 dans le netns | `disable_ipv6 = 1` |
| idempotence | `systemctl restart netns-vpn` → succès, **netns conservé (`id: 1`)**, et systemd propage le restart à `wireguard-wg0` qui revient seul (tunnel remonté) |
| couche web | qBittorrent 200, Prowlarr 302, Traefik 302 via le LAN |
| état système | `running`, **0 unité en échec** |

> Note pour le lot C : **Traefik n'écoute que sur `192.168.10.100:443/80`**, pas
> sur le loopback — un test en `https://127.0.0.1` renvoie `000` et ne prouve
> rien. Tester via l'IP LAN avec l'en-tête `Host` attendu.

> Attendu et **non** un défaut : `curl` depuis le netns vers Sonarr
> (`10.200.0.1:8989`) échoue encore. Ce port n'est ouvert sur aucune interface
> (seul le 22 est global, et le 53 via AdGuard) — c'est précisément l'ouverture
> pare-feu du **lot C**.

**Commandes de vérification de fin de lot** :

```bash
ip netns exec vpn wg show wg0            # handshake + transfert
ip netns exec vpn ip route               # default dev wg0 + 10.200.0.0/30
ip netns exec vpn ip link show lo        # UP (sinon WebUI + cross-seed KO)
ip netns exec vpn curl -s https://api.ipify.org   # IP AirVPN
curl -s https://api.ipify.org            # IP WAN (hôte inchangé)
sudo systemctl restart netns-vpn         # idempotence : doit réussir
```

### Lot B — déplacer les services

**Statut : déployé en `nixos-rebuild test` et validé en runtime** (2026-09-28).
⚠️ **Non persisté** (prochain boot = mode `uid`).

> ⛔ **Piège trouvé à l'implémentation : un `default` n'est PAS une définition.**
> `vpn.airvpn.netns.services` avait pour défaut `[ "qbittorrent" "prowlarr" ]`, et
> les modules cross-seed/freeleech-farmer y contribuaient leur propre nom. Les
> contributions ont **remplacé** le défaut au lieu de s'y ajouter : la liste
> évaluait à `[ "freeleech-farmer" "cross-seed" ]` seulement. qBittorrent et
> Prowlarr seraient restés dans le namespace hôte **alors que le kill-switch
> venait d'être retiré** → fuite WAN directe. Attrapé par `nix eval` avant
> déploiement. Correctif : défaut à `[ ]`, et **chaque** module contribue son nom
> (y compris qbittorrent.nix et prowlarr.nix). Règle générale : dès qu'une option
> de liste est alimentée par plusieurs modules, son défaut doit être vide.

> ℹ️ **Rollback préservé.** Le plan disait de *supprimer* `vpn-policy-routing`,
> `vpn-killswitch` et `routedUsers`. Ils sont **gatés sur `isolation = "uid"`**
> et non supprimés : les effacer détruirait le retour arrière en une ligne, qui
> est la raison d'être de l'option. Suppression définitive = nettoyage ultérieur,
> une fois le mode netns éprouvé.

**Vérifié en runtime** :

| Vérification | Résultat |
|---|---|
| appartenance au namespace | qBittorrent et Prowlarr dans `net:[4026532740]`, PID 1 dans `net:[4026531833]` — **preuve directe**, pas une inférence |
| machinerie UID | unités `vpn-policy-routing`/`vpn-killswitch` absentes, **aucune** `ip rule` résiduelle, table nft `vpn_killswitch` supprimée |
| `PrivateUsers = true` (le suspect n°1) | **aucun problème** : qBittorrent démarre tel quel, le plan B `mkForce false` n'a pas servi |
| **DNS applicatif tunnelisé** | `nsenter -m` sur les 3 services longue-durée → `nameserver 10.128.0.1` ; `dig @10.128.0.1` répond (25 ms via le tunnel). **La limitation « DNS non tunnelisé » est levée.** |
| IP de sortie | `nsenter -n` sur qBittorrent → AirVPN ; hôte inchangé sur son IP WAN |
| WebUI par la veth | qBittorrent 200, Prowlarr 302 ; via Traefik 302 (Authelia) |
| **port forward** | `reachable: true` sur 47594 — le ratio n'est pas cassé |
| cross-seed → qBittorrent | 200 sur `127.0.0.1:8090` (même namespace, inchangé) |
| veth → Sonarr/Radarr | 302 des deux côtés ; **fermés depuis le LAN** (règles bien scopées `-i veth-vpn-host`, vérifié en `iptables -S` **et** depuis une autre machine) |
| **fail-closed** | `stop wireguard-wg0` → le netns n'a plus que la route connectée `/30`, **aucune route par défaut** ; qBittorrent ne sort pas et **reste vivant** ; sortie rétablie au `start` |
| état système | `running`, **0 unité en échec** |

> ⚠️ **Deux tests « évidents » qui mentent**, tombés dans les deux :
> un `curl` depuis hyper vers sa propre IP LAN passe par `lo` (accepté par le
> pare-feu) et ne prouve **rien** sur l'ouverture d'un port ; et Traefik n'écoute
> que sur `192.168.10.100`, donc un test en `127.0.0.1:443` renvoie `000` sans
> que rien ne soit cassé. Tester depuis une **autre machine**, ou lire
> `iptables -S`.


> ⚠️ **Les trois points ci-dessous doivent atterrir dans le *même* déploiement.**
> Le lot A a laissé les services dans le namespace hôte, protégés par le
> kill-switch UID ; le lot B les déplace *et* retire ce kill-switch. Séparer les
> deux ouvrirait la fenêtre de fuite décrite dans l'encadré du lot A.

1. Appliquer le **drop-in partagé** (§ piège 3) à `qbittorrent`, `prowlarr`,
   `cross-seed`, `freeleech-farmer` : `NetworkNamespacePath = "/run/netns/vpn"`,
   `Requires`/`After = netns-vpn.service`, `After = wireguard-wg0.service`,
   `BindReadOnlyPaths` du resolv.conf applicatif. **Remplacer** au passage les
   `after`/`wants` existants (`qbittorrent.nix:36-45`,
   `freeleech-farmer.nix:22-27`) — ne pas seulement les retirer.
2. Supprimer `vpn-policy-routing`, `vpn-killswitch`, les options
   `lanNetworks`/`tailscaleNetworksV4`/`tailscaleNetworksV6`/`routedUsers`
   devenues inutiles, et `vpn.nix:132` (`checkReversePath`, § piège 5 — sans en
   attendre d'effet). Le bloc `networking.firewall.interfaces.wg0` est déjà gaté
   sur le mode `"uid"` depuis le lot A ; il peut disparaître complètement ici.
3. Ajouter l'**assertion d'exclusivité** déplacée depuis le lot A : `routedUsers`,
   `lanNetworks`, `tailscaleNetworksV4/V6` interdits en mode `"netns"`. Elle
   n'est correcte qu'une fois les points 1 et 2 faits — c'est précisément ce que
   l'assertion verrouille pour l'avenir.

> ⚠️ **Point à valider en premier, le plus susceptible d'échouer** : le module
> nixpkgs de qBittorrent pose `PrivateUsers = true` (`qbittorrent.nix:198`) et
> `ProtectSystem = "full"` (`:202`) ; Prowlarr est en `DynamicUser`.
> `NetworkNamespacePath=` neutralise `PrivateNetwork=` (`:194`, déjà `false`),
> donc pas de conflit de ce côté. Mais si le `setns(CLONE_NEWNET)` est refusé
> (`EPERM` lié au user namespace), **plan B immédiat** :
> `systemd.services.qbittorrent.serviceConfig.PrivateUsers = lib.mkForce false;`

**Réglages de durcissement écartés (ne pas perdre de temps dessus)** —
`RestrictNamespaces = true` (`qbittorrent.nix:214`) et `RestrictAddressFamilies`
(`:209-213`) ne peuvent pas interférer : `RestrictNamespaces` est un filtre
seccomp sur les `unshare`/`setns`/`clone` **du processus de service**, alors que le
namespace est installé par systemd dans le child après le fork et **avant**
l'application du seccomp ; et `RestrictAddressFamilies` autorise déjà `AF_INET`,
`AF_INET6` et `AF_NETLINK`, soit tout le nécessaire. `PrivateUsers` reste le seul
suspect parce que son risque est d'une autre nature : systemd doit y faire un
`setns` vers un namespace réseau existant **tout en créant un user namespace**, et
c'est cette interaction d'ordre et de capacités qui est fragile.

### Lot C — recâbler les points de contact

1. Déclaratif : les deux `traefik.services.*.host`, l'ouverture pare-feu
   **8989/7878 seulement** sur le veth.
2. Runtime : Sonarr/Radarr (client qBittorrent), Prowlarr (synchro d'apps dans
   les **deux** sens), qBittorrent (`AuthSubnetWhitelist`).
3. **Bindery — capturer avant d'adopter** : lancer un import et observer
   `journalctl -u podman-bindery -f` + `ss -tnp` pendant l'opération, pour voir
   si le garde-fou SSRF accepte `10.200.0.2` ou s'il faut élargir
   `BINDERY_DOWNLOAD_ALLOW_LOOPBACK`.

### Lot D — durcissement et documentation ✅

1. Table nft dans le netns (restriction du veth au `/30`), et éventuellement le
   drop de forwarding depuis `veth-vpn-host` côté hôte.
2. Ajouter `10.200.0.0/30` à l'`ignoreIP` de fail2ban (précaution ; jail `sshd`
   seule aujourd'hui).
3. Réécrire `docs/torrent-vpn.md` : toute la section diagnostics devient
   `ip netns exec vpn …`, et **`wg0` n'apparaîtra plus dans un `ip a` sur
   l'hôte**. Mettre à jour les *Known quirks* d'`AGENTS.md` : `fwMark`,
   exceptions Tailscale, `DynamicUser` Prowlarr (entrées devenues obsolètes) et
   ajout du quirk `checkReversePath` (§ piège 5).

> **Non-objectif explicite** : repasser `checkReversePath` en strict. Voir
> § piège 5 — irréalisable sans toucher au rôle de subnet router, et sans effet
> sur le netns.

### Lot E — supprimer la machinerie UID ✅

**Prérequis : levé.** Le mode netns a survécu à un boot à froid complet le
2026-09-28 (tunnel, port forward, listener `wg0`, isolation, Bindery — voir le
journal d'audit). C'est ce reboot qui a mis au jour le cycle d'ordonnancement du
§ piège 7 ; sans lui, ce nettoyage aurait retiré le rollback juste avant de
découvrir un tunnel mort au boot.

À faire **en un seul commit** avec la partie documentaire du lot D : laisser
`AGENTS.md` décrire une machinerie supprimée est pire que ne rien faire.

#### Ce qui disparaît

`modules/features/downloads/vpn.nix` — 649 lignes aujourd'hui, ~370 après :

| Quoi | Où | Volume |
|---|---|---|
| unité `vpn-policy-routing` | `:481-579` | 99 l. |
| unité `vpn-killswitch` | `:582-644` | 63 l. |
| options `routedUsers`, `lanNetworks`, `tailscaleNetworksV4/V6` | `:222-262` | 41 l. |
| option `isolation` + sa description | `:70-92` | 23 l. |
| helpers `uidOnlyOptions` / `customisedUidOptions` | `:25-34` | 10 l. |
| assertion d'exclusivité | autour de `:406` | ~25 l. |
| `table = "4242"` + `fwMark` de `wg0` | dans le `optionalAttrs (!useNetns)` | 10 l. |
| bloc `networking.firewall.interfaces.wg0` | dans le `mkMerge` de `:322` | 7 l. |
| `networking.firewall.checkReversePath` | `:347` | 1 l. |

Modules consommateurs :

- `qbittorrent.nix` : le bloc `lib.optionalAttrs (isolation == "uid")` avec les
  `after`/`wants` sur les deux unités UID ; les deux autres conditions
  (`traefik.services.qbittorrent.host` et le bloc netns) deviennent
  inconditionnelles.
- `freeleech-farmer.nix` : le `lib.optional (isolation == "uid")
  "vpn-killswitch.service"`.
- `prowlarr.nix` : la condition se réduit à `config.vpn.airvpn.enable`.
- `cross-seed.nix` : seulement un commentaire à corriger.
- **`modules/hosts/hyper/configuration.nix:86`** : retirer `isolation = "netns"`
  **dans le même changement**, sinon l'évaluation échoue sur une option inconnue.
  C'est le seul couplage dur entre le module et la config d'hôte.

#### Ce qu'il ne faut surtout PAS supprimer au passage

La partie la plus risquée : ces éléments ressemblent à du résidu UID sans en être.

1. **`partOf` + `wantedBy` sur `wireguard-wg0` de qBittorrent** — vit *à
   l'intérieur* du bloc `lib.optionalAttrs (isolation == "netns")`. En retirant le
   branchement il faut le rendre **inconditionnel**, pas le perdre avec le bloc.
   C'est le correctif du § piège 6 : sans lui le port forward redevient
   silencieusement injoignable à chaque redémarrage du tunnel.
2. **`wants = [ "wireguard-wg0.service" ]` dans le drop-in netns** — porteur, pas
   cosmétique : c'est ce qui remonte le tunnel si rien d'autre ne l'a fait
   (§ piège 7). Ne jamais le transformer en `requires`.
3. **L'ABSENCE d'ordonnancement sur `adguardhome`** sur `wireguard-wg0`. Le
   commentaire qui l'explique doit rester : quelqu'un qui « répare » en
   réintroduisant `after = [ "adguardhome.service" ]` recrée le cycle qui
   supprime le job de démarrage du tunnel.
4. **Le défaut vide de `netns.services`** et la contribution par module. Le
   remettre non vide réintroduit le bug du lot B — et cette fois sans kill-switch
   pour rattraper.
5. **Le `lib.mkMerge` de la section `config`** — pas un choix de style : la
   définition dynamique `systemd.services = lib.genAttrs …` ne peut pas cohabiter
   avec les `systemd.services.<nom>` littéraux dans le même attrset. Le collapser
   produit une erreur de syntaxe Nix.

#### Effets de bord mécaniques

- L'argument `options` de la signature du module ne sert plus qu'à l'assertion →
  le retirer, sinon `deadnix` le signale.
- `pkgs.nftables` et `pkgs.coreutils` n'étaient utilisés que par les deux unités →
  plus aucune référence à nftables dans le module.
- `networking.firewall.interfaces` n'a plus besoin de `mkMerge` (une seule entrée,
  la veth) → simplifier en attrset simple.
- **Vérifié** : `notify.services` ne contient aucune unité `vpn-*` (pas de risque
  FAC-5) et le regex `unit-include` de `node.nix` ne les mentionne pas non plus.

#### Documentation, dans le même commit

`AGENTS.md`, quatre entrées à corriger :

| Ligne | Problème |
|---|---|
| 15 | décrit l'architecture comme « table 4242, kill-switch nft par UID » |
| 75 | affirme que le `fwMark` est obligatoire — **devenu faux** ; le remplacer par le constat inverse et sa raison (la socket de transport reste côté hôte, donc le `fwMark` n'était nécessaire *que* tant que le kill-switch vivait) |
| 79 | décrit les exceptions Tailscale vers la table 52, supprimées |
| 80 | décrit la gymnastique `after`/`partOf`/`wantedBy` du `DynamicUser` Prowlarr, dont la disparition est le bénéfice même de la migration |

Et **ajouter** les quirks acquis : `checkReversePath` est du rpfilter iptables
donc par namespace, et Tailscale l'épingle à `loose` (§ piège 5) ; un service qui
lie un listener entrant au tunnel doit redémarrer avec lui (§ piège 6) ; le cycle
d'ordonnancement et le fait que `systemctl --failed` vide ≠ boot sain
(§ piège 7) ; Bindery met en cache sa config client au démarrage.

`docs/torrent-vpn.md` : toute la section diagnostics passe en
`ip netns exec vpn …`, et il faut y écrire que **`wg0` n'apparaît plus dans un
`ip a` sur l'hôte** — sans ça le prochain diagnostic conclut que le tunnel est
mort. Y verser aussi les deux tests qui mentent (un `curl` depuis hyper vers sa
propre IP LAN passe par `lo` donc est accepté et ne prouve rien sur un port ;
Traefik n'écoute que sur `192.168.10.100`, un test loopback renvoie `000`).

#### Test d'acceptation — fort, mais pas « 0 octet »

**Tout ce qui est supprimé est déjà inerte** en mode netns, donc le nettoyage ne
doit **rien changer au comportement**. La formulation initiale de ce test —
« `nh os switch` doit annoncer 0 octet » — était **trop stricte**, et l'exécution
l'a montré : le chemin du système a changé pour deux raisons parfaitement
bénignes, qu'il faut anticiper pour ne pas s'alarmer.

1. Les **commentaires vivent dans la dérivation du script** d'une unité : toute
   reformulation change son hash.
2. Retirer des options change le **manuel NixOS généré**, qui fait partie de la
   clôture (`documentation.nixos.enable = true`).

La bonne formulation : **aucun changement fonctionnel**, vérifiable précisément.

```bash
# Chaque unité doit être identique au bit près, hors diffs de commentaires
nix eval --raw '.#nixosConfigurations.hyper.config.systemd.units."<u>.service".text'
# et pour l'unité dont le script a changé, comparer la logique seule :
diff <(grep -vE '^\s*#|^\s*$' ancien) <(grep -vE '^\s*#|^\s*$' nouveau)
```

Résultat obtenu : `wireguard-wg0.service` et `qbittorrent.service` **identiques
au bit près**, `netns-vpn.service` différant uniquement par des commentaires
(logique identique confirmée par diff). Puis `nh os switch` : `-32 bytes`.

En complément : `nix eval` doit confirmer l'absence de
`vpn-policy-routing`/`vpn-killswitch` (déjà le cas), les quatre
`NetworkNamespacePath` toujours en place, et `qbittorrent` conservant
`partOf`/`wantedBy` sur `wireguard-wg0`. Runtime : tunnel up, port
`reachable: true`, 0 unité en échec, **et** `journalctl -b` sans « ordering
cycle ».

#### Ce que devient le rollback

Une fois `isolation` supprimée, revenir en arrière passe par la génération
précédente (`nixos-rebuild --rollback` ou l'entrée de boot) ou par un `git
revert`. La première voie a une **fenêtre bornée par le garbage collector** :
quand les générations en mode UID seront collectées, seul le revert git restera.
Ce n'est pas un problème, mais le nettoyage transforme un rollback en une ligne
en un rollback qui demande un rebuild.

## Déploiement et retour arrière

SSH et Tailscale restent dans le namespace hôte → **aucun risque de
verrouillage**, un `switch` à chaud est sûr de ce point de vue.

Passer quand même par **`nixos-rebuild test`** sur hyper avant le `switch` : ça
valide la création du netns et le démarrage des services **sans écrire de
génération**, et un simple reboot annule tout.

Retour arrière propre : `vpn.airvpn.isolation = "uid"`.

Deux détails de méthode propres à ce dépôt :

- `notify.services` a le garde-fou **FAC-5** (assertion à l'éval) : si
  `netns-vpn` y est ajouté, l'unité doit être réellement définie.
- Le backup restic de Prowlarr fait toujours `stop`/`start` — après le lot B,
  c'est **totalement inoffensif**, le netns ne dépendant plus de l'UID.

## Tests d'acceptation

```bash
# 1. Étanchéité : aucune sortie hors tunnel pour les services du netns
ip netns exec vpn curl -s https://api.ipify.org     # IP AirVPN
sudo -u logikdev curl -s https://api.ipify.org      # IP WAN

# 2. Fail-closed (structurel : plus de route par défaut)
sudo systemctl stop wireguard-wg0
ip netns exec vpn curl --max-time 5 https://api.ipify.org   # ENETUNREACH / timeout
#    Dimension DNS du fail-closed (complément bon marché du test 3) :
ip netns exec vpn dig +short +time=3 @10.128.0.1 example.com # doit échouer
sudo systemctl start wireguard-wg0

# 3. DNS applicatif : le BindReadOnlyPaths a-t-il pris ? (test de CORRECTION)
#    Seule preuve directe : lire le resolv.conf effectif dans le mount ns du service.
for s in qbittorrent prowlarr cross-seed; do
  nsenter -t "$(systemctl show -p MainPID --value $s)" -m cat /etc/resolv.conf
done                                                # doit montrer 10.128.0.1

#    Puis voir les requêtes entrer dans le tunnel — wg0 n'existe QUE dans le netns.
ip netns exec vpn tcpdump -ni wg0 port 53
ip netns exec vpn getent hosts <tracker>            # doit résoudre (pas `dig @…`)

# NE PAS utiliser pour ça :
#  - `tcpdump -ni management port 53 or 853` : AdGuard fait son DoT vers Quad9 en
#    permanence, le trafic est présent quoi qu'il arrive → non concluant.
#  - `dig +short @10.128.0.1` : `@serveur` contourne /etc/resolv.conf, donc ne dit
#    rien de ce que les services utilisent réellement.
#  - « aucune requête 10.128.0.1:53 sur management » : ce trafic ne peut exister là
#    qu'encapsulé dans UDP/1637 → le test passe toujours (fausse assurance).

# 4. Le tunnel survit à la perte du résolveur d'amorçage (endpoint en cache)
sudo systemctl stop adguardhome
ip netns exec vpn curl -s https://api.ipify.org     # doit toujours sortir
sudo systemctl start adguardhome

# 5. Écoutes bien exposées sur le veth
ip netns exec vpn ss -tlnp                          # 8090 et 9696 sur *

# 6. Traversée de frontière, dans les deux sens
curl -s -o /dev/null -w '%{http_code}' http://10.200.0.2:8090   # Traefik → qBittorrent
ip netns exec vpn curl -s -o /dev/null -w '%{http_code}' http://10.200.0.1:8989  # Prowlarr → Sonarr

# 7. Port forward toujours joignable (ratio)
ip netns exec vpn curl -s https://ifconfig.co/port/47594        # reachable:true

# 8. Idempotence et absence d'échec
sudo systemctl restart netns-vpn && systemctl --failed
```

## Supervision (fait — 2026-09-28)

Le seul point resté ouvert à la clôture est traité : `vpn-monitor.timer` publie
six métriques textfile toutes les 5 min et quatre alertes Prometheus les
exploitent (`VpnTunnelDown`, `VpnTrafficLeak`, `VpnListenerUnbound`,
`VpnMonitorMissing`). Détail dans `docs/torrent-vpn.md` § Supervision.

Deux pièges rencontrés en l'écrivant, tous deux du même genre — une supervision
qui ment est pire que pas de supervision :

1. **NixOS préfixe le script d'une unité par `set -e`**, qu'un `set -uo pipefail`
   écrit ensuite n'annule pas. Résultat au premier test d'injection de panne : le
   script s'arrêtait sur l'échec de `wg show` avant d'écrire quoi que ce soit, et
   le fichier `.prom` conservait ses valeurs précédentes — **tunnel mort,
   métriques saines**. Corrigé par un `set +e` en première ligne.
2. **`absent()` ne détecte pas un moniteur planté** : le collecteur textfile de
   node_exporter sert un `.prom` indéfiniment. Le dead-man doit tester la
   *fraîcheur* de l'horodatage écrit à chaque exécution.

Validé de bout en bout : injection de panne (handshake 0, route 0, listener 0,
unité qui ne plante pas), rétablissement, puis vérification que Prometheus
scrape bien les six séries et charge les quatre règles.

## Références

- <https://www.wireguard.com/netns/> — montage socket dehors / interface dedans.
- `docs/torrent-vpn.md` — implémentation actuelle, pièges historiques.
- `docs/audit-2026-09.md` — **SEC-13** (statut `todo`) : le constat et la
  correction proposée ; **Décisions ouvertes n°7** : la décision go/no-go ;
  **Journal de sessions 2026-09-28** : ce qui a été vérifié dans nixpkgs et les
  corrections issues de la contre-vérification.
