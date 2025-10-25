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
in
{
  ### WARNING
  ### When reinstall first disconnect ALL disks and keep ONLY system disk and comment mounts here
  ### After installation reconnect disk and decomment mounts here
  flake.modules.nixos.hyper = {
    imports = [
      inputs.disko.nixosModules.default
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
                end = "128M";
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
                size = "931G";
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

        # Backups (8Tb)
        medias = {
          device = "/dev/disk/by-uuid/255fc8ca-e257-4c57-a973-acc65ec81e6e";
          type = "disk";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/backups";
            inherit mountOptions;
          };
        };

        # Data1 (8Tb) will be merged to /mnt/storage
        data1 = {
          device = "/dev/disk/by-id/ata-ST8000DM004-2U9188_ZR14KLX2";
          type = "disk";
          content = {
            type = "lvm_pv";
            vg = "vg_storage";
          };
        };

        # Data2 (8Tb) will be merged to /mnt/storage
        data2 = {
          device = "/dev/disk/by-id/ata-ST8000DM004-2CX188_ZR13TZTV";
          type = "disk";
          content = {
            type = "lvm_pv";
            vg = "vg_storage";
          };
        };

        # Parity2 (8Tb) ONLY used by snapraid
        parity2 = {
          device = "/dev/disk/by-uuid/6810c203-848a-451c-9fe0-8bbe7014e190";
          type = "disk";
          content = {
            type = "btrfs";
            mountpoint = "/mnt/parity2";
            extraArgs = [ "-f" ];
            mountOptions = btrfsMountOptions;
          };
        };

        # USB WD Drive (20Tb)
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
              size = "431G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/local";
                inherit mountOptions;
              };
            };
          };
        };

        # Local VG
        vg_local = {
          type = "lvm_vg";
          lvs = {
            local = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                #mountpoint = "/mnt/local";
                #inherit mountOptions;
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

        # Storage VG
        vg_storage = {
          type = "lvm_vg";
          lvs = {

            storage = {
              size = "12T";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/storage";
                inherit mountOptions;
              };
            };

            # Snapshots
            backups = {
              size = "1T";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/storage-snapshots";
                inherit mountOptions;
              };
            };
          };
        };
      };
    };
  };
}
