let
  secretModeGroup = {
    group = "authelia";
    mode = "0440";
  };
in
{
  flake.modules.nixos.authelia =
    { config, ... }:
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

      age.secrets = {
        "authelia-storage-encryption-key" = secretModeGroup;
        "authelia-jwt-secret" = secretModeGroup;
        "authelia-users.yaml" = secretModeGroup;
        "authelia-session-secret" = secretModeGroup;
        "authelia-smtp.yaml" = secretModeGroup;
      };

      # Extra group
      users.groups.authelia = { };
      systemd.services.authelia-main.serviceConfig.SupplementaryGroups = [ "authelia" ];

      traefik.services.auth.port = 9091;

      notify.services = [ "authelia" ];

      # Authelia main
      services.authelia.instances.main = {
        enable = true;
        settingsFiles = [ config.age.secrets."authelia-smtp.yaml".path ];
        secrets = {
          storageEncryptionKeyFile = config.age.secrets.authelia-storage-encryption-key.path;
          jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
          sessionSecretFile = config.age.secrets.authelia-session-secret.path;
        };
        settings = {
          # Users file
          authentication_backend = {
            file.path = config.age.secrets."authelia-users.yaml".path;
          };

          # Session
          session.cookies = [
            {
              domain = "hyper.${config.constants.domain}";
              authelia_url = "https://auth.${config.networking.hostName}.${config.constants.domain}";
              expiration = "1d";
            }
          ];

          # Access control
          access_control = {
            default_policy = "deny";
            rules = [

              # Bypass for LAN
              {
                domain = "*.${config.constants.domain}";
                policy = "bypass";
                networks = [ "192.168.10.0/24" ];
              }

              # Two Factor for others
              {
                domain = "*.${config.constants.domain}";
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
