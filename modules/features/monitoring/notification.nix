{ ... }:
{
  flake.modules.nixos.monitoring =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.notify;
    in
    {
      options.notify.services = lib.mkOption {
        description = "List of services generating notifications on failure";
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };

      config = {
        traefik.services.ntfy.port = 2586;

        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = "https://ntfy.hyper.logikdev.fr";
            listen-http = ":2586";
            behind-proxy = true;
            auth-file = "/var/lib/ntfy-sh/auth.db";
            cache-file = "/var/lib/ntfy-sh/cache.db";
            upstream-base-url = "https://ntfy.sh";
          };
        };

        systemd.services = lib.mkMerge [
          {
            "notify-failure@" =
              let
                script = pkgs.writeShellScript "notify-failure" ''
                  SERVICE="$1"
                  LOCKFILE="/tmp/notify-failure-''${SERVICE}.lock"

                  # Don't repeat notification if it was sent during last minute
                  if [ -f "$LOCKFILE" ] && [ $(( $(date +%s) - $(cat "$LOCKFILE") )) -lt 60 ]; then
                    exit 0
                  fi

                  echo "$(date +%s)" > "$LOCKFILE"

                  LOGS=$(${pkgs.systemd}/bin/journalctl -u "$SERVICE" -n 30 --no-pager -o short-monotonic 2>/dev/null \
                    | grep -v ' systemd\[1\]: ' \
                    | tail -c 3800)

                  ${pkgs.curl}/bin/curl -s \
                    -H "Title: Homelab Alert" \
                    -H "Priority: high" \
                    -H "Tags: warning" \
                    -d "$LOGS" \
                    "http://localhost:2586/service-failure"
                '';
              in
              {
                description = "Notify ntfy on service failure for %i";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${script} %i";
                };

              };
          }

          (lib.genAttrs cfg.services (name: {
            onFailure = [ "notify-failure@%n.service" ];
          }))
        ];
      };
    };
}
