{ pkgs, ... }:
let
  rebuild-target = pkgs.writeShellScriptBin "rebuild-target" ''
    HOSTNAME=$1
    sudo nixos-rebuild switch --flake .#"$HOSTNAME" --target-host logikdev@"$HOSTNAME" --build-host builder --use-remote-sudo --verbose
  '';
in
rebuild-target
