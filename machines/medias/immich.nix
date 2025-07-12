{
  config,
  lib,
  domain,
  pkgs,
  hosts,
  ...
}:

{
  environment.systemPackages = [ pkgs.immich-cli ];

  # photos volume mounted by incus
  systemd.tmpfiles.settings = {
    "10-photos-immich" = {
      "/mnt/photos/immich" = {
        d = {
          group = "media";
          mode = "750";
          user = config.services.immich.user;
        };
      };
    };
  };

  users.users.${config.services.immich.user}.extraGroups = [
    "media"
    "render"
    "video"
  ];

  services.immich = {
    enable = true;
    mediaLocation = "/mnt/photos/immich";
    settings.server.externalDomain = "https://photos.${domain}";
    openFirewall = true;
    accelerationDevices = null; # all devices
    environment = {
      IMMICH_HOST = lib.mkForce "0.0.0.0";
      IMMICH_TRUSTED_PROXIES = "${hosts.proxy.ipv4}";
      #DB_SKIP_MIGRATIONS = "true";
    };
  };
}
