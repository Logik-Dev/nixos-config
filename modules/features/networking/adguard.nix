_: {
  flake.modules.nixos.adguard =
    { config, ... }:
    {

      traefik.services.dns = {
        port = 3000;
        enableAuthelia = true;
        category = "Réseau & Stockage";
        icon = "di:adguard-home";
        title = "AdGuard Home";
      };

      # resolved conflicts with adguard port
      services.resolved.enable = false;

      # Configure nameservers to use AdGuard Home, with Quad9 as a last-resort
      # fallback: if AdGuard itself is down the host still resolves (plaintext
      # and unfiltered — better than a DNS outage; LAN clients are unaffected).
      # Known limitation: browsers using DoH/Private Relay bypass both anyway.
      networking.nameservers = [
        "127.0.0.1"
        "9.9.9.9"
      ];

      networking.firewall.allowedUDPPorts = [ 53 ];

      networking.firewall.allowedTCPPorts = [ 53 ];

      notify.services = [ "adguardhome" ];

      services.adguardhome = {
        enable = true;
        mutableSettings = true;
        settings = {
          dns = {
            # DNS-over-TLS upstreams (Quad9 filtered: dns.quad9.net → 9.9.9.9,
            # dns10.quad9.net → 149.112.112.112); the plain addresses are only
            # the bootstrap used to resolve the DoT hostnames.
            upstream_dns = [
              "tls://dns.quad9.net"
              "tls://dns10.quad9.net"
            ];
            bootstrap_dns = [
              "9.9.9.9"
              "149.112.112.112"
            ];
            enable_dnssec = true;
          };

          filtering.rewrites_enabled = true;
          filtering.rewrites = [
            {
              enabled = true;
              domain = "*.hyper.${config.constants.domain}";
              answer = config.constants.hosts.hyper.lanIp;
            }
          ];
        };
      };

      backups.sources.adguard = {
        # DynamicUser + StateDirectory: /var/lib/AdGuardHome is a symlink to
        # /var/lib/private/AdGuardHome, so backing up the former only saves the
        # link (and the admin password hash lives in that state).
        paths = [ "/var/lib/private/AdGuardHome" ];
        # AdGuard Home is the host's DNS resolver (nameservers = 127.0.0.1,
        # resolved disabled). The default manageService stops it during the
        # backup, which kills DNS resolution and breaks any backup target that
        # needs a lookup (the Hetzner sftp host). Back it up live instead.
        manageService = false;
      };
    };
}
