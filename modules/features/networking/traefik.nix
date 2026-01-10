{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) email domain;

  flake.modules.nixos.hyper = {
    imports = [ inputs.self.modules.nixos.traefik ];
    services.mytraefik.enable = true;
  };

  flake.modules.nixos.traefik =
    {
      lib,
      config,
      commonSecret,
      ...
    }:
    with lib;
    let
      cfg = config.services.mytraefik;
      host = config.networking.hostName;

      service = types.submodule {
        options = {
          subdomain = mkOption {
            description = "Alternative subdomain name, if not set default to vhost name";
            type = types.nullOr types.str;
            default = null;
          };

          host = mkOption {
            description = "Host IP";
            type = types.str;
            default = "localhost";
          };

          port = mkOption {
            description = "Port which the service is listening on";
            type = types.nullOr types.number;
            default = null;
          };

          protocol = mkOption {
            description = "Protocol to use http or https";
            type = types.enum [
              "http"
              "https"
            ];
            default = "http";
          };

          enableAuthelia = mkOption {
            description = "Wheter to enable authelia";
            type = types.bool;
            default = false;
          };
        };
      };
    in
    {

      options.services.mytraefik = {
        enable = mkEnableOption "Enable traefik reverse-proxy";
        services = mkOption {
          description = "Attribute set of services";
          type = types.attrsOf service;
          default = { };
        };
      };

      config = mkIf cfg.enable {

        networking.firewall.allowedTCPPorts = [
          443
          80
        ];

        age.secrets.cloudflare.rekeyFile = commonSecret "cloudflare";

        services.traefik = {
          enable = true;
          environmentFiles = [
            config.age.secrets.cloudflare.path
          ];
          dataDir = "/mnt/ultra/traefik";

          # static config
          staticConfigOptions = {
            log.level = "DEBUG";

            # dashboard
            api.dashboard = true;
            api.insecure = false;

            # HTTP
            entryPoints.http = {
              address = "192.168.10.100:80";
              http.redirections.entryPoint = {
                to = "https";
                scheme = "https";
              };
            };

            # HTTPS
            entryPoints.https.address = "192.168.10.100:443";

            # ACME
            certificatesResolvers.myresolver.acme = {
              email = email;
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

          # dynamic config
          dynamicConfigOptions = {

            # middlewares
            http.middlewares.authelia.forwardAuth = {
              address = "http://localhost:9091/api/authz/forward-auth";
              trustForwardHeader = "true";
              authResponseHeaders = "Remote-User,Remote-Groups,Remote-Email,Remote-Name";
            };

            # router
            http.routers =
              (mapAttrs' (
                service: value:
                nameValuePair service {
                  inherit service;
                  entryPoints = [ "https" ];
                  tls.certResolver = "myresolver";
                  rule = "Host(`${service}.${host}.${domain}`)";
                  middlewares = lib.mkIf value.enableAuthelia "authelia@file";
                }

              ) cfg.services)
              // {
                # Dashboard
                dashboard = {
                  rule = "Host(`traefik.${host}.${domain}`)";
                  middlewares = "authelia@file";
                  entryPoints = [ "https" ];
                  service = "api@internal";
                  tls.certResolver = "myresolver";
                };

              };

            # services
            http.services = mapAttrs' (
              service: value:
              nameValuePair service {
                loadBalancer.servers = [
                  {
                    url = "${value.protocol}://${value.host}:${toString value.port}";
                  }
                ];
              }
            ) cfg.services;

          };
        };
      };
    };
in
{
  inherit flake;
}
