{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

  flake.modules.nixos = { inherit common hyper; };

  common =
    {
      pkgs,
      commonSecret,
      config,
      ...
    }:

    {
      age.secrets.password.rekeyFile = commonSecret "password";

      programs.fish.enable = true;

      users.users.${username} = {
        description = username;
        shell = pkgs.fish;
        isNormalUser = true;
        hashedPasswordFile = config.age.secrets.password.path;
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
      };
    };

  hyper = {
    users.groups.media.gid = 991;
  };

in
{
  inherit flake;
}
