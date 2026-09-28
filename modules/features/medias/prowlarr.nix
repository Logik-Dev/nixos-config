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
        # Reached across the veth once Prowlarr moves into the VPN namespace.
        # Its Postgres access is unaffected: _servarr.nix uses the Unix socket,
        # which is a filesystem object and ignores network namespaces.
        host = lib.mkIf (
          config.vpn.airvpn.enable && config.vpn.airvpn.isolation == "netns"
        ) config.vpn.airvpn.netns.namespaceAddress;
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

      # Indexer queries must exit through the same IP as qBittorrent (tracker
      # consistency), so Prowlarr joins the namespace too. Inert in "uid" mode.
      vpn.airvpn.netns.services = lib.mkIf config.vpn.airvpn.enable [ "prowlarr" ];

      # DynamicUser + StateDirectory: /var/lib/prowlarr is a symlink to
      # /var/lib/private/prowlarr, so back up the real path. Indexer configs +
      # API key (config.xml); the DB itself is in postgres.
      backups.sources.prowlarr = {
        paths = [ "/var/lib/private/prowlarr" ];
      };
    };
}
