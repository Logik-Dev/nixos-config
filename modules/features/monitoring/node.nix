_: {
  flake.modules.nixos.node = {
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
        "--collector.systemd.unit-include=(traefik|prometheus|grafana|alertmanager|loki|alloy|mosquitto|zigbee2mqtt|ntfy|smartd|postgresql|adguardhome|authelia|cf-ddns|vaultwarden|jellyfin|seerr|radarr|sonarr|prowlarr|sabnzbd|immich|restic|rankoder|mealie|n8n|paperless|tika|gotenberg|podman-immich-ml|btrfs-scrub|snapraid|syncthing|restore-canary|postgres-restore-drill).*"
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|run|var/lib/docker/.+|var/lib/containers/storage/.+)(/|$)"
        "--collector.netclass.ignored-devices=^(veth|br-|docker|virbr|tun|tap).*"
        "--collector.textfile.directory=/var/lib/node-exporter-textfile"
      ];
    };

    systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

    notify.services = [ "prometheus-node-exporter" ];
  };
}
