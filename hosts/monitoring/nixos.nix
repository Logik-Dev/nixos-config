{ lib, ... }:
{
  imports = [
    ./grafana.nix
    ./victoriametrics.nix
  ];
  networking.networkmanager.enable = lib.mkForce false;
}
