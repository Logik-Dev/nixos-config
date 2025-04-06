{
  config,
  homelab,
  ...
}:
{

  sops.secrets."grafana-secret-key" = {
    owner = "grafana";
    sopsFile = ./secrets.yaml;
  };

  sops.secrets."grafana-password" = {
    owner = "grafana";
    sopsFile = ./secrets.yaml;
  };

  sops.secrets."grafana-email" = {
    owner = "grafana";
    sopsFile = ./secrets.yaml;
  };

  services.grafana = {
    enable = true;
    settings = {
      plugins = {
        allow_loading_unsigned_plugins = "victoriametrics-datasource";
      };
      security = {
        admin_user = homelab.username;
        admin_password = "$__file{${config.sops.secrets.grafana-password.path}}";
        admin_email = "$__file{${config.sops.secrets.grafana-email.path}}";
        secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
      };
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "grafana.${homelab.domain}";
      };
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "https://victoriametrics.${homelab.domain}";
        }
        {
          name = "Loki";
          type = "loki";
          url = "https://loki.${homelab.domain}";
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Incus";
          options.path = ./dashboards/incus.json;

        }
      ];
    };

  };

  services.nginx.virtualHosts."grafana.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://localhost:3000";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

}
