_: {
  flake.modules.nixos.bindery =
    { config, ... }:
    let
      # Bindery's image is distroless and cannot switch users, so the UID must
      # be set at runtime (--user) and match the host owner of /config and the
      # media libraries. logikdev is uid 1000; media is gid 991.
      uid = 1000;
      gid = config.constants.media.gid;
    in
    {
      virtualisation.oci-containers.containers.bindery = {
        image = "ghcr.io/vavallee/bindery:latest";
        autoStart = true;
        extraOptions = [
          # host network: Bindery reaches Prowlarr (9696), qBittorrent (8090)
          # and SABnzbd (8088) on loopback. The NixOS firewall blocks external
          # access to 8787; Traefik proxies it from localhost.
          "--network=host"
          "--user=${toString uid}:${toString gid}"
          # Group-writable library/download files (matches _media-service).
          "--umask=0002"
        ];
        environment = {
          BINDERY_DATA_DIR = "/config";
          # Paths are host-identical: downloads and libraries are subpaths of a
          # single mount (see volumes). Bindery's importer hardlinks when the
          # completed download and the library share a filesystem *inside the
          # container*; separate bind mounts get different device IDs even when
          # they point at the same host fs, which would force a copy (double
          # disk, no torrent seeding). Matching the host paths also avoids any
          # download-client path remap (qBittorrent/SABnzbd report host paths).
          BINDERY_LIBRARY_DIR = "/mnt/storage/medias/books";
          BINDERY_AUDIOBOOK_DIR = "/mnt/storage/medias/audiobooks";
          BINDERY_DOWNLOAD_DIR = "/mnt/storage/medias/downloads";
          # Sanity checks (assert only, no user switching).
          BINDERY_PUID = toString uid;
          BINDERY_PGID = toString gid;
          # Prowlarr runs on loopback: indexer-provided download links point at
          # 127.0.0.1 and are rejected by the SSRF guard unless allowed.
          BINDERY_DOWNLOAD_ALLOW_LOOPBACK = "1";
          BINDERY_LOG_LEVEL = "info";
        };
        volumes = [
          "/mnt/ultra/bindery:/config"
          # One mount for downloads + both libraries so hardlinks work.
          "/mnt/storage/medias:/mnt/storage/medias"
        ];
      };

      systemd.tmpfiles.rules = [
        "d /mnt/ultra/bindery 2755 logikdev media - -"
      ];

      traefik.services.bindery = {
        port = 8787;
        # Web UI only (no native client) → forward-auth is fine.
        enableAuthelia = true;
        category = "Médias";
        icon = "di:bindery";
        title = "Bindery";
      };

      notify.services = [ "podman-bindery" ];

      backups.sources.bindery = {
        paths = [ "/mnt/ultra/bindery" ];
        # SQLite DB lives in /config: stop the container for a consistent copy.
        serviceName = "podman-bindery";
      };
    };
}
