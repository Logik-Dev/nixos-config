{ homelab, config, ... }:
{

  sops.secrets."homepage.env" = {
    sopsFile = ./secrets.env;
    format = "dotenv";
    key = "";
    restartUnits = [ "homepage-dashboard.service" ];
  };

  services.homepage-dashboard = {
    enable = true;
    environmentFile = "/run/secrets/homepage.env";
    settings = {
      headerStyle = "boxedWidgets";
      target = "_blank";
    };
    widgets = [
      {
        resources = {
          label = "Storage";
          expanded = true;
          disk = [
            "/mnt/archives"
            "/mnt/raid"
            "/pools/ultra"
            "/"
          ];
        };
      }
      {
        resources = {
          label = "System";
          cpu = true;
          memory = true;
          network = true;
          uptime = true;
        };
      }
    ];
    services = [
      {
        Medias = [
          {
            Jellyfin = {
              icon = "jellyfin.png";
              href = "https://jellyfin.${homelab.domain}";
              description = "Open source media player";
              widget = {
                type = "jellyfin";
                url = "https://jellyfin.${homelab.domain}";
                key = "{{ HOMEPAGE_VAR_JELLYFIN_KEY }}";
                movies = true;
                series = true;
                enableBlocks = true;
                enableNowPlaying = true;
              };

            };
          }
        ];
      }
    ];
  };

  services.nginx.virtualHosts."homepage.${homelab.domain}" = {
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    locations."/".proxyPass =
      "http://localhost:${toString config.services.homepage-dashboard.listenPort}";
  };
}
