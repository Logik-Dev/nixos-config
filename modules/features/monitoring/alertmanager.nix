{
  flake.modules.nixos.alertmanager = _: {
    services.prometheus.alertmanager = {
      enable = true;
      port = 9093;
      listenAddress = "127.0.0.1";
      configuration = {
        route = {
          group_by = [
            "alertname"
            "severity"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          receiver = "ntfy";
        };
        # Chains where one alert is the CAUSE and the others are its shadow.
        # Written narrowly on purpose: an inhibition that is too broad turns a
        # noisy channel into a blind one. `equal` is omitted where the source and
        # the targets carry no comparable label (a mount has `mountpoint`, a
        # restic alert has `repository`), which makes the suppression global for
        # as long as the cause is firing — and it lifts on its own when the cause
        # resolves.
        inhibit_rules = [
          {
            # /mnt/usb or /mnt/ultra gone: every backup, drill and pgBackRest
            # alert is a consequence, and `SystemdUnitFailed` fires for each unit
            # that trips over the missing mount. Safe to silence *here* because
            # the per-unit failures still arrive on the service-failure topic
            # through notify-failure, which Alertmanager cannot inhibit —
            # nothing becomes invisible, it just stops arriving twice.
            # HighDiskUsage is deliberately NOT a target: with /mnt/usb absent
            # the backups write to the root filesystem, so a full `/` is a real
            # and urgent consequence, not noise.
            source_matchers = [ ''alertname="MountPointMissing"'' ];
            target_matchers = [ ''alertname=~"Restic.*|Pgbackrest.*|DrillStale|SystemdUnitFailed"'' ];
          }
          {
            # The kernel killed a process for memory. PSI stalls and low
            # MemAvailable are the same event seen from two other angles, and
            # HostOOMKill is the only one of the three that names what happened.
            source_matchers = [ ''alertname="HostOOMKill"'' ];
            target_matchers = [ ''alertname=~"MemoryStallSustained|HighMemoryPressure"'' ];
            equal = [ "instance" ];
          }
          {
            # No wg0, no listener bound to it: while the tunnel itself is down,
            # VpnListenerUnbound can be nothing but a consequence.
            source_matchers = [ ''alertname="VpnTunnelDown"'' ];
            target_matchers = [ ''alertname="VpnListenerUnbound"'' ];
            equal = [ "instance" ];
          }
          {
            # The backend failing its probe is what produces the 5xx rate. The
            # probe names the service; TraefikHigh5xxRate is a label-less sum and
            # can only say "something returns 500" — hence no `equal`.
            source_matchers = [ ''alertname="ProbeFailure"'' ];
            target_matchers = [ ''alertname="TraefikHigh5xxRate"'' ];
          }
        ];

        receivers = [
          {
            name = "ntfy";
            webhook_configs = [
              {
                url = "http://127.0.0.1:8000/hook";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    services.prometheus.alertmanager-ntfy = {
      enable = true;
      settings = {
        http.addr = "127.0.0.1:8000";
        ntfy = {
          baseurl = "http://127.0.0.1:2586";
          notification = {
            topic = "homelab-alerts";
            # Severity routing WITHOUT splitting the topic. The plan called for
            # homelab-critical/homelab-warning, but ntfy decides whether the
            # phone makes noise from the priority, not from the topic — and two
            # new topics would mean re-subscribing the phone and re-granting the
            # ACLs for no extra benefit. Verified on the sandbox: gval reads
            # `labels.severity`, giving priority 5 / 2 / 2 for firing-critical,
            # firing-warning and resolved.
            #
            # Firing warnings therefore land silently in the topic history
            # (`low` = no sound, no vibration). To make them audible again
            # without touching anything else, change the `low` below to
            # `default`.
            priority = ''status == "firing" && labels.severity == "critical" ? "urgent" : "low"'';
            tags = [
              {
                tag = "green_circle";
                condition = ''status == "resolved"'';
              }
              {
                tag = "red_circle";
                condition = ''status == "firing"'';
              }
            ];
            # A resolved alert used to reuse the FIRING description, so the
            # recovery message announced the outage it was clearing:
            # "Resolved: WAL archiving failures" with a body reading
            # "archive-push failed at least once in the last hour".
            # Firing and resolved now have distinct bodies, and the recovery
            # text only states what the webhook actually carries
            # (docs/notifications-plan.md §2.3).
            templates = {
              title = ''{{ if eq .Status "resolved" }}✅ Rétabli : {{ else if eq (index .Labels "severity") "critical" }}🚨 {{ else }}⚠️ {{ end }}{{ index .Annotations "summary" }}'';
              description = ''{{ if eq .Status "resolved" }}Alerte rétablie : {{ index .Labels "alertname" }}{{ with index .Labels "instance" }} ({{ . }}){{ end }}.{{ else }}{{ index .Annotations "description" }}{{ end }}'';
            };
          };
        };
      };
    };

    notify.services = [
      "alertmanager"
      "alertmanager-ntfy"
    ];
  };
}
