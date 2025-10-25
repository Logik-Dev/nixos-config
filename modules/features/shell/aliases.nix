{
  flake.modules.homeManager.common = {
    home.shellAliases = {
      c = "clear";
      g = "git";
      gaa = "git add .";
      gs = "git status";
      gcm = "git commit -m";
      nrs = "sudo nixos-rebuild switch --flake $FLAKE";
    };
  };
}
