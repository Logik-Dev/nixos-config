_: {
  flake.modules.nixos.cross-seed =
    { config, lib, ... }:
    {
      # Enabled as soon as the agenix secret exists. Create it with:
      #   agenix -e secrets/hosts/hyper/cross-seed-secrets.json.age
      # then `nix run .#agenix-rekey` and `git add`.
      # The secret must contain: apiKey, torznab, torrentClients.
      config = lib.mkIf (config.age.secrets ? "cross-seed-secrets.json") {
        services.cross-seed = {
          enable = true;
          user = "cross-seed";
          group = "media";
          useGenConfigDefaults = true;
          settingsFile = config.age.secrets."cross-seed-secrets.json".path;
          settings = {
            # Branch paths (not the mergerfs pool) so cross-seed can pick the
            # linkDir on the same device as each file and hardlink works.
            dataDirs = [
              "/mnt/medias1/medias"
              "/mnt/medias2/medias"
            ];
            linkDirs = [
              "/mnt/medias1/cross-seed-links"
              "/mnt/medias2/cross-seed-links"
            ];
            # mergerfs reports its own st_dev for pooled paths, so hardlinks
            # can't be validated against the branch linkDirs. symlinks have no
            # same-device requirement and qBittorrent seeds through them.
            linkType = "symlink";
            matchMode = "partial";
            maxDataDepth = 3;
            # YggReborn recommends delay=5, but cross-seed enforces >= 30s.
            searchLimit = 300;
            searchCadence = "1 day";
            # useClientTorrents (default) uses the qBittorrent API instead of
            # torrentDir; setting both is rejected by cross-seed.
            host = "127.0.0.1";
            port = 2468;
          };
        };

        # qBittorrent (group media) must be able to create the files cross-seed
        # could not link (e.g. the .nfo absent from the library). Without a
        # group-writable umask the per-torrent link dirs are created 2755 and
        # qBittorrent gets EACCES -> torrents stuck in "error".
        systemd.services.cross-seed.serviceConfig.UMask = "0002";

        systemd.tmpfiles.rules = [
          "d /mnt/medias1/cross-seed-links 2775 cross-seed media - -"
          "d /mnt/medias2/cross-seed-links 2775 cross-seed media - -"
          # Fix link dirs created before the umask above (2755 -> 2775).
          "Z /mnt/medias1/cross-seed-links 2775 cross-seed media - -"
          "Z /mnt/medias2/cross-seed-links 2775 cross-seed media - -"
        ];

        notify.services = [ "cross-seed" ];

        # Join the VPN namespace (isolation = "netns"); inert in "uid" mode,
        # where cross-seed is covered by routedUsers instead. Declared here
        # rather than in vpn.nix so the unit is only ever referenced when this
        # module is actually enabled (no phantom unit, cf. FAC-5).
        vpn.airvpn.netns.services = [ "cross-seed" ];
      };
    };
}
