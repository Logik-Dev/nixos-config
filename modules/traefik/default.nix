{
  domain,
  email,
  lib,
  config,
  ...
}:
let
  cfg = config.services.traefik-proxy;
  svc = lib.types.submodule {
    options = {
      port = lib.mkOption {
        description = "Port which the service is listening on";
        type = lib.types.nullOr lib.types.number;
        default = null;
      };
      subdomain = lib.mkOption {
        description = "Alternative subdomain name, if not set default to service name";
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      https = lib.mkOption {
        description = "Whether the service uses HTTPS";
        type = lib.types.bool;
        default = false;
      };
    };
  };
in
{
  options.services.traefik-proxy = {
    enable = lib.mkEnableOption "traefik-proxy";
    services = lib.mkOption {
      description = "Attribute set of servies proxified";
      type = lib.types.attrsOf svc;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {

    sops.secrets."cloudflare.env" = {
      sopsFile = ../../secrets/cloudflare.hyper.env;
      key = "";
      format = "dotenv";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    networking.firewall.allowedUDPPorts = [ 443 ];

    services.traefik = {
      enable = true;
      environmentFiles = [ config.sops.secrets."cloudflare.env".path ];
      staticConfigOptions = {
        entryPoints = {
          http.address = ":80";
          https = {
            address = ":443";
            http.tls = {
              certResolver = "cloudflare";
              domains = [
                {
                  main = domain;
                  sans = [
                    "*.hyper.home.${domain}"
                  ];
                }
              ];
            };
          };
        };
        certificatesResolvers = {
          cloudflare.acme = {
            inherit email;
            caServer = "https://acme-v02.api.letsencrypt.org/directory";
            storage = "/var/lib/traefik/acme.json";
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
      dynamicConfigOptions = {
        http = {

          # routers
          routers = lib.mapAttrs (
            service: v:
            let
              subdomain = if isNull v.subdomain then service else v.subdomain;
            in
            {
              inherit service;
              rule = "Host(`${subdomain}.hyper.home.${domain}`)";
            }
          ) cfg.services;

          # services
          services = lib.mapAttrs (
            service: v:
            let
              port = if isNull v.port then config.services.${service}.port else v.port;
              protocol = if v.https then "https" else "http";
            in
            {
              loadBalancer = {
                servers = [
                  {
                    url = "${protocol}://localhost:${toString port}";
                  }
                ];
              } // (if v.https then {
                serversTransport = "${service}-transport";
              } else {});
            }
          ) cfg.services;

          # HTTPS transports for services that need it  
          serversTransports = lib.mapAttrs' (
            service: v: lib.nameValuePair "${service}-transport" {
              insecureSkipVerify = true;
            }
          ) (lib.filterAttrs (name: v: v.https) cfg.services);
        };
      };
    };
  };
}
