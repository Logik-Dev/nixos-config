_: {
  flake.modules.nixos.notification =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.notify;
      pushNtfy = import ./lib/_ntfy.nix { inherit pkgs; };
    in
    {
      options.notify.services = lib.mkOption {
        description = "List of services generating notifications on failure";
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };

      config = {
        # FAC-5: `notify.services` is a free-form list and this module creates the
        # onFailure unit itself, so a typo silently produces an empty,
        # never-started unit (a dead alert). A ghost unit is all-defaults apart
        # from our `onFailure`, so assert every listed name carries real content
        # (a description, a script, or a non-empty serviceConfig). Real units
        # backed by `systemd.packages` (e.g. tailscaled) still have a populated
        # serviceConfig from the NixOS overrides.
        assertions = map (name: {
          assertion =
            let
              s = config.systemd.services.${name};
            in
            s.description != "" || s.script != "" || s.serviceConfig != { };
          message = "notify.services: '${name}' matches no real systemd service (typo / ghost unit, cf. FAC-5).";
        }) cfg.services;

        traefik.services.ntfy = {
          port = 2586;
          category = "Supervision";
          icon = "di:ntfy";
          # Read-only from the internet: publishers post from localhost
          # (bypassing Traefik), so the public vhost never needs POST/PUT.
          # Closes anonymous external writes to the alert topics.
          methods = [
            "GET"
            "HEAD"
            "OPTIONS"
          ];
        };

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
                  source ${pushNtfy}

                  SERVICE="$1"
                  LOCKFILE="/run/notify-failure-''${SERVICE}.lock"

                  # Don't repeat a notification sent during the last minute.
                  # /run (not /tmp): root-owned state on tmpfs, no symlink games.
                  now="$(date +%s)"
                  if [ -f "$LOCKFILE" ]; then
                    last="$(cat "$LOCKFILE" 2>/dev/null || echo 0)"
                    case "$last" in "" | *[!0-9]*) last=0 ;; esac
                    [ $((now - last)) -lt 60 ] && exit 0
                  fi

                  printf '%s\n' "$now" > "$LOCKFILE"

                  LOGS=$(${pkgs.systemd}/bin/journalctl -u "$SERVICE" -n 30 --no-pager -o short-monotonic 2>/dev/null \
                    | grep -v ' systemd\[1\]: ' \
                    | tail -c 3800)

                  printf '%s' "$LOGS" | push_ntfy service-failure "Homelab Alert" warning high
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
                  # Restore-drill heartbeat/results (formatted, success + failure).
                  ${ntfy} access everyone backup-verify write-only

                  # Read-only account for the phone (password from agenix).
                  # add is a no-op if the user exists; change-pass keeps the
                  # stored hash in sync when the secret is rotated (the old
                  # `|| true` silently kept a stale password forever).
                  READER_PW="$(cat ${config.age.secrets."ntfy-reader-pw".path})"
                  NTFY_PASSWORD="$READER_PW" ${ntfy} user add reader 2>/dev/null || true
                  NTFY_PASSWORD="$READER_PW" ${ntfy} user change-pass reader >/dev/null
                  ${ntfy} access reader '*' read-only
                '';
              };
          }

          (lib.genAttrs cfg.services (_name: {
            onFailure = [ "notify-failure@%n.service" ];
          }))
        ];
      };
    };
}
