{
  domain,
  hosts,
  username,
  ...
}:
{

  # resolved conflicts with adguard port
  services.resolved.enable = false;
  
  # Configure nameservers to use AdGuard Home
  networking.nameservers = [ "127.0.0.1" ];

  # traefik
  services.traefik-proxy.services.adguardhome.subdomain = "dns";
  services.traefik-proxy.services.adguardhome.port = 3000;

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
          domain = "*.k8sp.home.${domain}";
          answer = "10.0.200.100";
        }
       {
          domain = "*.k8sd.home.${domain}";
          answer = "10.0.200.99";
        }
        {
          domain = "*.k8s.home.${domain}";
          answer = "10.0.200.100";
        }
        {
          domain = "*.hyper.home.${domain}";
          answer = hosts.hyper.ipv4;
        }
        

      ];
    };
  };
}
