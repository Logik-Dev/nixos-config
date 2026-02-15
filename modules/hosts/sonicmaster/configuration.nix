{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.sonicmaster.imports = with inputs.self.modules.nixos; [
    audio
    common
    gnome
    kvm-intel
    logikdev
    network
    yubikey
  ];

  network = {
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault true;
  };

in
{
  inherit flake;
}
