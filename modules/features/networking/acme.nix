{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) email domain;

  flake.modules.nixos.acme =
    {
      lib,
      config,
      commonSecret,
      ...
    }:
    let
      cfg = config.services.acme;
      host = config.networking.hostName;
    in
    {
      options.services.acme = {
        enable = lib.mkEnableOption "acme";
      };

      config = lib.mkIf cfg.enable {
        age.secrets.cloudflare.rekeyFile = commonSecret "cloudflare";

        security.acme = {
          acceptTerms = true;
          defaults.email = email;
          certs."${host}.${domain}" = {
            domain = "*.${host}.${domain}";
            dnsProvider = "cloudflare";
            dnsPropagationCheck = true;
            credentialsFile = config.age.secrets.cloudflare.path;
          };
        };
      };
    };

in
{
  inherit flake;

}
