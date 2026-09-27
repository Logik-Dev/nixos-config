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
      kvm-intel
      logikdev
      blackbox
      alertmanager
      glance
      grafana
      notification
      mqtt
      n8n
      neovim
      gpu
      hardening
      node
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
      # AirVPN WireGuard for torrenting
      (
        { config, ... }:
        {
          vpn.airvpn = {
            enable = true;
            address = "10.150.11.114/32";
            publicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
            endpoint = "nl3.vpn.airdns.org:1637";
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
