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
          staticConfigOptions = {
            entryPoints.http.address = "192.168.10.100:80";
            entryPoints.https.address = "192.168.10.100:443";
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
          dynamicConfigOptions = {
            http.routers = mapAttrs' (
              service: value:
              nameValuePair service {
                inherit service;
                entryPoints = [ "https" ];
                tls.certResolver = "myresolver";
                rule = "Host(`${service}.${host}.${domain}`)";

              }

            ) cfg.services;

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
