{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username domain;
in
{
  flake.modules.nixos.adguard = {

    services.reverse-proxy.vhosts.dns.port = 3000;

    # resolved conflicts with adguard port
    services.resolved.enable = false;

    # Configure nameservers to use AdGuard Home
    networking.nameservers = [ "127.0.0.1" ];

    networking.firewall.allowedUDPPorts = [ 53 ];

    networking.firewall.allowedTCPPorts = [ 53 ];

    services.adguardhome = {
      enable = true;
      mutableSettings = true;
      settings = {
        users = [
          {
            name = username;
            password = "$2y$05$wzc0PDmM39F1IIQQwNtMt.Rmc0.M7MIo9TpNeVZrJqhemcbrbmXIG";
          }
        ];
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
            domain = "*.hyper.${domain}";
            answer = "192.168.10.100";
          }
          {
            enabled = true;
            domain = "*.k8s.${domain}";
            answer = "192.168.10.200";
          }
        ];
      };
    };
  };
}
