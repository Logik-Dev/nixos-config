{ inputs, ... }:
{
  flake.modules.nixos.common = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      gc.dates = "weekly";
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # used by nixd
      settings = {
        auto-optimise-store = true;
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
      };
    };
  };
}
