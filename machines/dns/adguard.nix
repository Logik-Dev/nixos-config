{
  domain,
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

      filtering.rewrites = [
        {
          domain = "wireguard.${domain}";
          answer = hosts.security.ipv4;
        }
        {
          domain = "*.${domain}";
          answer = hosts.proxy.ipv4;
        }
      ];
    };
  };
}
