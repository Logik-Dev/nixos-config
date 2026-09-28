_: {
  flake.modules.nixos.prowlarr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        (import ./lib/_servarr.nix { inherit pkgs; } {
          app = "prowlarr";
          mainDb = "prowlarr-main";
          logDb = "prowlarr-logs";
        })
      ];

      traefik.services.prowlarr = {
        port = 9696;
        # Prowlarr lives in the VPN namespace (indexer queries must exit through
        # the same IP as qBittorrent), so Traefik reaches it across the veth. Its
        # Postgres access is unaffected: _servarr.nix uses the Unix socket, which
        # is a filesystem object and ignores network namespaces.
        host = lib.mkIf config.vpn.airvpn.enable config.vpn.airvpn.netns.namespaceAddress;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:prowlarr";
      };

      # Keep the module's default dataDir (/var/lib/prowlarr). A custom one
      # makes nixpkgs bind-mount it at /var/lib/private/prowlarr and force the
      # source to root:root 0700, which the DynamicUser service cannot write
      # ("Access to the path '/var/lib/prowlarr/config.xml' is denied").
      services.prowlarr.enable = true;

      notify.services = [ "prowlarr" ];

      vpn.airvpn.netns.services = lib.mkIf config.vpn.airvpn.enable [ "prowlarr" ];

      # DynamicUser + StateDirectory: /var/lib/prowlarr is a symlink to
      # /var/lib/private/prowlarr, so back up the real path. Indexer configs +
      # API key (config.xml); the DB itself is in postgres.
      backups.sources.prowlarr = {
        paths = [ "/var/lib/private/prowlarr" ];
        # Definitions (4.7 MB) are indexer definitions Prowlarr re-syncs from
        # upstream, and logs (5 MB) churn daily. Small in absolute terms, but
        # they are the only things in this 9.7 MB state dir that change every
        # day — excluding them makes snapshots essentially free.
        exclude = [
          "/var/lib/private/prowlarr/Definitions"
          "/var/lib/private/prowlarr/logs"
        ];
      };
    };
}
