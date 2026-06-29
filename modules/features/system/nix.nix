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
          "logikdev"
        ];
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
        auto-optimise-store = true;
      };
    };
  };
in
{
  flake.modules = {
    darwin.common = {
      imports = [ nixCommon ];
      nix.gc.automatic = true;
      nix.gc.interval = "weekly";
    };

    nixos.common = {
      imports = [ nixCommon ];
      nix.gc.automatic = true;
      nix.gc.dates = "weekly";
    };

  };
}
