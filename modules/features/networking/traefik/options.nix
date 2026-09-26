{ inputs, ... }:
let
  optionsModule =
    {
      lib,
      ...
    }:
    {
      imports = [ inputs.self.modules.nixos.authelia ];

      options.traefik.services = lib.mkOption {
        description = "Attribute set of services";
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              host = lib.mkOption {
                description = "Host IP";
                type = lib.types.str;
                default = "localhost";
              };

              port = lib.mkOption {
                description = "Port which the service is listening on";
                type = lib.types.nullOr lib.types.number;
                default = null;
              };

              protocol = lib.mkOption {
                description = "Protocol to use http or https";
                type = lib.types.enum [
                  "http"
                  "https"
                ];
                default = "http";
              };

              methods = lib.mkOption {
                description = "If non-empty, restrict the router to these HTTP methods (e.g. read-only public routes)";
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [
                  "GET"
                  "HEAD"
                  "OPTIONS"
                ];
              };

              enableAuthelia = lib.mkOption {
                description = "Wheter to enable authelia";
                type = lib.types.bool;
                default = false;
              };

              insecureSkipVerify = lib.mkOption {
                description = "Skip TLS certificate verification for this backend (e.g. self-signed certs)";
                type = lib.types.bool;
                default = false;
              };

              category = lib.mkOption {
                description = "Glance dashboard category (null = excluded from glance)";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };

              icon = lib.mkOption {
                description = "Glance widget icon (e.g. di:jellyfin)";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };

              title = lib.mkOption {
                description = "Glance widget title (defaults to service key)";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = { };
      };
    };
in
{
  flake.modules.nixos.traefik.imports = [ optionsModule ];
}
