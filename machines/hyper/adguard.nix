{
  domain,
  hosts,
  username,
  ...
}:
{

  # resolved conflicts with adguard port
  services.resolved.enable = false;

  # DNS port managed by nftables in firewall.nix

  # traefik
  services.traefik-proxy.services.adguardhome.subdomain = "dns";

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

      filtering.rewrites = [
        {
          domain = "*.${domain}";
          answer = "192.168.12.100";
        }
      ];
    };
  };
}
