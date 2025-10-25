{
  flake.modules.homeManager.common = {
    home.sessionVariables = {
      LAB = "$HOME/Homelab";
      FLAKE = "$HOME/Homelab/Nixos";
    };
  };
}
