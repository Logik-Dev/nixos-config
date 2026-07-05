{ ... }:
{
  flake.modules.nixos.grafana =
    { config, ... }:
    {
      age.secrets."grafana-admin-pw".owner = "grafana";
      age.secrets."grafana-secret-key".owner = "grafana";

      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "127.0.0.1";
            http_port = 3002;
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
            # Assigning a uid to an already-provisioned datasource breaks the
            # update path: Grafana looks the datasource up by the NEW uid,
            # finds nothing, and the whole service fails to start ("data
            # source not found"). Deleting by name first makes provisioning
            # idempotent whatever the previous state.
            deleteDatasources = [
              {
                name = "Prometheus";
                orgId = 1;
              }
              {
                name = "Loki";
                orgId = 1;
              }
            ];
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                # Fixed uid so provisioned dashboard JSON can reference the
                # datasource without depending on a generated identifier.
                uid = "prometheus";
                url = "http://127.0.0.1:9090";
                access = "proxy";
                isDefault = true;
              }
              {
                name = "Loki";
                type = "loki";
                uid = "loki";
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
        port = 3002;
        enableAuthelia = true;
      };

      notify.services = [ "grafana" ];

      # grafana.db (SQLite): users, API keys, annotations, dashboard state not
      # covered by Nix provisioning. Stopped during backup for a consistent copy.
      backups.sources.grafana = {
        paths = [ "/var/lib/grafana" ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
