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

      traefik.services.vaultwarden = {
        port = 8082;
        category = "Maison";
        icon = "di:vaultwarden";
      };

      notify.services = [ "vaultwarden" ];

      services.vaultwarden = {
        enable = true;
        dbBackend = "postgresql";
        environmentFile = config.age.secrets."vaultwarden.env".path;
      };

      # On-disk state: rsa_key.pem (JWT signing key — irreplaceable),
      # attachments/sends, plus a live db.sqlite3 (WAL). The postgres DB is
      # covered by the pg base-backup/WAL; here we stop the service during the
      # backup so the sqlite/rsa_key snapshot is consistent.
      backups.sources.vaultwarden = {
        paths = [ "/var/lib/vaultwarden" ];
      };

    };
}
