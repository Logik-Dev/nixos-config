{
  config,
  email,
  domain,
  ...
}:
{

  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    appendHttpConfig = ''
      map $scheme $hsts_header {
          https   "max-age=31536000; includeSubdomains; preload";
      }
      add_header Strict-Transport-Security $hsts_header;
      add_header 'Referrer-Policy' 'origin-when-cross-origin';
      add_header X-Frame-Options DENY;
      add_header X-Content-Type-Options nosniff;
    '';
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  sops.secrets."cloudflare.env" = {
    sopsFile = ./cloudflare.env;
    format = "dotenv";
    key = "";
    group = "nginx";
  };

  security.acme = {
    acceptTerms = true;

    defaults = {
      inherit email;
      group = "nginx";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = config.sops.secrets."cloudflare.env".path;
    };

    certs.${domain} = {
      extraDomainNames = [ "*.${domain}" ];
    };
  };
}
