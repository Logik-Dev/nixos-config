{ ... }:
{

  flake.modules.nixos.vaultwarden =
    { config, hostSecret, ... }:
    {

      services.postgresql = {
        ensureDatabases = [ "vaultwarden" ];
        ensureUsers = [
          {
            name = "vaultwarden";
            ensureDBOwnership = true;
          }
        ];
      };

      age.secrets."vaultwarden.env".rekeyFile = hostSecret "vaultwarden.env";

      services.mytraefik.services.vaultwarden.port = 8082;

      services.vaultwarden = {
        enable = true;
        dbBackend = "postgresql";
        environmentFile = config.age.secrets."vaultwarden.env".path;
      };

    };
}
