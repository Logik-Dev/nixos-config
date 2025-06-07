{ ... }:
{
  services.backups.enable = true;
  services.backups.configurations.docker = {
    source_directories = [ "/var/lib/containers/qBittorrent" ];
    services = [ "podman-qbittorrent" ];
  };
}
