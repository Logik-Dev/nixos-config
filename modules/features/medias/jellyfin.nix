{
  flake.modules.nixos.seedbox = {
    services.reverse-proxy.vhosts.jellyfin.port = 8096;

    services.jellyfin = {
      enable = true;
      group = "media";
      dataDir = "/mnt/ultra/jellyfin";
    };
  };
}
