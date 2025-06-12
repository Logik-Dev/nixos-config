{ ... }:
{
  services.backups.enable = true;
  services.backups.configurations.vaultwarden = {
    source_directories = [ "/var/lib/vaultwarden/attachments" ];
    postgresql_databases = [
      {
        name = "vaultwarden";
        username = "vaultwarden";
      }
    ];
  };
}
