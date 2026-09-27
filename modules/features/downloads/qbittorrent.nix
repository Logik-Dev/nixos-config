_: {
  flake.modules.nixos.qbittorrent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      vpnCfg = config.vpn.airvpn;
      webuiPort = 8090;
    in
    {
      traefik.services.qbittorrent = lib.mkIf vpnCfg.enable {
        port = webuiPort;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:qbittorrent";
      };

      notify.services = lib.mkIf vpnCfg.enable [ "qbittorrent" ];

      backups.sources.qbittorrent = lib.mkIf vpnCfg.enable {
        paths = [ "/mnt/ultra/qbittorrent" ];
      };

      systemd.tmpfiles.rules = lib.mkIf vpnCfg.enable [
        "d /mnt/storage/medias/downloads 2755 logikdev media - -"
        "d /mnt/storage/medias/downloads/incomplete 2775 logikdev media - -"
        "d /mnt/storage/medias/downloads/movies 2775 logikdev media - -"
        "d /mnt/storage/medias/downloads/series 2775 logikdev media - -"
        "d /mnt/ultra/qbittorrent 2755 qbittorrent media - -"
      ];

      systemd.services.qbittorrent = lib.mkIf vpnCfg.enable {
        after = [
          "wireguard-wg0.service"
          "vpn-policy-routing.service"
          "vpn-killswitch.service"
        ];
        wants = [
          "wireguard-wg0.service"
          "vpn-policy-routing.service"
          "vpn-killswitch.service"
        ];
        serviceConfig.UMask = lib.mkForce "0002";
      };

      # Older manual experiments left files owned by logikdev in the profile
      # directory; qBittorrent aborts if it cannot create its config dirs.
      systemd.services.qbittorrent-permissions = lib.mkIf vpnCfg.enable {
        description = "Fix qBittorrent profile directory ownership";
        unitConfig.RequiresMountsFor = [ "/mnt/ultra/qbittorrent" ];
        before = [ "qbittorrent.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/chown -R qbittorrent:media /mnt/ultra/qbittorrent";
        };
      };

      services.qbittorrent = lib.mkIf vpnCfg.enable {
        enable = true;
        user = "qbittorrent";
        group = "media";
        profileDir = "/mnt/ultra/qbittorrent";
        inherit webuiPort;
        torrentingPort = vpnCfg.forwardedPort;
        # Keep qBittorrent.conf writable so UI changes persist across reboots.
        serverConfig = { };
        extraArgs = [ "--confirm-legal-notice" ];
      };
    };
}
