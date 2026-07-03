{ inputs, ... }:
let
  flake.modules.nixos.traefik =
    {
      lib,
      config,
      ...
    }:
    with lib;
    let
      cfg = config.traefik;
      host = config.networking.hostName;
      domain = config.constants.domain;
      email = config.constants.users.logikdev.email;

      service = types.submodule {
        options = {
          subdomain = mkOption {
            description = "Alternative subdomain name, if not set default to vhost name";
            type = types.nullOr types.str;
            default = null;
          };

          host = mkOption {
            description = "Host IP";
            type = types.str;
            default = "localhost";
          };

          port = mkOption {
            description = "Port which the service is listening on";
            type = types.nullOr types.number;
            default = null;
          };

          protocol = mkOption {
            description = "Protocol to use http or https";
            type = types.enum [
              "http"
              "https"
            ];
            default = "http";
          };

          enableAuthelia = mkOption {
            description = "Wheter to enable authelia";
            type = types.bool;
            default = false;
          };

          insecureSkipVerify = mkOption {
            description = "Skip TLS certificate verification for this backend (e.g. self-signed certs)";
            type = types.bool;
            default = false;
          };
        };
      };
    in
    {

      options.traefik = {
        services = mkOption {
          description = "Attribute set of services";
          type = types.attrsOf service;
          default = { };
        };
      };

      imports = [ inputs.self.modules.nixos.authelia ];

      config = {

        networking.firewall.allowedTCPPorts = [
          443
          80
        ];

        notify.services = [ "traefik" ];

        services.traefik = {
          enable = true;
          environmentFiles = [
            config.age.secrets.cloudflare.path
          ];
          dataDir = "/mnt/ultra/traefik";

          # static config
          staticConfigOptions = {
            log.level = "INFO";

            # Security-relevant access logging only (auth failures, scans):
            # keep 4xx/5xx, to journald. Low noise, no logrotate needed.
            accessLog = {
              filters.statusCodes = [ "400-599" ];
              bufferingSize = 64;
            };

            # dashboard
            api.dashboard = true;
            api.insecure = false;

            # HTTP
            entryPoints.http = {
              address = "192.168.10.100:80";
              http.redirections.entryPoint = {
                to = "https";
                scheme = "https";
              };
            };

            # HTTPS
            entryPoints.https.address = "192.168.10.100:443";

            # ACME
            certificatesResolvers.myresolver.acme = {
              email = email;
              storage = "${config.services.traefik.dataDir}/acme.json";
              dnsChallenge = {
                provider = "cloudflare";
                resolvers = [
                  "1.1.1.1:53"
                  "8.8.8.8:53"
                ];
              };
            };

          };

          # dynamic config
          dynamicConfigOptions = {

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
              (mapAttrs' (
                service: value:
                nameValuePair service {
                  inherit service;
                  entryPoints = [ "https" ];
                  tls.certResolver = "myresolver";
                  rule = "Host(`${service}.${host}.${domain}`)";
                  middlewares =
                    [
                      "secureHeaders@file"
                      "ratelimit@file"
                    ]
                    ++ lib.optional value.enableAuthelia "authelia@file";
                }

              ) cfg.services)
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
            http.services = mapAttrs' (
              service: value:
              nameValuePair service {
                loadBalancer = {
                  servers = [
                    {
                      url = "${value.protocol}://${value.host}:${toString value.port}";
                    }
                  ];
                  serversTransport = lib.mkIf value.insecureSkipVerify "insecure@file";
                };
              }
            ) cfg.services;

          };
        };
      };
    };
in
{
  inherit flake;
}
