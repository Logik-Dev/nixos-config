# ACL Tailscale — versionner et appliquer

Les ACL Tailscale ne sont **pas** gérées par Nix : elles vivent dans la console
Tailscale (admin → *Access Controls*). Ce document fige la politique voulue pour
qu'elle soit auditable et reproductible (audit 2026-09, SEC-11).

## Modèle

- **hyper** est *subnet router* : il annonce `192.168.10.0/24` (LAN) et
  `192.168.21.0/24` (IoT). Ces routes doivent être **approuvées** dans la console
  (Machines → hyper → Edit route settings).
- **sonicmaster** et **m4** acceptent les routes (`--accept-routes` /
  `overrideLocalDns = true`).
- **Pas de Tailscale SSH** : `--ssh` a été retiré de la config de hyper. L'admin
  passe par `sshd` (clé-only + fail2ban) sur l'IP tailnet, pas par le serveur SSH
  Tailscale (qui contournerait sshd/fail2ban).

## ACL à coller (console → Access Controls)

Remplacer `<tailnet>` par le nom du tailnet. Ajuster les tags selon les appareils
existants (des appareils sont déjà `tagged-devices`, ex. iPhone/Android).

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:client": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["hyper:22"]
    },
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["192.168.10.0/24:*", "192.168.21.0/24:*"]
    }
  ],
  "ssh": []
}
```

Notes :

- `ssh: []` désactive explicitement Tailscale SSH pour tout le monde.
- La 2ᵉ règle autorise les membres à joindre le LAN/IoT **via** hyper (subnet
  router). Retirer/adapter si l'on veut cloisonner (par ex. IoT réservé à
  `tag:server`).
- Les nœuds eux-mêmes ne sont pas ouverts hors des destinations listées : le
  trafic inter-nœuds direct (hors routes) reste régi par ces règles.

## Procédure d'application

1. Console Tailscale → *Access Controls* → coller le JSON → *Save*.
2. Machines → `hyper` → *Edit route settings* → approuver `192.168.10.0/24` et
   `192.168.21.0/24`.
3. Vérifier depuis hyper :
   ```
   tailscale debug prefs | grep -E 'AdvertiseRoutes|RunSSH'
   tailscale status --json | jq '.Peer[] | select(.HostName=="m4") | .PrimaryRoutes'
   ```
   (`RunSSH` doit rester `false`, les routes approuvées apparaître côté pairs.)
4. Depuis m4, tester un accès à un hôte du LAN via le nom/IP (ex. `ssh h`).

## Historique

- 2026-09-26 : `--ssh` retiré de hyper, politique ci-dessus (audit SEC-11).
