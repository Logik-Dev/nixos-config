{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./adguard.nix
    inputs.cf-ddns.nixosModules.x86_64-linux.default
  ];

  networking.networkmanager.enable = lib.mkForce false;
  networking.nameservers = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  sops.secrets."ddns.env" = {
    sopsFile = ./ddns.env;
    format = "dotenv";
    key = "";
  };

  services.cf-ddns = {
    enable = true;
    environmentFile = config.sops.secrets."ddns.env".path;
  };

  systemd.timers."cf-ddns" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "cf-ddns.service";
    };
  };
}
