{ inputs, ... }:
{

  flake.modules.nixos.common =
    { config, ... }:
    {
      imports =
        let
          path = inputs.self + "/modules/hosts/${config.networking.hostName}/facter.json";
        in
        [
          inputs.nixos-facter-modules.nixosModules.facter
          {
            config.facter.reportPath = path;
          }
        ];
    };
}
