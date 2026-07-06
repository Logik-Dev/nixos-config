{ ... }:
let
  dynamicModule =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.traefik.services;
      host = config.networking.hostName;
      domain = config.constants.domain;
    in
    {
      config = {
        services.traefik.dynamicConfigOptions = {
          # middlewares
          http.middlewares.authelia.forwardAuth = {
            address = "http://localhost:9091/api/authz/forward-auth";
            trustForwardHeader = "true";
            authResponseHeaders = "Remote-User,Remote-Groups,Remote-Email,Remote-Name";
          };

          # Security headers applied to every router (see routers below).
          # HSTS is safe here: every vhost is HTTPS-only via traefik. preload
          # is left off (it's an irreversible commitment to the browser list).
          http.middlewares.secureHeaders.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = false;
            contentTypeNosniff = true;
            customFrameOptionsValue = "SAMEORIGIN";
            referrerPolicy = "strict-origin-when-cross-origin";
          };

          # Per-source-IP rate limit to blunt brute-force / scraping. Generous
          # so it doesn't hurt media streaming / immich sync; bump if needed.
          http.middlewares.ratelimit.rateLimit = {
            average = 150;
            burst = 300;
          };

          # Hardened TLS: options.default is applied automatically to all
          # routers. TLS 1.3 ciphers are negotiated automatically; the list
          # below only constrains the TLS 1.2 fallback.
          tls.options.default = {
            minVersion = "VersionTLS12";
            sniStrict = false;
            cipherSuites = [
              "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
              "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
              "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
              "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
              "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
              "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
            ];
          };

          # transport for backends with self-signed certs (e.g. UniFi)
          http.serversTransports.insecure.insecureSkipVerify = true;

          # router
          http.routers =
            (lib.mapAttrs' (
              service: value:
              lib.nameValuePair service {
                inherit service;
                entryPoints = [ "https" ];
                tls.certResolver = "myresolver";
                rule = "Host(`${service}.${host}.${domain}`)";
                middlewares = [
                  "secureHeaders@file"
                  "ratelimit@file"
                ]
                ++ lib.optional value.enableAuthelia "authelia@file";
              }
            ) cfg)
            // {
              # Dashboard
              dashboard = {
                rule = "Host(`traefik.${host}.${domain}`)";
                middlewares = [
                  "secureHeaders@file"
                  "ratelimit@file"
                  "authelia@file"
                ];
                entryPoints = [ "https" ];
                service = "api@internal";
                tls.certResolver = "myresolver";
              };
            };

          # services
          http.services = lib.mapAttrs' (
            service: value:
            lib.nameValuePair service {
              loadBalancer = {
                servers = [
                  {
                    url = "${value.protocol}://${value.host}:${toString value.port}";
                  }
                ];
                serversTransport = lib.mkIf value.insecureSkipVerify "insecure@file";
              };
            }
          ) cfg;
        };
      };
    };
in
{
  flake.modules.nixos.traefik.imports = [ dynamicModule ];
}
