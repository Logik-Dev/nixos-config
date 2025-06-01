{
  domain,
  lib,
  hosts,
  username,
  ...
}:
{

  networking.firewall.allowedUDPPorts = [ 53 ];

  services.adguardhome = {
    enable = true;
    openFirewall = true;
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

      filtering.rewrites =
        let
          mkRewrites =
            host:
            (map (alias: {
              domain = alias + "." + domain;
              answer = host.ipv4;
            }) host.aliases);

        in
        lib.flatten (lib.attrValues (lib.mapAttrs (k: host: mkRewrites host) hosts));

    };
  };
}
