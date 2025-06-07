{ ... }:
{
  services.backups.enable = true;
  services.backups.configurations.vaultwarden = {
    source_directories = [ "/var/lib/vaultwarden" ];
    services = [ "vaultwarden" ];
  };
}
