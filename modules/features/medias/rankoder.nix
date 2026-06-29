{ inputs, ... }: {
  flake.modules.nixos.rankoder = { config, ... }: {
    imports = [ inputs.rankoder.nixosModules.default ];

    systemd.tmpfiles.rules = [
      # Parent owned by logikdev (same owner as /mnt/storage/medias) so
      # systemd-tmpfiles can descend into it to create the rankoder-owned
      # subdirs below; a logikdev -> rankoder ownership change here is rejected
      # as an "unsafe path transition". rankoder traverses via the media group.
      "d /mnt/storage/medias/rankoder 0750 logikdev media - -"
      "d /mnt/storage/medias/rankoder/retention 0750 rankoder media - -"
      "d /mnt/storage/medias/rankoder/temp 0750 rankoder media - -"
    ];

    traefik.services.rankoder.port = 8765;

    services.rankoder = {
      enable = true;
      group = "media";
      environmentFile = config.age.secrets."rankoder.env".path;
      jellyfinUrl = "https://jellyfin.hyper.logikdev.fr";
      radarrUrl = "https://radarr.hyper.logikdev.fr";
      sonarrUrl = "https://sonarr.hyper.logikdev.fr";
      mediaPaths = [ "/mnt/storage/medias" ];
      tmpDir = "/mnt/storage/medias/rankoder/temp";
      retentionDir = "/mnt/storage/medias/rankoder/retention";
      minVmaf = 92.0;
      hardwareAcceleration = true;
      mqtt.username = "homeassistant";
      http = {
        enable = true;
        address = "0.0.0.0";
      };
    };
  };
}
