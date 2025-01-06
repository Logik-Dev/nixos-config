{ lib, ... }:
{
  imports = [
    ./victoriametrics.nix
  ];
  networking.networkmanager.enable = lib.mkForce false;
}
