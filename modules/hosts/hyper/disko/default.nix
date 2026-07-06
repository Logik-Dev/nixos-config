{
  inputs,
  lib,
  ...
}:
let
  baseModule = {
    imports = [ inputs.disko.nixosModules.default ];

    options.disko-lib.mountOptions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
    };

    config = {
      systemd.tmpfiles.rules = [
        "d /mnt/medias1 0755 root root -"
        "d /mnt/medias2 0755 root root -"
        "d /mnt/parity1 0755 root root -"
        "d /mnt/parity2 0755 root root -"
      ];

      disko-lib.mountOptions = {
        default = [
          "nofail"
          "defaults"
          "noatime"
        ];
        btrfs = [
          "nofail" # dont block system if failed
          "noatime"
          "compress=zstd"
          "space_cache=v2"
          "commit=15"
        ];
        xfs = [
          "nofail" # dont block system if failed
          "defaults"
          "noatime"
          "nodiratime"
          "largeio"
          "inode64"
        ];
      };
    };
  };
in
{
  flake.modules.nixos.hyper.imports = [ baseModule ];
}
