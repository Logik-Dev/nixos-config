{ lib, ... }:
{
  imports = [
    ./grafana.nix
    ./loki.nix
    ./promtail.nix
    ./victoriametrics.nix
  ];
  networking.networkmanager.enable = lib.mkForce false;
}
