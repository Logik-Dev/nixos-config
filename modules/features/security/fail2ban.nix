{
  flake.modules.nixos.fail2ban = {
    # Expose jail/bans metrics to Prometheus (socket is wired automatically).
    services.prometheus.exporters.fail2ban.enable = true;

    services.fail2ban = {
      enable = true;

      # Never ban our own access paths: loopback, both LAN subnets, and the
      # Tailscale CGNAT range (Tailscale SSH + admin traffic originate there).
      ignoreIP = [
        "127.0.0.1/8"
        "192.168.10.0/24"
        "192.168.21.0/24"
        "100.64.0.0/10"
      ];

      bantime = "1h";
      maxretry = 5;
      # Escalate repeat offenders (each re-ban lasts longer).
      bantime-increment.enable = true;

      # SSH is already key-only (PasswordAuthentication=false); this bans the
      # scanners/invalid-user noise at the firewall via the systemd-journal backend.
      jails.sshd.settings.enabled = true;
    };
  };
}
