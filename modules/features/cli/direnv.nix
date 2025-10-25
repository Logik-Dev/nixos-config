{
  flake.modules.homeManager.dev = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
