{
  inputs,
  ...
}:
let
  mountOptions = [
    "nofail"
    "defaults"
    "noatime"
  ];
  btrfsMountOptions = [
    "nofail" # dont block system if failed
    "noatime"
    "compress=zstd"
    "space_cache=v2"
    "commit=15"
  ];
  xfsMountOptions = [
    "nofail" # dont block system if failed
    "defaults"
    "noatime"
    "nodiratime"
    "largeio"
    "inode64"
  ];
in
{
  ### WARNING
  ### When reinstalling keep ONLY system disk and comment other mounts here
  flake.modules.nixos.hyper = {

    imports = [
      inputs.disko.nixosModules.default
    ];

    systemd.tmpfiles.rules = [
      "d /mnt/medias1 0755 root root -"
      "d /mnt/medias2 0755 root root -"
      "d /mnt/parity1 0755 root root -"
      "d /mnt/parity2 0755 root root -"
    ];

    disko.devices = {
      disk = {

        # Nixos M2 SSD (1Tb) Root and Local PVs
        nixos = {
          device = "/dev/disk/by-id/nvme-CT1000P3PSSD8_2227E6457CFF";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              # EFI
              ESP = {
                name = "ESP";
                start = "1M";
                end = "2G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              # Root PV
              root = {
                size = "100%";
                content = {
                  type = "lvm_pv";
                  vg = "vg_root";
                };
              };
            };
          };
        };

        # Ultra M2 SSD (2Tb) Ultra PV
        ultra = {
          device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X165765M";
          type = "disk";
          content = {
            type = "lvm_pv";
            vg = "vg_ultra";
          };
        };

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
                  mountOptions = xfsMountOptions;
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
                  mountOptions = xfsMountOptions;
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
                  mountOptions = xfsMountOptions;
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
                  mountOptions = xfsMountOptions;
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
            mountOptions = btrfsMountOptions;
          };
        };
      };

      # Volume groups
      lvm_vg = {

        # Root VG for Nixos
        vg_root = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "500G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            local = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/local";
                inherit mountOptions;
              };
            };
          };
        };

        # Ultra VG
        vg_ultra = {
          type = "lvm_vg";
          lvs = {
            # Ultra storage - now takes all available space
            ultra = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/ultra";
                inherit mountOptions;
              };
            };
          };
        };
      };
    };
  };
}
