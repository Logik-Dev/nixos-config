{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.hyper.imports =
    (with inputs.self.modules.nixos; [
      adguard
      audio
      common
      cross-seed
      disableNetworkManager
      ddns
      fail2ban
      freeleech-farmer
      hetznerStoragebox
      mealie
      immich
      io-scheduler
      kvm-intel
      logikdev
      blackbox
      alertmanager
      glance
      grafana
      notification
      mqtt
      mqtt-clients
      n8n
      neovim
      gpu
      hardening
      home-assistant
      node
      cgroup-pressure
      nvidia
      ollama
      paperless
      pgbackrest
      postgres
      postgresql
      prometheus
      qbittorrent
      rankoder
      restic
      restoreDrill
      seedbox
      slskd
      smartd
      syncthing
      tailscale
      traefik
      unifi
      vaultwarden
      vpn-torrent
    ])
    ++ [
      # host-specific tailscale config
      {
        # Only SSH needs a hole here. Postgres (5432) listens on localhost
        # only, and 3333/11434 (dead ollama) had no listener — all removed.
        networking.firewall.allowedTCPPorts = [
          22
        ];
        notify.services = [ "tailscaled" ];
        services.tailscale = {
          useRoutingFeatures = "both";
          # No `--ssh`: Tailscale SSH would bypass sshd (key-only) and fail2ban.
          # Regular sshd over the tailnet is the only admin path.
          extraSetFlags = [ "--advertise-routes=192.168.10.0/24,192.168.21.0/24" ];
        };
      }
      # host-specific SSH authorized keys
      {
        users.users.logikdev.openssh.authorizedKeys.keyFiles = [
          (inputs.self + "/secrets/yubikey.pub")
          (inputs.self + "/secrets/m4.pub")
          (inputs.self + "/secrets/id_ed25519.pub")
        ];
      }
      # host-specific musique : import auto de la file (WP5). Un faux positif
      # se corrige via `beet-classique remove -d` (M16).
      { musique.autoImport = true; }
      # AirVPN WireGuard for torrenting
      (
        { config, ... }:
        {
          vpn.airvpn = {
            enable = true;
            address = "10.150.11.114/32";
            publicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
            endpoint = "nl3.vpn.airdns.org:1637";
            # Must match the AirVPN forwarded public port (Client Area ->
            # Forwarded ports, with "Local" left equal to the public port).
            # qBittorrent announces this port, so public != local = unreachable.
            forwardedPort = 47594;
            # Second forwarded port, slskd's Soulseek listener (§0.2 du plan
            # musique) — same public = local rule.
            forwardedPortSlskd = 54500;
            privateKeyFile = config.age.secrets."airvpn-private.key".path;
            presharedKeyFile = config.age.secrets."airvpn-psk.key".path;
          };
        }
      )
    ];

  disableNetworkManager = {
    networking.networkmanager.enable = lib.mkForce false;
  };

in
{
  inherit flake;
}
