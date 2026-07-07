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
      disableNetworkManager
      ddns
      fail2ban
      hetznerStoragebox
      home
      immich
      kvm-intel
      logikdev
      blackbox
      alertmanager
      glance
      grafana
      loki
      monitoring
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
      alloy
      rankoder
      restic
      resticExporter
      restoreDrill
      seedbox
      smartd
      syncthing
      tailscale
      traefik
      unifi
      vaultwarden
    ])
    ++ [
      # host-specific tailscale config
      {
        # Only SSH needs a hole here. Postgres (5432) listens on localhost
        # only, and 3333/11434 (dead ollama) had no listener — all removed.
        networking.firewall.allowedTCPPorts = [
          22
        ];
        notify.services = [ "tailscale" ];
        services.tailscale = {
          useRoutingFeatures = "both";
          extraUpFlags = [ "--ssh" ];
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
    ];

  disableNetworkManager = {
    networking.networkmanager.enable = lib.mkForce false;
  };

in
{
  inherit flake;
}
