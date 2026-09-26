{ ... }:
{
  flake.modules.nixos.smartd =
    { pkgs, ... }:
    let
      pushNtfy = import ../monitoring/lib/_ntfy.nix { inherit pkgs; };

      # nixpkgs' smartd module pipes a full e-mail to its mailer
      # (`${mailer} -i <recipient>`: From/To/Subject headers, then the alert
      # message and `smartctl -a` output on stdin). Parse it here — Subject
      # becomes the ntfy title, the body after the header block the message
      # (truncated to ntfy's size limit). The previous shim expected
      # `-s <subject>` and never matched, so every alert arrived as a generic
      # "SMART alert".
      ntfyMailer = pkgs.writeShellScript "smartd-ntfy" ''
        source ${pushNtfy}
        input="$(${pkgs.coreutils}/bin/cat)"
        subject="$(printf '%s\n' "$input" | ${pkgs.gnused}/bin/sed -n 's/^Subject: //p' | ${pkgs.coreutils}/bin/head -1)"
        body="$(printf '%s\n' "$input" | ${pkgs.gawk}/bin/awk 'found{print} /^[[:space:]]*$/{found=1}')"
        [ -n "$subject" ] || subject="SMART alert"
        [ -n "$body" ] || body="$input"
        body="$(printf '%s' "$body" | ${pkgs.coreutils}/bin/tail -c 3800)"
        printf '%s' "$body" | push_ntfy homelab-alerts "💽 $subject" floppy_disk,rotating_light urgent
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
