{
  # Nix configuration
  nixpkgs.config.allowUnfree = true;
  nix = {
    gc.dates = "monthly";
    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "@wheel"
        "root"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
    };
  };

  system.stateVersion = "25.05";
}