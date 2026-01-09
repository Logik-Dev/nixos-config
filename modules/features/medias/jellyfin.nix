{
  flake.modules.nixos.seedbox = {
    services.mytraefik.services.jellyfin.port = 8096;

    services.jellyfin = {
      enable = true;
      group = "media";
      dataDir = "/mnt/ultra/jellyfin";
    };
  };
}
