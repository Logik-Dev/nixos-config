{ homelab, lib, ... }:
{

  networking.firewall.allowedUDPPorts = [ 53 ];

  services.nginx.virtualHosts."dns.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://localhost:3000";
    };

  };

  services.adguardhome = {
    enable = true;
    openFirewall = false;
    mutableSettings = false;
    settings = {
      users = [
        {
          name = "logikdev";
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
      filtering.rewrites =
        let
          mkRewrites =
            host:
            (map (alias: {
              domain = alias + "." + homelab.domain;
              answer = host.ipv4;
            }) host.aliases);

        in
        lib.flatten (lib.attrValues (lib.mapAttrs (k: host: mkRewrites host) homelab.hosts));

    };
  };
}
