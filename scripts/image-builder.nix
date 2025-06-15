{ pkgs, ... }:
let
  imageBuilder = pkgs.writeShellScriptBin "image-builder" ''
    DEST_DIR="$FLAKE/deployments/generated"

    mkdir -p $DEST_DIR

    vmImage=$(nix build .#nixosConfigurations.virtual-machine.config.system.build.qemuImage --no-link --print-out-paths)
    vmMetadata=$(nix build .#nixosConfigurations.virtual-machine.config.system.build.metadata --no-link --print-out-paths)
    cp -L "$vmImage"/nixos.qcow2 "$DEST_DIR"/vm.qcow2 
    cp -L "$vmMetadata"/tarball/*  "$DEST_DIR"/vm-metadata.tar.xz

    containerImage=$(nix build .#nixosConfigurations.container.config.system.build.squashfs --no-link --print-out-paths)
    containerMetadata=$(nix build .#nixosConfigurations.container.config.system.build.metadata --no-link --print-out-paths)
    cp -L "$containerImage"/*.squashfs "$DEST_DIR"/container-image.squashfs
    cp -L "$containerMetadata"/tarball/* "$DEST_DIR"/container-metadata.tar.xz

    chmod 770 "$DEST_DIR"/*
  '';
in
imageBuilder
