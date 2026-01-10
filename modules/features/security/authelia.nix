{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) domain;
in
{
  flake.modules.nixos.hyper =
    { config, hostSecret, ... }:
    {
      services.postgresql = {
        ensureDatabases = [ "authelia-main" ];
        ensureUsers = [
          {
            name = "authelia-main";
            ensureDBOwnership = true;
          }
        ];
      };

      age.secrets.authelia-storage-encryption-key = {
        rekeyFile = hostSecret "authelia-storage-encryption-key";
        group = "authelia";
        mode = "0440";
      };

      age.secrets.authelia-jwt-secret = {
        rekeyFile = hostSecret "authelia-jwt-secret";
        group = "authelia";
        mode = "0440";
      };

      age.secrets.authelia-users = {
        rekeyFile = hostSecret "authelia-users.yaml";
        group = "authelia";
        mode = "0440";
      };

      age.secrets.authelia-session-secret = {
        rekeyFile = hostSecret "authelia-session-secret";
        group = "authelia";
        mode = "0440";
      };

      age.secrets.authelia-notifier = {
        rekeyFile = hostSecret "authelia-smtp.yaml";
        group = "authelia";
        mode = "0440";
      };

      # Extra group
      users.groups.authelia = { };
      systemd.services.authelia-main.serviceConfig.SupplementaryGroups = [ "authelia" ];

      services.mytraefik.services.auth.port = 9091;

      # Authelia main
      services.authelia.instances.main = {
        enable = true;
        settingsFiles = [ config.age.secrets.authelia-notifier.path ];
        secrets = {
          storageEncryptionKeyFile = config.age.secrets.authelia-storage-encryption-key.path;
          jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
          sessionSecretFile = config.age.secrets.authelia-session-secret.path;
        };
        settings = {
          # Users file
          authentication_backend = {
            file.path = config.age.secrets.authelia-users.path;
          };

          # Session
          session.cookies = [
            {
              domain = "hyper.${domain}";
              authelia_url = "https://auth.hyper.${domain}";
              expiration = "1d";
            }
          ];

          # Access control
          access_control = {
            default_policy = "deny";
            rules = [

              # Bypass for LAN
              {
                domain = "*.${domain}";
                policy = "bypass";
                networks = [ "192.168.10.0/24" ];
              }

              # Two Factor for others
              {
                domain = "*.${domain}";
                policy = "two_factor";
              }
            ];
          };

          # postgresql
          storage = {
            postgres = {
              address = "unix:///run/postgresql";
              database = "authelia-main";
              username = "authelia-main";
            };
          };
        };
      };
    };
}
