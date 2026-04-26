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
    #libvirt
    no-root-password
    nvidia
    postgresql
    restic
    seedbox
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
