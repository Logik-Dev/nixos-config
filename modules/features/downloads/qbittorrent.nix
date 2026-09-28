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
      secretName = "cross-seed-secrets.json";
      # `builtins.hasAttr`, not `age.secrets ? secretName`: the `?` operator takes a
      # literal attrpath, so it would test for an attribute *named* "secretName".
      hasCrossSeedSecret = builtins.hasAttr secretName config.age.secrets;
      secretPath = config.age.secrets.${secretName}.path;
    in
    {
      traefik.services.qbittorrent = lib.mkIf vpnCfg.enable {
        port = webuiPort;
        # qBittorrent lives in the VPN namespace, so it does not listen on the
        # host's loopback: Traefik reaches it across the veth. glance derives its
        # check-url from this same field, so the dashboard follows automatically.
        host = vpnCfg.netns.namespaceAddress;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:qbittorrent";
      };

      notify.services = lib.mkIf vpnCfg.enable (
        [ "qbittorrent" ] ++ lib.optional hasCrossSeedSecret "qbittorrent-monitor"
      );

      # Join the VPN namespace. Declared here rather than in vpn.nix so the unit
      # is only ever referenced when this module is enabled (no phantom unit).
      vpn.airvpn.netns.services = lib.mkIf vpnCfg.enable (
        [ "qbittorrent" ] ++ lib.optional hasCrossSeedSecret "qbittorrent-monitor"
      );

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

      # Ordering and namespace membership come from the shared drop-in in vpn.nix.
      systemd.services.qbittorrent = lib.mkIf vpnCfg.enable {
        serviceConfig.UMask = lib.mkForce "0002";

        # qBittorrent enumerates interfaces at start-up and binds its listener
        # per address; it never re-binds. If wg0 is recreated underneath it — any
        # activation that restarts wireguard-wg0 — it keeps listening on lo and
        # the veth only, the forwarded port becomes unreachable from the outside,
        # and the ratio silently goes to zero with **no failed unit**. Verified:
        # `ss -tlnp` in the namespace showed no wg0 listener and ifconfig.co
        # reported reachable:false until a restart.
        #
        # partOf propagates the stop, wantedBy the start. Both are needed: partOf
        # alone does not pull the unit back up — the exact asymmetry that once
        # silently dropped the kill-switch after the Prowlarr backup (cb6d146).
        partOf = [ "wireguard-wg0.service" ];
        wantedBy = [ "wireguard-wg0.service" ];
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

      # Ratio health. Every pre-existing alert covers *reachability* (tunnel up,
      # listener bound on wg0) and all of them were green while qBittorrent
      # uploaded at exactly 10 KiB/s for days: the alternative speed limits had
      # been switched on by hand (the "turtle" button) with the scheduler
      # disabled, so nothing was ever going to switch them back off. No failed
      # unit, no unreachable port, a perfectly healthy dashboard, and a ratio
      # pinned at 0.03. Same class of silent failure as the ordering cycle in
      # vpn.nix — the service is up and doing nothing useful — so it gets the
      # same treatment: a metric, an alert, and a dead-man switch.
      #
      # Runs INSIDE the namespace (via netns.services below) because the WebUI is
      # reachable at 127.0.0.1 only from there; the host side would have to go
      # through the veth and authenticate against Authelia.
      systemd.services.qbittorrent-monitor = lib.mkIf (vpnCfg.enable && hasCrossSeedSecret) {
        description = "qBittorrent ratio/throttle metrics";
        # Ordering and namespace membership come from the shared drop-in in vpn.nix.
        after = [ "qbittorrent.service" ];
        wants = [ "qbittorrent.service" ];
        path = with pkgs; [
          curl
          coreutils
          gawk
          gnugrep
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          # `set +e` first, and load-bearing for the same reason as in vpn.nix:
          # NixOS prepends its own `set -e`, and an early abort would leave the
          # previous .prom in place — a throttled client reporting yesterday's
          # healthy ceiling forever. No `-u` either. Every command below must be
          # allowed to fail and still reach the write at the end.
          set +e

          dir=/var/lib/node-exporter-textfile
          file="$dir/qbittorrent.prom"
          tmp="$file.tmp"
          base="http://127.0.0.1:${toString webuiPort}"
          jar=$(mktemp)

          # Credentials come from the cross-seed secret: the same qBittorrent
          # account cross-seed and freeleech-farmer already use (hence the
          # mkIf on that secret). The password is stored URL-encoded there, so
          # it is passed through with --data-raw rather than re-encoded.
          raw=$(grep -o 'qbittorrent:http://[^"]*' ${secretPath} 2>/dev/null | head -1)
          raw=''${raw#qbittorrent:http://}
          creds=''${raw%@*}
          user=''${creds%%:*}
          pass=''${creds#*:}

          curl -s -c "$jar" --data-raw "username=$user&password=$pass" \
            -H "Referer: $base" "$base/api/v2/auth/login" >/dev/null 2>&1

          # Ground truth for "the scrape worked": a login that returns 200 with an
          # empty body still yields an unusable session, so validate on real data
          # instead of on the login response.
          prefs=$(curl -s -b "$jar" "$base/api/v2/app/preferences" 2>/dev/null)
          case "$prefs" in
            *'"up_limit"'*) ok=1 ;;
            *) ok=0 ;;
          esac

          # Pull one integer field out of a JSON blob. Anchored on the closing
          # quote so "uploaded" cannot match "uploaded_session".
          getnum() {
            printf '%s' "$1" | tr ',' '\n' \
              | grep -oE "\"$2\":-?[0-9]+" | head -1 | cut -d: -f2
          }
          num() { case "''${1:-}" in "" | *[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

          up_limit=$(num "$(getnum "$prefs" up_limit)")
          alt_up_limit=$(num "$(getnum "$prefs" alt_up_limit)")

          mode=$(curl -s -b "$jar" "$base/api/v2/transfer/speedLimitsMode" 2>/dev/null)
          case "$mode" in 1) alt_active=1 ;; *) alt_active=0 ;; esac

          # The number that actually decides the ratio: whichever ceiling is in
          # force right now. 0 means unlimited, which is why the alert on this
          # metric has to exclude 0 explicitly.
          if [ "$alt_active" = 1 ]; then
            effective=$alt_up_limit
          else
            effective=$up_limit
          fi

          xfer=$(curl -s -b "$jar" "$base/api/v2/transfer/info" 2>/dev/null)
          sess_up=$(num "$(getnum "$xfer" up_info_data)")
          sess_dl=$(num "$(getnum "$xfer" dl_info_data)")

          tor=$(curl -s -b "$jar" "$base/api/v2/torrents/info" 2>/dev/null)
          total=$(printf '%s' "$tor" | grep -o '"hash":"' | wc -l)
          seeding=$(printf '%s' "$tor" \
            | grep -oE '"state":"(uploading|stalledUP|forcedUP|queuedUP)"' | wc -l)
          uploaded=$(printf '%s' "$tor" | tr '}' '\n' \
            | grep -oE '"uploaded":[0-9]+' | cut -d: -f2 | awk '{s+=$1} END {print s+0}')
          downloaded=$(printf '%s' "$tor" | tr '}' '\n' \
            | grep -oE '"downloaded":[0-9]+' | cut -d: -f2 | awk '{s+=$1} END {print s+0}')

          {
            printf 'qbt_scrape_success %s\n' "$ok"
            printf 'qbt_alt_speed_limits_active %s\n' "$alt_active"
            printf 'qbt_up_limit_bytes %s\n' "$up_limit"
            printf 'qbt_alt_up_limit_bytes %s\n' "$alt_up_limit"
            printf 'qbt_up_limit_effective_bytes %s\n' "$effective"
            printf 'qbt_session_uploaded_bytes %s\n' "$sess_up"
            printf 'qbt_session_downloaded_bytes %s\n' "$sess_dl"
            printf 'qbt_uploaded_bytes %s\n' "$(num "$uploaded")"
            printf 'qbt_downloaded_bytes %s\n' "$(num "$downloaded")"
            printf 'qbt_torrents_total %s\n' "$(num "$total")"
            printf 'qbt_torrents_seeding %s\n' "$(num "$seeding")"
            printf 'qbt_monitor_timestamp_seconds %s\n' "$(date +%s)"
          } > "$tmp"
          mv -f "$tmp" "$file"
          rm -f "$jar"
        '';
      };

      systemd.timers.qbittorrent-monitor = lib.mkIf (vpnCfg.enable && hasCrossSeedSecret) {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/5";
          RandomizedDelaySec = "1m";
          Persistent = true;
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
