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
        # In netns mode qBittorrent no longer listens on the host's loopback:
        # Traefik reaches it across the veth. glance derives its check-url from
        # this same field, so the dashboard follows automatically.
        host = lib.mkIf (vpnCfg.isolation == "netns") vpnCfg.netns.namespaceAddress;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:qbittorrent";
      };

      notify.services = lib.mkIf vpnCfg.enable [ "qbittorrent" ];

      # Join the VPN namespace (isolation = "netns"); inert in "uid" mode, where
      # qBittorrent is covered by routedUsers instead.
      vpn.airvpn.netns.services = lib.mkIf vpnCfg.enable [ "qbittorrent" ];

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

      # In netns mode the ordering and the namespace membership come from the
      # shared drop-in in vpn.nix; the UID units below do not exist there.
      systemd.services.qbittorrent = lib.mkIf vpnCfg.enable (
        {
          serviceConfig.UMask = lib.mkForce "0002";
        }
        // lib.optionalAttrs (vpnCfg.isolation == "netns") {
          # qBittorrent enumerates interfaces at start-up and binds its listener
          # per address; it never re-binds. If wg0 is recreated underneath it —
          # any activation that restarts wireguard-wg0 — it keeps listening on lo
          # and the veth only, the forwarded port becomes unreachable from the
          # outside, and the ratio silently goes to zero with **no failed unit**.
          # Verified: `ss -tlnp` in the namespace showed no wg0 listener and
          # ifconfig.co reported reachable:false until a restart.
          #
          # partOf propagates the stop, wantedBy the start. Both are needed:
          # partOf alone does not pull the unit back up — the exact asymmetry
          # that silently dropped the kill-switch after the Prowlarr backup
          # (cf. AGENTS.md, commit cb6d146).
          partOf = [ "wireguard-wg0.service" ];
          wantedBy = [ "wireguard-wg0.service" ];
        }
        // lib.optionalAttrs (vpnCfg.isolation == "uid") {
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
        }
      );

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
