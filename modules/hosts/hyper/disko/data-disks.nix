{ ... }:
let
  dataDisksModule =
    { config, ... }:
    let
      m = config.disko-lib.mountOptions;
    in
    {
      disko.devices.disk = {
        # Medias1 is part of mergerfs (8Tb)
        medias1 = {
          device = "/dev/disk/by-uuid/c21a2c28-58eb-4ae2-9591-cfe8de518f2a";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/mnt/medias1";
                  mountOptions = m.xfs;
                };
              };
            };
          };
        };

        # Medias2 is part of mergerfs (8Tb)
        medias2 = {
          device = "/dev/disk/by-uuid/577774a9-36c8-4d06-87d5-69939fb9abb3";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/mnt/medias2";
                  mountOptions = m.xfs;
                };
              };
            };
          };
        };

        # Parity1 for snapraid (8Tb)
        parity1 = {
          device = "/dev/disk/by-uuid/4abb727c-73f5-42ab-bcb5-ad92a1077d1d";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/mnt/parity1";
                  mountOptions = m.xfs;
                };
              };
            };
          };
        };

        # Parity2 for snapraid (8Tb)
        parity2 = {
          device = "/dev/disk/by-uuid/af20cb71-b9f2-439e-95c5-311786a64543";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/mnt/parity2";
                  mountOptions = m.xfs;
                };
              };
            };
          };
        };

        # USB WD Drive (2Tb)
        usb = {
          device = "/dev/disk/by-id/ata-WDC_WD20JDRW-11C7VS1_WD-WX22AC4KLCU0";
          type = "disk";
          content = {
            type = "btrfs";
            mountpoint = "/mnt/usb";
            extraArgs = [ "-f" ];
            mountOptions = m.btrfs;
          };
        };
      };

      # Monthly checksum scrub of the btrfs backup drive. /mnt/usb is btrfs
      # single (no DUP data) — scrub can detect bit-rot but not self-heal it,
      # so it's our only early-warning that the restic/pgbackrest target is
      # silently corrupting. df/usage won't tell us; the scrub will.
      services.btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [ "/mnt/usb" ];
      };
    };
in
{
  flake.modules.nixos.hyper.imports = [ dataDisksModule ];
}
