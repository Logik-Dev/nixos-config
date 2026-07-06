{
  # Glance — homelab homepage. Reachable at home.hyper.logikdev.fr.
  #
  # Design note on the monitor widgets: each site's `url` is the public HTTPS
  # link (what you click), while `check-url` points at the localhost backend.
  # Glance runs on hyper, so the health probe hits the service directly —
  # bypassing Traefik, TLS and Authelia entirely — which keeps the status dots
  # honest even for Authelia-gated services.
  flake.modules.nixos.glance = {
    services.glance = {
      enable = true;
      settings = {
        server = {
          host = "127.0.0.1";
          port = 3004;
        };

        branding.custom-footer = "Homelab hyper";

        theme = {
          background-color = "225 14 12";
          primary-color = "205 68 66";
          contrast-multiplier = 1.1;
        };

        pages = [
          {
            name = "Accueil";
            columns = [
              {
                size = "small";
                widgets = [
                  {
                    type = "clock";
                    hour-format = "24h";
                    timezones = [ ];
                  }
                  {
                    type = "server-stats";
                    servers = [
                      {
                        type = "local";
                        name = "hyper";
                      }
                    ];
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "monitor";
                    title = "Médias";
                    cache = "1m";
                    sites = [
                      {
                        title = "Jellyfin";
                        url = "https://jellyfin.hyper.logikdev.fr";
                        check-url = "http://localhost:8096";
                        icon = "di:jellyfin";
                      }
                      {
                        title = "Immich";
                        url = "https://immich.hyper.logikdev.fr";
                        check-url = "http://localhost:2283";
                        icon = "di:immich";
                      }
                      {
                        title = "Jellyseerr";
                        url = "https://seerr.hyper.logikdev.fr";
                        check-url = "http://localhost:5055";
                        icon = "di:jellyseerr";
                      }
                      {
                        title = "Radarr";
                        url = "https://radarr.hyper.logikdev.fr";
                        check-url = "http://localhost:7878";
                        icon = "di:radarr";
                      }
                      {
                        title = "Sonarr";
                        url = "https://sonarr.hyper.logikdev.fr";
                        check-url = "http://localhost:8989";
                        icon = "di:sonarr";
                      }
                      {
                        title = "Prowlarr";
                        url = "https://prowlarr.hyper.logikdev.fr";
                        check-url = "http://localhost:9696";
                        icon = "di:prowlarr";
                      }
                      {
                        title = "SABnzbd";
                        url = "https://sabnzbd.hyper.logikdev.fr";
                        check-url = "http://localhost:8088";
                        icon = "di:sabnzbd";
                      }
                      {
                        title = "Rankoder";
                        url = "https://rankoder.hyper.logikdev.fr";
                        check-url = "http://localhost:8765";
                        icon = "di:rankoder";
                      }
                    ];
                  }
                  {
                    type = "monitor";
                    title = "Maison";
                    cache = "1m";
                    sites = [
                      {
                        title = "Home Assistant";
                        url = "https://hass.hyper.logikdev.fr";
                        check-url = "http://192.168.21.181:8123";
                        icon = "di:home-assistant";
                      }
                      {
                        title = "Mealie";
                        url = "https://mealie.hyper.logikdev.fr";
                        check-url = "http://localhost:9999";
                        icon = "di:mealie";
                      }
                      {
                        title = "Zigbee2MQTT";
                        url = "https://zigbee.hyper.logikdev.fr";
                        check-url = "http://localhost:8788";
                        icon = "di:zigbee2mqtt";
                      }
                      {
                        title = "Vaultwarden";
                        url = "https://vaultwarden.hyper.logikdev.fr";
                        check-url = "http://localhost:8082";
                        icon = "di:vaultwarden";
                      }
                    ];
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "monitor";
                    title = "Réseau & Stockage";
                    cache = "1m";
                    sites = [
                      {
                        title = "AdGuard Home";
                        url = "https://dns.hyper.logikdev.fr";
                        check-url = "http://localhost:3000";
                        icon = "di:adguard-home";
                      }
                      {
                        title = "UniFi";
                        url = "https://unifi.hyper.logikdev.fr";
                        check-url = "https://localhost:8443";
                        allow-insecure = true;
                        icon = "di:unifi";
                      }
                      {
                        title = "Syncthing";
                        url = "https://syncthing.hyper.logikdev.fr";
                        check-url = "http://localhost:8384";
                        icon = "di:syncthing";
                      }
                    ];
                  }
                  {
                    type = "monitor";
                    title = "Supervision";
                    cache = "1m";
                    sites = [
                      {
                        title = "Grafana";
                        url = "https://grafana.hyper.logikdev.fr";
                        check-url = "http://localhost:3002";
                        icon = "di:grafana";
                      }
                      {
                        title = "ntfy";
                        url = "https://ntfy.hyper.logikdev.fr";
                        check-url = "http://localhost:2586";
                        icon = "di:ntfy";
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
      };
    };

    traefik.services.home = {
      port = 3004;
      enableAuthelia = true;
    };

    notify.services = [ "glance" ];
  };
}
