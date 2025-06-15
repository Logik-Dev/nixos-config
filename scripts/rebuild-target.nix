{ pkgs, ... }:
let
  rebuild-target = pkgs.writeShellScriptBin "rebuild-target" ''
    HOSTNAME=$1
    sudo nixos-rebuild switch --flake .#"$HOSTNAME" --target-host logikdev@"$HOSTNAME" --use-remote-sudo
  '';
in
rebuild-target
