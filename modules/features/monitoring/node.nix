_: {
  flake.modules.nixos.node =
    { config, lib, ... }:
    let
      # `SystemdUnitFailed` (prometheus-alerts.nix) can only fire for units this
      # collector actually exports, and the hand-written list below had drifted
      # from notify.services: 15 of the 73 notified units were invisible to it —
      # qbittorrent, qbittorrent-monitor, unifi, vpn-monitor, tailscaled, ollama,
      # glance, cross-seed, freeleech-farmer, audiobookshelf, pg-dumpall,
      # pgbackrest-{default-weekly,metrics,stanza-create}, podman-bindery. For
      # those, notify-failure was the *only* channel, and it is the one that used
      # to lose messages (docs/notifications-plan.md §2.4).
      #
      # Union, not replacement: these prefixes also cover units that are watched
      # without being notified (ntfy itself, restic-verify,
      # postgres-restore-drill, btrfs-scrub, the per-source restic timers), so
      # dropping them would trade one blind spot for another.
      watchedPrefixes = [
        "traefik"
        "prometheus"
        "grafana"
        "alertmanager"
        "mosquitto"
        "zigbee2mqtt"
        "ntfy"
        "smartd"
        "postgresql"
        "adguardhome"
        "authelia"
        "cf-ddns"
        "vaultwarden"
        "jellyfin"
        "seerr"
        "radarr"
        "sonarr"
        "prowlarr"
        "sabnzbd"
        "immich"
        "restic"
        "rankoder"
        "mealie"
        "n8n"
        "paperless"
        "tika"
        "gotenberg"
        "podman-immich-ml"
        "btrfs-scrub"
        "snapraid"
        "syncthing"
        "restic-verify"
        "postgres-restore-drill"
      ];

      # The collector matches the full unit name, hence the trailing `.*`: every
      # alternative therefore behaves as a prefix, which is why a bare `authelia`
      # already covers `authelia-main` — and why a notified unit that starts with
      # one of the prefixes above would only lengthen the regex.
      alreadyCovered = unit: lib.any (prefix: lib.hasPrefix prefix unit) watchedPrefixes;
      unitInclude = "(${
        lib.concatStringsSep "|" (
          watchedPrefixes ++ lib.filter (u: !alreadyCovered u) config.notify.services
        )
      }).*";
    in
    {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9100;
        enabledCollectors = [
          "systemd"
          "hwmon"
          "processes"
          "filesystem"
          "textfile"
        ];
        extraFlags = [
          "--collector.systemd.unit-include=${unitInclude}"
          "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|run|var/lib/docker/.+|var/lib/containers/storage/.+)(/|$)"
          "--collector.netclass.ignored-devices=^(veth|br-|docker|virbr|tun|tap).*"
          "--collector.textfile.directory=/var/lib/node-exporter-textfile"
        ];
      };

      systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

      notify.services = [ "prometheus-node-exporter" ];
    };
}
