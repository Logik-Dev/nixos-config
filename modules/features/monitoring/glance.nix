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

      # Every category used by a service must appear in the dashboard layout
      # below; the assertion at the bottom prevents a new category (like
      # "Automatisation"/n8n once was) from silently disappearing.
      categories = [
        "Médias"
        "Maison"
        "Réseau & Stockage"
        "Supervision"
        "Automatisation"
      ];

      usedCategories = lib.unique (lib.filter (c: c != null) (lib.mapAttrsToList (_: v: v.category) cfg));

      missingCategories = lib.subtractLists categories usedCategories;

      # A port-less service cannot produce a check-url; skip it defensively.
      servicesInCategory = cat: lib.filterAttrs (_: v: v.category == cat && v.port != null) cfg;

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
        // lib.optionalAttrs (value.icon != null) { inherit (value) icon; }
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
                    (mkMonitor "Automatisation")
                  ];
                }
              ];
            }
          ];
        };
      };

      assertions = [
        {
          assertion = missingCategories == [ ];
          message = "Glance dashboard is missing categories: ${lib.concatStringsSep ", " missingCategories}";
        }
      ];

      traefik.services.home = {
        port = 3004;
        enableAuthelia = true;
      };

      notify.services = [ "glance" ];
    };
}
