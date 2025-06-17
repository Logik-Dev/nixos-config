{
  config,
  email,
  domain,
  ...
}:

let
  mkVirtualHostWithExtraConfig = host: service: port: extraConfig: {
    "${service}.${domain}" = {
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        inherit extraConfig;
        proxyWebsockets = true;
        proxyPass = "http://${host}:${toString port}";
      };
    };
  };
  mkVirtualHost =
    host: service: port:
    mkVirtualHostWithExtraConfig host service port "";
in
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

    virtualHosts =
      mkVirtualHost "docker" "torrent" 8080
      // mkVirtualHost "docker" "flaresolverr" 8191
      // mkVirtualHost "dns" "dns" 3000
      // mkVirtualHost "security" "vaultwarden" 8222
      // mkVirtualHost "medias" "prowlarr" 9696
      // mkVirtualHost "medias" "radarr" 7878
      // mkVirtualHost "medias" "sonarr" 8989
      // mkVirtualHost "medias" "jellyfin" 8096
      // mkVirtualHost "medias" "jellyseerr" 5055
      // mkVirtualHost "medias" "papers" 28981
      // mkVirtualHost "monitoring" "logs" 9428

      # immich specific
      // mkVirtualHostWithExtraConfig "medias" "photos" 2283 ''
        client_max_body_size 50000M;
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';

  };

  # ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # cloudflare secrets
  sops.secrets."cloudflare.env" = {
    sopsFile = ../../secrets/cloudflare.proxy.env;
    format = "dotenv";
    key = "";
    group = "nginx";
  };

  # acme
  security.acme = {
    acceptTerms = true;
    certs.${domain}.domain = "*.${domain}";
    defaults = {
      inherit email;
      group = "nginx";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = config.sops.secrets."cloudflare.env".path;
    };
  };
}
