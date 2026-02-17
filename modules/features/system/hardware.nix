{ inputs, ... }:
{

  flake.modules.nixos.common =
    { config, ... }:
    {
      imports =
        let
          facterPath = inputs.self + "/modules/hosts/${config.networking.hostName}/facter.json";
        in
        [
          inputs.nixos-facter-modules.nixosModules.facter
          {
            config.facter.reportPath = facterPath;
          }
        ];
    };
}
