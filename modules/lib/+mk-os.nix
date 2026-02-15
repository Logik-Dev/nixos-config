{
  inputs,
  lib,
  ...
}:
let
  flake.lib.mk-os = {
    inherit linux darwin;
  };

  linux = mkNixos "x86_64-linux" "nixos";
  darwin = mkDarwin "aarch64-darwin" "darwin";

  mkNixos =
    system: cls: host:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
        inputs.self.modules.nixos.${cls}
        inputs.self.modules.nixos.${host}
        {
          networking.hostName = lib.mkDefault host;
          nixpkgs.hostPlatform = lib.mkDefault system;
          system.stateVersion = "25.05";
        }
      ];
    };

  mkDarwin =
    system: cls: name:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      modules = [
        inputs.self.modules.darwin.${cls}
        inputs.self.modules.darwin.${name}
        {
          networking.hostName = lib.mkDefault name;
          nixpkgs.hostPlatform = lib.mkDefault system;
          system.stateVersion = 5;
        }
      ];
    };
in
{
  inherit flake;
}
