_:
let
  prometheusModule =
    {
      config,
      ...
    }:
    let
      host = config.networking.hostName;
      domain = config.constants.domain;
      traefikServices = builtins.attrNames config.traefik.services;
      exporters = config.services.prometheus.exporters;
    in
    {
      services.prometheus = {
        enable = true;
        port = 9090;
        listenAddress = "127.0.0.1";
        # Kept at the historical "prometheus" path (nixpkgs' default is now
        # "prometheus2"): renaming it would orphan the existing 30d TSDB.
        stateDir = "prometheus";
        retentionTime = "30d";

        scrapeConfigs = [
          {
            job_name = "node";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:${toString exporters.node.port}" ]; }
            ];
          }
          {
            job_name = "postgres";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:${toString exporters.postgres.port}" ]; }
            ];
          }
          {
            job_name = "nvidia-gpu";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:${toString exporters.nvidia-gpu.port}" ]; }
            ];
          }
          {
            job_name = "traefik";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:8082" ]; }
            ];
          }
          {
            job_name = "authelia";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:9959" ]; }
            ];
          }
          {
            job_name = "fail2ban";
            scrape_interval = "15s";
            static_configs = [
              { targets = [ "127.0.0.1:${toString exporters.fail2ban.port}" ]; }
            ];
          }
          {
            job_name = "restic";
            scrape_interval = "60s";
            static_configs = map (inst: {
              targets = [ "127.0.0.1:${toString inst.port}" ];
              labels = {
                repository = inst.name;
              };
            }) config.resticExporters;
          }
          {
            job_name = "blackbox_http";
            scrape_interval = "30s";
            metrics_path = "/probe";
            params = {
              module = [ "http_2xx" ];
            };
            static_configs = [
              {
                targets = map (s: "https://${s}.${host}.${domain}") traefikServices;
              }
            ];
            relabel_configs = [
              {
                source_labels = [ "__address__" ];
                target_label = "__param_target";
              }
              {
                source_labels = [ "__param_target" ];
                target_label = "service";
                regex = "https://([^.]+)\\..*";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:${toString exporters.blackbox.port}";
              }
            ];
          }
        ];

        alertmanagers = [
          {
            static_configs = [
              { targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ]; }
            ];
          }
        ];
      };

      notify.services = [ "prometheus" ];
    };
in
{
  flake.modules.nixos.prometheus.imports = [ prometheusModule ];
}
