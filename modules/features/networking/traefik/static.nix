{ ... }:
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
