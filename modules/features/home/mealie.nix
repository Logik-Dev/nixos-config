{ ... }:
let
  port = 9999;
in
{
  flake.modules.nixos.mealie = {
    traefik.services.mealie = {
      port = port;
      enableAuthelia = true;
      category = "Maison";
      icon = "di:mealie";
    };
    notify.services = [ "mealie" ];
    services.mealie = {
      inherit port;
      enable = true;
      # Traefik is the only entry point; don't listen on the LAN/tailnet.
      listenAddress = "127.0.0.1";
      database.createLocally = true;
      settings = {
        ALLOW_SIGNUP = "false";
      };
    };
    # Recipe images and app state (DynamicUser: /var/lib/mealie is a symlink
    # to /var/lib/private/mealie). The DB itself is in postgres.
    backups.sources.mealie = {
      paths = [ "/var/lib/private/mealie" ];
    };
  };
}
