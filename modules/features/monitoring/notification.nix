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
            # Deny everything by default; grants are provisioned by the
            # ntfy-setup oneshot below (anonymous write-only on the alert
            # topics, read-only for the phone). Closes anonymous READ of the
            # alert topics, which carry system log excerpts.
            auth-default-access = "deny-all";
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

            # Provision ntfy access control on top of auth-default-access=deny-all.
            ntfy-setup =
              let
                ntfy = "${config.services.ntfy-sh.package}/bin/ntfy";
              in
              {
                description = "Provision ntfy access control (grants)";
                after = [ "ntfy-sh.service" ];
                requires = [ "ntfy-sh.service" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                environment = {
                  NTFY_AUTH_FILE = config.services.ntfy-sh.settings.auth-file;
                  NTFY_AUTH_DEFAULT_ACCESS = "deny-all";
                };
                script = ''
                  set -eu
                  # Publishers (alertmanager-ntfy, notify-failure) post from
                  # localhost; anonymous write-only lets them publish without
                  # credentials while anonymous READ stays denied.
                  ${ntfy} access everyone homelab-alerts write-only
                  ${ntfy} access everyone service-failure write-only

                  # Read-only account for the phone (password from agenix).
                  # Change later with: ntfy user change-pass reader
                  NTFY_PASSWORD="$(cat ${config.age.secrets."ntfy-reader-pw".path})" \
                    ${ntfy} user add reader 2>/dev/null || true
                  ${ntfy} access reader '*' read-only
                '';
              };
          }

          (lib.genAttrs cfg.services (name: {
            onFailure = [ "notify-failure@%n.service" ];
          }))
        ];
      };
    };
}
