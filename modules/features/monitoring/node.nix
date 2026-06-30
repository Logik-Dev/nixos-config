{ ... }:
{
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
      ];
      extraFlags = [
        "--collector.systemd.unit-include=(traefik|prometheus|grafana|alertmanager|loki|promtail|mosquitto|zigbee2mqtt|ntfy|smartd|nginx|postgresql|adguardhome|authelia|cloudflared|cf-ddns|vaultwarden|jellyfin|seerr|radarr|sonarr|prowlarr|sabnzbd|immich|rustfs|restic).*"
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|run|var/lib/docker/.+|var/lib/containers/storage/.+)(/|$)"
        "--collector.netclass.ignored-devices=^(veth|br-|docker|virbr|tun|tap).*"
      ];
    };

    notify.services = [ "prometheus-node-exporter" ];
  };
}
