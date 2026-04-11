{

  flake.modules.nixos.vaultwarden =
    { config, ... }:
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

      traefik.services.vaultwarden.port = 8082;

      notify.services = [ "vaultwarden" ];

      services.vaultwarden = {
        enable = true;
        dbBackend = "postgresql";
        environmentFile = config.age.secrets."vaultwarden.env".path;
      };

    };
}
