{ inputs, ... }:
let
  nixCommon = {
    nixpkgs.config.allowUnfree = true;
    nix = {
      optimise.automatic = true;
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # used by nixd
      settings = {
        trusted-users = [
          "root"
          "@wheel"
        ];
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
      };
    };
  };
in
{
  flake.modules = {
    darwin.common = {
      imports = [ nixCommon ];
      nix.gc.interval = "weekly";
    };

    nixos.common = {
      imports = [ nixCommon ];
      nix.gc.dates = "weekly";
    };

  };
}
