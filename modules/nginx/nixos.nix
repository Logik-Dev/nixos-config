{ config, homelab, ... }:
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

  sops.secrets.cloudflare-token.owner = "nginx";
  sops.secrets.cloudflare-email.owner = "nginx";

  security.acme = {
    acceptTerms = true;

    defaults = {
      email = "logikdevfr@gmail.com";
      group = "nginx";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialFiles = {
        "CF_API_EMAIL_FILE" = config.sops.secrets.cloudflare-email.path;
        "CF_DNS_API_TOKEN_FILE" = config.sops.secrets.cloudflare-token.path;
      };
    };

    certs.${homelab.domain} = {
      extraDomainNames = [ "*.${homelab.domain}" ];
    };
  };
}
