_: {
  flake.modules.nixos.slskd =
    {
      config,
      lib,
      ...
    }:
    let
      vpnCfg = config.vpn.airvpn;
    in
    {
      # The Soulseek listener must be reachable from the outside; on AirVPN the
      # forwarded port has to be requested in the Client Area (public = local),
      # exactly like qBittorrent's.
      assertions = [
        {
          assertion = vpnCfg.forwardedPortSlskd != null;
          message = "slskd requires vpn.airvpn.forwardedPortSlskd (request the port on AirVPN, public = local).";
        }
      ];

      services.slskd = {
        enable = true;
        # No default on this option, and non-null pulls nginx — we have Traefik.
        domain = null;
        # Must carry both credential sets: SLSKD_SLSK_* (Soulseek network) and
        # SLSKD_USERNAME/SLSKD_PASSWORD (WebUI).
        environmentFile = config.age.secrets."slskd.env".path;
        # Useless: the namespace has no input firewall — AirVPN forwards in.
        openFirewall = false;
        # cf. _media-service: beets (logikdev) reads the finished downloads.
        group = "media";
        settings = {
          web.port = 5030;
          soulseek.listen_port = vpnCfg.forwardedPortSlskd;
          directories.downloads = "/mnt/storage/medias/downloads/slskd";
          directories.incomplete = "/mnt/storage/medias/downloads/slskd-incomplete";
          shares.directories = [ "/mnt/storage/medias/musique" ];
        };
      };

      # Like qbittorrent.nix/prowlarr.nix: only reference the unit when the VPN
      # is enabled (no phantom unit), and reach the WebUI across the veth.
      vpn.airvpn.netns.services = lib.mkIf vpnCfg.enable [ "slskd" ];
      traefik.services.slskd = lib.mkIf vpnCfg.enable {
        port = 5030;
        host = vpnCfg.netns.namespaceAddress;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:soulseek";
      };
      notify.services = [ "slskd" ];

      backups.sources.slskd = {
        paths = [ "/var/lib/slskd" ];
      };

      # ReadWritePaths does not create the directories, and slskd runs
      # slskd:media. 2775 + UMask 0002 so beets can read behind (group media).
      systemd.tmpfiles.rules = [
        "d /mnt/storage/medias/downloads/slskd 2775 slskd media - -"
        "d /mnt/storage/medias/downloads/slskd-incomplete 2775 slskd media - -"
      ];
      systemd.services.slskd.serviceConfig.UMask = lib.mkForce "0002";
    };
}
