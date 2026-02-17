{
  flake.modules.nixos.acme =
    {
      config,
      ...
    }:
    let
      host = config.networking.hostName;
    in
    {
      config = {
        security.acme = {
          acceptTerms = true;
          defaults.email = config.constants.users.logikdev.email;
          certs."${host}.${config.constants.domain}" = {
            domain = "*.${host}.${config.constants.domain}";
            dnsProvider = "cloudflare";
            dnsPropagationCheck = true;
            credentialsFile = config.age.secrets.cloudflare.path;
          };
        };
      };
    };
}
