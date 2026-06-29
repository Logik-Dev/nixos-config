{ ... }:
{
  flake.modules.nixos.adguard =
    { config, ... }:
    {

      traefik.services.dns.port = 3000;

      # resolved conflicts with adguard port
      services.resolved.enable = false;

      # Configure nameservers to use AdGuard Home
      networking.nameservers = [ "127.0.0.1" ];

      networking.firewall.allowedUDPPorts = [ 53 ];

      networking.firewall.allowedTCPPorts = [ 53 ];

      notify.services = [ "adguardhome" ];

      services.adguardhome = {
        enable = true;
        mutableSettings = true;
        settings = {
          dns = {
            upstream_dns = [
              "9.9.9.9"
              "149.112.112.112"
            ];
            bootstrap_dns = [ "9.9.9.9" ];
            enable_dnssec = true;
          };

          filtering.rewrites_enabled = true;
          filtering.rewrites = [
            {
              enabled = true;
              domain = "*.hyper.${config.constants.domain}";
              answer = "192.168.10.100";
            }
          ];
        };
      };

      backups.sources.adguard = {
        paths = [ "/var/lib/AdGuardHome" ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
