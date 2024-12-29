{
  config,
  homelab,
  pkgs,
  ...
}:
let
  user = homelab.username;
in
{

  sops.secrets."vaultwarden.env" = {
    owner = "vaultwarden";
    format = "dotenv";
    key = "";
    sopsFile = ./vaultwarden.env;
    restartUnits = [ "vaultwarden.service" ];
  };

  sops.secrets.borg = {
    sopsFile = ../common/secrets.yaml;
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden.env".path;
  };

  # Nginx
  services.nginx.virtualHosts."vaultwarden.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;

    locations."/" = {
      proxyWebsockets = true;
      proxyPass = "http://localhost:8222";
    };

  };

}
