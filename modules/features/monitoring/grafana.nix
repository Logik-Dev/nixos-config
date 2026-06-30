{ ... }:
{
  flake.modules.nixos.grafana =
    { config, ... }:
    {
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "127.0.0.1";
            http_port = 3000;
            domain = "grafana.${config.networking.hostName}.${config.constants.domain}";
            root_url = "https://%(domain)s/";
            serve_from_sub_path = false;
          };
          security = {
            admin_password = "$__file{${config.age.secrets."grafana-admin-pw".path}}";
            secret_key = "$__file{${config.age.secrets."grafana-secret-key".path}}";
            disable_gravatar = true;
          };
          auth.anonymous_enabled = false;
        };

        provision = {
          enable = true;
          datasources.settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                url = "http://127.0.0.1:9090";
                access = "proxy";
                isDefault = true;
              }
              {
                name = "Loki";
                type = "loki";
                url = "http://127.0.0.1:3100";
                access = "proxy";
              }
            ];
          };
          dashboards.settings.providers = [
            {
              name = "default";
              options.path = ./grafana/dashboards;
              options.updateIntervalSeconds = 30;
            }
          ];
        };
      };

      traefik.services.grafana = {
        port = 3000;
        enableAuthelia = true;
      };

      notify.services = [ "grafana" ];
    };
}
