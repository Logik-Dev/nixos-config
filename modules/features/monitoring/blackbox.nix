_: {
  flake.modules.nixos.blackbox =
    { pkgs, ... }:
    {
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
                # 401/403 count as "up": apps with their own auth (Immich,
                # Jellyfin, Vaultwarden) legitimately answer that way without
                # credentials. Limitation: for services behind Authelia the
                # probe follows the redirect and validates the portal, not the
                # backend — backend health there is covered by Glance's direct
                # check-url probes.
                valid_status_codes: [200, 301, 302, 401, 403]
                method: GET
                follow_redirects: true
        '';
      };

      notify.services = [ "prometheus-blackbox-exporter" ];
    };
}
