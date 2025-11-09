{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) domain;

  flake.modules.nixos.nginx =
    { lib, config, ... }:
    with lib;
    let
      cfg = config.services.reverse-proxy;
      host = config.networking.hostName;

      vhost = types.submodule {
        options = {
          subdomain = mkOption {
            description = "Alternative subdomain name, if not set default to vhost name";
            type = types.nullOr types.str;
            default = null;
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

          enableWebsockets = mkOption {
            description = "Proxy websockets";
            type = types.bool;
            default = false;
          };

          extraConfig = mkOption {
            description = "Extra configuration";
            type = types.nullOr types.lines;
            default = null;
          };
        };
      };

    in
    {

      imports = with inputs.self.modules.nixos; [ acme ];

      options.services.reverse-proxy = {
        enable = mkEnableOption "Enable nginx reverse-proxy";
        vhosts = mkOption {
          description = "Attribute set of virtual hosts";
          type = types.attrsOf vhost;
          default = { };
        };
      };

      config = mkIf cfg.enable {

        # acme
        services.acme.enable = true;

        # needed for nginx to be able to read certificates
        users.users.nginx.extraGroups = [ "acme" ];

        networking.firewall.allowedTCPPorts = [
          443
          80
        ];

        services.nginx = {
          enable = true;

          # Active les logs d'accès et d'erreur globaux
          virtualHosts = mapAttrs' (
            vhost: value:
            nameValuePair "${vhost}.${host}.${domain}" {
              listenAddresses = [ "192.168.10.100" ];
              useACMEHost = "${host}.${domain}";
              forceSSL = true;
              locations."/" = {
                proxyPass = "${value.protocol}://localhost:${toString value.port}";
                proxyWebsockets = value.enableWebsockets;
                recommendedProxySettings = true;
                extraConfig = lib.mkIf (value.extraConfig != null) value.extraConfig;
              };
            }

          ) cfg.vhosts;
        };
      };
    };
in
{
  inherit flake;
}
