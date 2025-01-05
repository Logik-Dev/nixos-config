{
  config,
  homelab,
  ...
}:
{

  sops.secrets."vaultwarden.env" = {
    owner = "vaultwarden";
    format = "dotenv";
    key = "";
    sopsFile = ./vaultwarden.env;
    restartUnits = [ "vaultwarden.service" ];
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
