{
  # Glance — homelab homepage. Reachable at home.hyper.logikdev.fr.
  #
  # Monitor widgets are auto-generated from config.traefik.services: each
  # service with a non-null `category` becomes a site entry. The public URL
  # is derived from the service key + host + domain; the check-url hits the
  # backend directly (bypassing Traefik/TLS/Authelia) so health dots stay
  # honest even for Authelia-gated services.
  flake.modules.nixos.glance =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.traefik.services;
      host = config.networking.hostName;
      domain = config.constants.domain;

      servicesInCategory = cat: lib.filterAttrs (_: v: v.category == cat) cfg;

      mkSite =
        name: value:
        let
          site = {
            title = if value.title != null then value.title else name;
            url = "https://${name}.${host}.${domain}";
            check-url = "${value.protocol}://${value.host}:${toString value.port}";
          };
        in
        site
        // lib.optionalAttrs (value.icon != null) { icon = value.icon; }
        // lib.optionalAttrs value.insecureSkipVerify { allow-insecure = true; };

      mkMonitor = cat: {
        type = "monitor";
        title = cat;
        cache = "1m";
        sites = lib.mapAttrsToList mkSite (servicesInCategory cat);
      };
    in
    {
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
                    (mkMonitor "Médias")
                    (mkMonitor "Maison")
                  ];
                }
                {
                  size = "full";
                  widgets = [
                    (mkMonitor "Réseau & Stockage")
                    (mkMonitor "Supervision")
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
