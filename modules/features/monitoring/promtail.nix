{ pkgs, ... }:
{
  flake.modules.nixos.promtail = {
    services.alloy = {
      enable = true;
      extraFlags = [ "--server.http.listen-addr=127.0.0.1:12346" ];
    };

    environment.etc."alloy/config.alloy".text = ''
      logging {
        level = "info"
      }

      loki.source.journal "systemd" {
        max_age = "12h"
        path = "/var/log/journal"
        labels = {
          job = "systemd-journal",
          host = "hyper",
        }
        relabel_rules = <<-EOF
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label = "unit"
          }
          rule {
            source_labels = ["__journal__priority"]
            target_label = "priority"
          }
          rule {
            source_labels = ["__journal__transport"]
            target_label = "transport"
          }
        EOF
        forward_to = [loki.write.local.receiver]
      }

      loki.write "local" {
        endpoint {
          url = "http://127.0.0.1:3100/loki/api/v1/push"
        }
      }
    '';

    notify.services = [ "alloy" ];
  };
}
