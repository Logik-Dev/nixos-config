{
  inputs,
  lib,
  ...
}:
let
  flake.lib.mk-os = {
    inherit linux;
  };

  linux = mkNixos "x86_64-linux" "nixos";

  mkNixos =
    system: cls: name:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
        inputs.self.modules.nixos.${cls}
        inputs.self.modules.nixos.${name}
        {
          networking.hostName = lib.mkDefault name;
          nixpkgs.hostPlatform = lib.mkDefault system;
          system.stateVersion = "25.05";
        }
      ];

      specialArgs =
        let
          hs = hostname: secret: inputs.self + "/secrets/hosts/${hostname}/${secret}.age";
          cs = secret: inputs.self + "/secrets/common/${secret}.age";
        in
        {
          hostSecret = hs name;
          commonSecret = cs;
        };
    };
in
{
  inherit flake;
}
