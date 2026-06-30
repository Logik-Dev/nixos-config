{
  flake.modules.nixos.alertmanager =
    { config, ... }:
    {
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
          receivers = [
            {
              name = "ntfy";
              webhook_configs = [
                {
                  url = "http://127.0.0.1:8000/alertmanager";
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
              priority = ''status == "firing" ? "high" : "default"'';
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
              templates = {
                title = ''{{ if eq .Status "resolved" }}Resolved: {{ end }}{{ index .Annotations "summary" }}'';
                description = ''{{ index .Annotations "description" }}'';
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
