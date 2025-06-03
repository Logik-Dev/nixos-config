{
  config,
  domain,
  ...
}:
{

  sops.secrets."vaultwarden.env" = {
    owner = "vaultwarden";
    format = "dotenv";
    key = "";
    sopsFile = ../../secrets/vaultwarden.security.env;
    restartUnits = [ "vaultwarden.service" ];
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden.env".path;
  };

  networking.firewall.allowedTCPPorts = [ 8222 ];
}
