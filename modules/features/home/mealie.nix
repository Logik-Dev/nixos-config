{ ... }:
let
  port = 9999;
in
{
  flake.modules.nixos.home = {
    traefik.services.mealie.port = port;
    services.mealie = {
      inherit port;
      enable = true;
      database.createLocally = true;
      settings = {
        ALLOW_SIGNUP = "false";
      };
    };
  };
}
