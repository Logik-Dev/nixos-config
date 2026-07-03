{ ... }:
{
  flake.modules.nixos.smartd =
    { pkgs, ... }:
    let
      # smartd's "mail" transport invokes its mailer like `mailer -s <subject>
      # <recipient>` with the alert body on stdin. We hijack that shim to push
      # the SMART alert to ntfy (homelab-alerts, already granted) as an urgent
      # notification, so a failing disk reaches the phone instead of a wall(1)
      # broadcast that no one is around to read.
      ntfyMailer = pkgs.writeShellScript "smartd-ntfy" ''
        subject="SMART alert"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -s) subject="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        body="$(cat)"
        ${pkgs.curl}/bin/curl -s \
          -H "Title: 💽 $subject" \
          -H "Priority: urgent" \
          -H "Tags: floppy_disk,rotating_light" \
          -d "$body" \
          "http://localhost:2586/homelab-alerts" >/dev/null 2>&1 || true
      '';
    in
    {
      # Also alert if the smartd daemon itself dies (complementary: this covers
      # the monitor going down; the mailer above covers a disk going bad).
      notify.services = [ "smartd" ];

      services.smartd = {
        enable = true;
        autodetect = true;
        notifications = {
          # wall(1) is useless on a headless box (no one on a tty); route disk
          # alerts to ntfy via the mailer shim instead (see ntfyMailer above).
          wall.enable = false;
          mail = {
            enable = true;
            recipient = "root";
            mailer = "${ntfyMailer}";
          };
          # Startup test push is off on purpose: with 7 drives it would fire one
          # notification per device on every smartd restart. Verify the pipe
          # manually after a config change instead.
          test = false;
        };
      };
    };
}
