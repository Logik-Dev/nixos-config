{ inputs, ... }:
{

  imports = [
    inputs.agenix-rekey.flakeModule
  ];

  perSystem =
    { config, ... }:
    {
      devshells.default = {
        packages = [ config.agenix-rekey.package ];
        env = [
          {
            name = "AGENIX_REKEY_ADD_TO_GIT";
            value = true;
          }
        ];
      };
    };
}
