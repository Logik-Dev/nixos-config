{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.hyper.imports = with inputs.self.modules.nixos; [
    adguard
    agenix
    audio
    common
    disableNetworkManager
    ddns
    kvm-intel
    #libvirt
    no-root-password
    nvidia
    reverse-proxy
    seedbox
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
