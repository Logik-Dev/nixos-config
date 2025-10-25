let
  flakePath = "/home/logikdev/Homelab/Nixos";
in
{

  flake.modules.homeManager.management = {
    programs.nh = {
      enable = true;
      clean.enable = true;
      homeFlake = flakePath;
      osFlake = flakePath;
    };
  };
}
