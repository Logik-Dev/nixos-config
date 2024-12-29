{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    inputs.cf-ddns.nixosModules.x86_64-linux.default
  ];

  networking.networkmanager.enable = lib.mkForce false;

  sops.secrets."ddns.env" = {
    sopsFile = ./ddns.env;
    format = "dotenv";
    key = "";
  };

  services.cf-ddns = {
    enable = true;
    environmentFile = config.sops.secrets."ddns.env".path;
  };
}
