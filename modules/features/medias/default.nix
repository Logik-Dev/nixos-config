{ inputs, ... }:
{
  flake.modules.nixos.seedbox =
    { pkgs, ... }:
    {

      users.groups.media.gid = 991;

      services.postgresql.initialScript = pkgs.writeText "ownership.sql" ''
        ALTER DATABASE "sonarr-main" OWNER TO sonarr;
        ALTER DATABASE "sonarr-logs" OWNER TO sonarr;
        ALTER DATABASE "radarr-main" OWNER TO radarr;
        ALTER DATABASE "radarr-logs" OWNER TO radarr;
        ALTER DATABASE "prowlarr-main" OWNER TO prowlarr;
        ALTER DATABASE "prowlarr-logs" OWNER TO prowlarr;
      '';

      systemd.tmpfiles.rules = [
        "d /mnt/storage 2755 logikdev media - -"
        "d /mnt/storage/medias 2755 logikdev media - -"
        "d /mnt/ultra 2755 logikdev media - -"
      ];

      imports = with inputs.self.modules.nixos; [
        #jackett
        jellyfin
        seerr
        prowlarr
        radarr
        sabnzbd
        sonarr
        #torrent
      ];
    };
}
