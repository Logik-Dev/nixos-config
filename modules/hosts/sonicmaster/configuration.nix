{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.sonicmaster.imports = with inputs.self.modules.nixos; [
    agenix
    audio
    common
    gnome
    kvm-intel
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
