{ lib, ... }:
{

  config.flake.factory.user =
    username: isAdmin:
    let
      fish =
        { pkgs, ... }:
        {
          programs.fish.enable = true;
          users.users.${username}.shell = pkgs.fish;
        };
    in
    {
      darwin.${username} =
        { pkgs, ... }:
        {
          imports = [ fish ];
          environment.shells = [ pkgs.fish ];
          users.users.${username}.home = "/Users/${username}";
          system.primaryUser = lib.mkIf isAdmin username;
        };

      nixos.${username} =
        { config, ... }:
        {
          imports = [ fish ];
          users.users.${username} = {
            description = username;
            isNormalUser = true;
            hashedPasswordFile = config.age.secrets."${username}-pw".path;
            extraGroups = lib.optionals isAdmin [
              "wheel"
              "networkmanager"
            ];
          };
        };
    };
}
