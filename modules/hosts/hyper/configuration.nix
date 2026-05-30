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
      home
      immich
      kvm-intel
      logikdev
      minio
      monitoring
      mosquitto
      neovim
      #libvirt
      no-root-password
      nvidia
      postgresql
      restic
      rustfs
      seedbox
      syncthing
      tailscale
      traefik
      unifi
      vaultwarden
    ])
    ++ [
      # host-specific tailscale config
      {
        networking.firewall.allowedTCPPorts = [
          22
          5432
          3333
          11434
        ];
        notify.services = [ "tailscale" ];
        services.tailscale = {
          useRoutingFeatures = "both";
          extraUpFlags = [ "--ssh" ];
          extraSetFlags = [ "--advertise-routes=192.168.10.0/24,192.168.21.0/24" ];
        };
        traefik.services.ollama.port = 11434;
      }
      # host-specific SSH authorized keys
      {
        users.users.logikdev.openssh.authorizedKeys.keyFiles = [
          (inputs.self + "/secrets/yubikey.pub")
          (inputs.self + "/secrets/m4.pub")
        ];
      }
      # minio data directory
      {
        services.minio.dataDir = [ "/mnt/ultra/minio" ];
      }
    ];

  disableNetworkManager = {
    networking.networkmanager.enable = lib.mkForce false;
  };

in
{
  inherit flake;
}
