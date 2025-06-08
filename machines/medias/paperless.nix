{ config, username, ... }:
{

  sops.secrets.paperless = {
    sopsFile = ../../secrets/medias.yaml;
    owner = config.services.paperless.user;
  };

  # photos volume mounted by incus
  systemd.tmpfiles.settings = {
    "10-photos-immich" = {
      "/mnt/photos/documents" = {
        d = {
          group = "media";
          mode = "750";
          user = config.services.paperless.user;
        };
      };
    };
  };

  services.paperless = {
    enable = true;
    passwordFile = config.sops.secrets.paperless.path;
    settings.PAPERLESS_ADMIN_USER = username;
    mediaDir = "/mnt/photos/documents";
    database.createLocally = true;
    configureTika = true;
  };

  networking.firewall.allowedTCPPorts = [ 28981 ];

}
