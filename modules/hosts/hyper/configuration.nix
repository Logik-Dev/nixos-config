{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.hyper.imports = with inputs.self.modules.nixos; [
    adguard
    audio
    common
    disableNetworkManager
    ddns
    home
    immich
    kvm-intel
    logikdev
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
    traefik
    unifi
    vaultwarden
  ];

  disableNetworkManager = {
    networking.networkmanager.enable = lib.mkForce false;
  };

in
{
  inherit flake;
}
