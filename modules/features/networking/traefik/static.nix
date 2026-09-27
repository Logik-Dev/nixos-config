_:
let
  staticModule =
    {
      config,
      ...
    }:
    let
      email = config.constants.users.logikdev.email;
      lanIp = config.constants.hosts.hyper.lanIp;
    in
    {
      config = {
        networking.firewall.allowedTCPPorts = [
          443
          80
        ];

        notify.services = [ "traefik" ];

        # acme.json: losing it means re-issuing every certificate on restore
        # (Let's Encrypt rate limits). Live copy — stopping Traefik would take
        # every web service down.
        backups.sources.traefik = {
          paths = [ config.services.traefik.dataDir ];
          manageService = false;
        };

        services.traefik = {
          enable = true;
          environmentFiles = [ config.age.secrets.cloudflare.path ];
          dataDir = "/mnt/ultra/traefik";

          staticConfigOptions = {
            log.level = "INFO";

            # Security-relevant access logging only (auth failures, scans):
            # keep 4xx/5xx, to journald. Low noise, no logrotate needed.
            accessLog = {
              filters.statusCodes = [ "400-599" ];
              bufferingSize = 64;
            };

            # dashboard
            api.dashboard = true;
            api.insecure = false;

            # HTTP
            entryPoints.http = {
              address = "${lanIp}:80";
              http.redirections.entryPoint = {
                to = "https";
                scheme = "https";
              };
            };

            # HTTPS
            entryPoints.https.address = "${lanIp}:443";

            # Prometheus metrics on a dedicated loopback entrypoint (scraped by
            # Prometheus on hyper): request counts/latency per entrypoint,
            # service and router.
            entryPoints.metrics.address = "127.0.0.1:8082";
            metrics.prometheus = {
              addEntryPointsLabels = true;
              addServicesLabels = true;
              addRoutersLabels = true;
              entryPoint = "metrics";
            };

            # ACME
            certificatesResolvers.myresolver.acme = {
              inherit email;
              storage = "${config.services.traefik.dataDir}/acme.json";
              dnsChallenge = {
                provider = "cloudflare";
                resolvers = [
                  "1.1.1.1:53"
                  "8.8.8.8:53"
                ];
              };
            };
          };
        };
      };
    };
in
{
  flake.modules.nixos.traefik.imports = [ staticModule ];
}
