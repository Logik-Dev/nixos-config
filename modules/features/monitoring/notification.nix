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
      # Kept in sync with the default baked into _ntfy.nix: the publishers only
      # write here, the drain below is the only reader.
      spoolDir = "/var/lib/ntfy-spool";
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
                # Same scheme as the Traefik routers (`<service>.<host>.<domain>`),
                # so the tap target follows the host it is generated for.
                dashboardUrl = "https://home.${config.networking.hostName}.${config.constants.domain}";
                grafanaUrl = "https://grafana.${config.networking.hostName}.${config.constants.domain}";
                script = pkgs.writeShellScript "notify-failure" ''
                  source ${pushNtfy}

                  # systemd passes MONITOR_* to the ExecStart of any unit pulled in
                  # by OnFailure= (systemd.exec(5)); verified on systemd 261. They
                  # are the whole reason this notifier can name the service and the
                  # kind of failure, and scope the body to the invocation that
                  # actually failed — the previous version had none of that and sent
                  # a constant "Homelab Alert" title with 30 lines of raw journal
                  # (docs/notifications-plan.md §2.2).
                  #
                  # They are only passed because every service gets its OWN template
                  # instance (notify-failure@%n): systemd drops them when several
                  # units share one OnFailure= target, so the template is
                  # load-bearing, not a stylistic choice. %i stays as the fallback
                  # for a manual `systemctl start notify-failure@foo.service`.
                  UNIT="''${MONITOR_UNIT:-$1}"
                  SERVICE="''${UNIT%.service}"
                  RESULT="''${MONITOR_SERVICE_RESULT:-inconnu}"
                  STATUS="''${MONITOR_EXIT_STATUS:-}"
                  INVOCATION="''${MONITOR_INVOCATION_ID:-}"

                  # Per-incident cap, replacing the flat 60 s lock. That lock let
                  # a unit restarting every 8 s produce a notification every
                  # 60 s — 60 an hour, indefinitely, which is how the 2026-09-02
                  # storm reached 103 notifications for n8n alone.
                  #
                  # Escalating hold instead: notify at once, then at most once per
                  # 5 min, then once per 30 min, each notification carrying how
                  # many failures it stands for. An hour of quiet closes the
                  # incident, so the next isolated failure is immediate again.
                  #
                  # /run (not /tmp): root-owned state on tmpfs, no symlink games.
                  STATE="/run/notify-failure-''${UNIT}.state"
                  now="$(date +%s)"

                  num() { case "''${1:-}" in "" | *[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }
                  last=0
                  count=0
                  stage=0
                  since=0
                  if [ -r "$STATE" ]; then
                    read -r last count stage since < "$STATE" || :
                  fi
                  last="$(num "''${last:-}")"
                  count="$(num "''${count:-}")"
                  stage="$(num "''${stage:-}")"
                  since="$(num "''${since:-}")"

                  # An hour without a notification means the incident is over:
                  # start a fresh one so a later isolated failure is not held back
                  # by the 30-minute stage left over from the previous storm.
                  if [ "$last" -eq 0 ] || [ $((now - last)) -ge 3600 ]; then
                    count=0
                    stage=0
                    since=$now
                    last=0
                  fi
                  [ "$since" -eq 0 ] && since=$now

                  count=$((count + 1))
                  case "$stage" in
                    0) hold=0 ;;
                    1) hold=300 ;;
                    *) hold=1800 ;;
                  esac

                  if [ "$last" -gt 0 ] && [ $((now - last)) -lt "$hold" ]; then
                    # Held back, but counted: the next notification says how many.
                    printf '%s %s %s %s\n' "$last" "$count" "$stage" "$since" > "$STATE"
                    exit 0
                  fi

                  repeat=$count
                  elapsed=$((now - since))
                  printf '%s %s %s %s\n' "$now" "0" "$((stage + 1))" "$since" > "$STATE"

                  # Compact duration, for the "N failures in M" synthesis line.
                  dur() {
                    if [ "$1" -lt 60 ]; then
                      printf '%ss' "$1"
                    elif [ "$1" -lt 3600 ]; then
                      printf '%smin' "$(($1 / 60))"
                    else
                      printf '%dh%02d' "$(($1 / 3600))" "$((($1 % 3600) / 60))"
                    fi
                  }

                  # Nature of the failure -> glyph + ntfy priority. `urgent` is
                  # reserved for what threatens the host itself (the kernel killed
                  # something, a crash dump, a hung watchdog); `low` for a
                  # condition that simply was not met, which is not a breakage.
                  # Everything else stays audible: at 1-4 notifications a day the
                  # useful lever on volume is N3 (routing + cap), not muting real
                  # failures.
                  case "$RESULT" in
                    oom-kill)        glyph="💀"; prio=urgent; tag=skull ;;
                    core-dump)       glyph="💥"; prio=urgent; tag=boom ;;
                    watchdog)        glyph="🐕"; prio=urgent; tag=dog ;;
                    timeout)         glyph="⏱";  prio=high;   tag=hourglass ;;
                    start-limit-hit) glyph="🔁"; prio=high;   tag=repeat ;;
                    exit-code)       glyph="❌"; prio=high;   tag=x ;;
                    signal)          glyph="⛔"; prio=high;   tag=no_entry ;;
                    resources)       glyph="🚧"; prio=high;   tag=construction ;;
                    protocol)        glyph="🔌"; prio=high;   tag=electric_plug ;;
                    exec-condition)  glyph="⏭";  prio=low;    tag=next_track_button ;;
                    *)               glyph="❓"; prio=high;   tag=question ;;
                  esac

                  # For exit-code STATUS is the numeric code, for signal it is the
                  # signal name (KILL, ABRT…): "exit-code 1", "signal KILL".
                  detail="$RESULT"
                  [ -n "$STATUS" ] && detail="$RESULT $STATUS"
                  TITLE="$glyph $SERVICE — $detail"
                  # A storm reads as one line instead of N notifications.
                  if [ "$repeat" -gt 1 ]; then
                    TITLE="$TITLE (×$repeat)"
                  fi

                  # The invocation id scopes the journal to the run that failed.
                  # `journalctl -u <unit> -n 30` could not do that: it mixed the
                  # boot noise and even later SUCCESSFUL runs into the message
                  # (observed on freeleech-farmer), and its `grep -v systemd[1]`
                  # filter emptied the body completely for a unit that logs nothing
                  # of its own — ntfy then substituted its default text and the
                  # alert read just "triggered", with no way to tell which service
                  # had failed (observed on vpn-monitor). Invocation-scoped output
                  # contains no systemd[1] lines at all, so no filtering is needed.
                  LOG=""
                  if [ -n "$INVOCATION" ]; then
                    LOG="$(journalctl _SYSTEMD_INVOCATION_ID="$INVOCATION" -o cat --no-pager 2>/dev/null)"
                  else
                    LOG="$(journalctl -u "$UNIT" -n 30 -o cat --no-pager 2>/dev/null \
                      | grep -v ' systemd\[1\]: ')"
                  fi

                  # Services log in colour (zigbee2mqtt does), and an escape
                  # sequence in a notification is noise at best.
                  LOG="$(printf '%s' "$LOG" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g')"

                  # The cause line: the LAST line that looks like a diagnostic.
                  # Last, not first, because the line closest to the exit is the
                  # one that killed the run — that is what turns a Python
                  # traceback into its final exception, and what digs
                  # "MQTT failed to connect" out of 25 lines of start-up chatter.
                  # Deliberately no "warn": unifi emits pages of harmless JVM
                  # warnings, and presenting one as the root cause would be a lie.
                  #
                  # Lines that name their own level as INFO/DEBUG/NOTICE/TRACE are
                  # dropped FIRST, because a word match alone lies: unifi logs
                  # `|-INFO … Setting level of logger [org.mongodb] to ERROR`, and
                  # picking that as the cause of a crash would be worse than
                  # showing nothing. Better no cause line than a wrong one — when
                  # nothing survives the filter the body is just the tail of the log.
                  CAUSE=""
                  if [ -n "$LOG" ]; then
                    CAUSE="$(printf '%s\n' "$LOG" \
                      | grep -ivE '(^|[^[:alnum:]])(info|debug|notice|trace)([^[:alnum:]]|$)' \
                      | grep -iE 'error|erreur|fail|échec|fatal|panic|exception|traceback|refus|denied|not permitted|not found|no space|read-only|timed out|timeout|unauthor|forbidden|cannot|could not|unable to|invalid|missing' \
                      | tail -1 | sed -E 's/^[[:space:]]+//')"
                  fi

                  # Cap every line at 200 bytes: one stray JSON payload (a
                  # zigbee2mqtt health message is ~400 chars) would otherwise eat
                  # the whole notification. iconv -c then drops the trailing
                  # multibyte sequence the byte-cut may have split, so the body
                  # stays valid UTF-8 for the JSON ntfy builds around it.
                  trim() {
                    LC_ALL=C sed -E 's/^(.{200}).+$/\1…/' \
                      | ${pkgs.glibc.bin}/bin/iconv -c -f utf-8 -t utf-8 2>/dev/null
                  }

                  if [ -n "$LOG" ]; then
                    BODY=""
                    if [ -n "$CAUSE" ]; then
                      BODY="⤷ $(printf '%s\n' "$CAUSE" | trim)"$'\n\n'
                    fi
                    # The cause is usually also the last log line, and printing
                    # it twice in a six-line message wastes the space that makes
                    # the message readable at a glance.
                    CONTEXT="$(printf '%s\n' "$LOG" | tail -5)"
                    if [ -n "$CAUSE" ]; then
                      CONTEXT="$(printf '%s\n' "$CONTEXT" | grep -vxF -- "$CAUSE" || :)"
                    fi
                    BODY="''${BODY}$(printf '%s\n' "$CONTEXT" | trim)"
                  else
                    # Always non-empty: RESULT and STATUS come from systemd, not
                    # from the unit, so a silent failure is still identifiable.
                    BODY="Aucune sortie journalisée par l'unité (échec silencieux)."$'\n'"Résultat systemd : $detail"
                  fi

                  if [ "$repeat" -gt 1 ]; then
                    BODY="🔁 $repeat échecs en $(dur "$elapsed") — notifications suivantes espacées."$'\n'"$BODY"
                  fi

                  export NTFY_CLICK="${dashboardUrl}"
                  export NTFY_ACTIONS="view, Grafana, ${grafanaUrl}"

                  printf '%s' "$BODY" | push_ntfy service-failure "$TITLE" "$tag" "$prio"
                '';
              in
              {
                description = "Notify ntfy on service failure for %i";
                # Ordering only, deliberately no `wants`: at boot the units that
                # fail earliest (cf-ddns, which needs DNS) were triggering this
                # notifier *before* ntfy-sh had bound its socket, and the message
                # was dropped (docs/notifications-plan.md §2.1). `wants` would
                # additionally risk an ordering cycle the day ntfy-sh itself lands
                # in notify.services, and would resurrect a deliberately stopped
                # ntfy. Everything ntfy-sh being down cannot cover is handled by
                # the spool in _ntfy.nix plus ntfy-spool-drain below.
                after = [ "ntfy-sh.service" ];
                path = [
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.systemd
                ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${script} %i";
                };

              };

            # Second half of the delivery guarantee: _ntfy.nix retries for ~28 s
            # and then spools to /var/lib/ntfy-spool. This replays what it left
            # behind, which covers the cases a retry cannot — ntfy-sh down for a
            # whole deploy, a boot where it starts after the failing units, a
            # broken topic ACL.
            #
            # It also publishes the spool depth so that a notification the
            # channel could not deliver is itself alertable (NtfySpoolStuck),
            # through a *different* publisher (Prometheus -> Alertmanager ->
            # alertmanager-ntfy) and visible in Grafana/Glance even when ntfy is
            # the thing that is down.
            ntfy-spool-drain = {
              description = "Replay spooled ntfy notifications and expose spool depth";
              after = [ "ntfy-sh.service" ];
              path = [
                pkgs.coreutils
                pkgs.curl
                pkgs.findutils
                pkgs.gnused
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              # `set +e` first: NixOS prefixes `script` with `set -e`, and a
              # collector that stops at the first failure would leave stale
              # metrics in place — i.e. report a healthy spool while messages
              # pile up (cf. AGENTS.md).
              script = ''
                set +e
                source ${pushNtfy}
                SPOOL="${spoolDir}"
                TEXTFILE=/var/lib/node-exporter-textfile

                # A publisher killed between the write and the rename leaves a
                # .part behind; nothing will ever complete it.
                find "$SPOOL" -maxdepth 1 -name '*.part' -mmin +60 -delete

                # Spool layout (_ntfy_spool): one "Header: value" per line, a
                # blank line, then the body. `Topic:` names the target, every
                # other line is replayed verbatim as an HTTP header — so a header
                # added to push_ntfy needs no change here.
                for f in "$SPOOL"/*.msg; do
                  [ -e "$f" ] || continue
                  topic="$(sed -n 's/^Topic: //p' "$f" | head -1)"
                  headers="$(sed -n '1,/^$/p' "$f" | sed -E '/^Topic: /d; /^$/d')"
                  if [ -z "$topic" ]; then
                    echo "ntfy-spool: $f illisible (pas de Topic:), mis de côté en .bad" >&2
                    mv -f "$f" "$f.bad"
                    continue
                  fi
                  # `1,/^$/d` drops the header block plus its blank separator.
                  if sed '1,/^$/d' "$f" | _ntfy_post "$topic" "$headers"; then
                    rm -f "$f"
                    echo "ntfy-spool: rejoué sur $topic — $(printf '%s\n' "$headers" | sed -n 's/^Title: //p')"
                  fi
                done

                pending="$(find "$SPOOL" -maxdepth 1 -name '*.msg' | wc -l)"
                oldest=0
                if [ "$pending" -gt 0 ]; then
                  ts="$(find "$SPOOL" -maxdepth 1 -name '*.msg' -printf '%T@\n' \
                        | sort -n | head -1 | cut -d. -f1)"
                  [ -n "$ts" ] && oldest=$(( $(date +%s) - ts ))
                fi

                mkdir -p "$TEXTFILE"
                umask 022
                tmp="$TEXTFILE/.ntfy-spool.prom.tmp"
                {
                  echo "# HELP ntfy_spool_pending Notifications ntfy non publiées en attente de rejeu."
                  echo "# TYPE ntfy_spool_pending gauge"
                  echo "ntfy_spool_pending $pending"
                  echo "# HELP ntfy_spool_oldest_age_seconds Âge du message en attente le plus ancien."
                  echo "# TYPE ntfy_spool_oldest_age_seconds gauge"
                  echo "ntfy_spool_oldest_age_seconds $oldest"
                  echo "# HELP ntfy_spool_drain_timestamp_seconds Dernier passage du drain (dead-man)."
                  echo "# TYPE ntfy_spool_drain_timestamp_seconds gauge"
                  echo "ntfy_spool_drain_timestamp_seconds $(date +%s)"
                } > "$tmp"
                mv -f "$tmp" "$TEXTFILE/ntfy-spool.prom"
              '';
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
                  # Music library notifications (beets imports, etc.).
                  ${ntfy} access everyone musique write-only

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

        systemd.timers.ntfy-spool-drain = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # OnBootSec flushes what was spooled during the boot race itself;
            # 2 min then bounds how long a held alert stays invisible.
            OnBootSec = "2min";
            OnUnitActiveSec = "2min";
            Unit = "ntfy-spool-drain.service";
          };
        };

        # 1733 drop-box: the publishers are not all root (the postgres restore
        # drill runs as `postgres`), so they must be able to create and rename
        # their own message there without being able to list — the spool carries
        # journal excerpts. The sticky bit keeps one publisher from removing
        # another's message; only the root drain reads and deletes.
        systemd.tmpfiles.rules = [ "d ${spoolDir} 1733 root root -" ];

        notify.services = [ "ntfy-spool-drain" ];
      };
    };
}
