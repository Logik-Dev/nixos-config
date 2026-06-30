{ pkgs, ... }:
{
  flake.modules.nixos.blackbox = {
    services.prometheus.exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9115;
      configFile = pkgs.writeText "blackbox.yml" ''
        modules:
          http_2xx:
            prober: http
            timeout: 5s
            http:
              valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
              valid_status_codes: [200, 301, 302, 401, 403]
              method: GET
              follow_redirects: true
          icmp:
            prober: icmp
            timeout: 5s
      '';
    };

    notify.services = [ "prometheus-blackbox-exporter" ];
  };
}
