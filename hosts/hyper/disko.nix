{
  ...
}:
let
  mountOptions = [
    "noatime"
    "compress=zstd"
    "ssd"
    "space_cache=v2"
    "commit=15"
  ];
  mkSubvolume = name: mountpoint: {
    "${name}" = {
      inherit mountpoint mountOptions;
    };
  };
in
{
  disko.devices = {
    disk = {
      # Nixos NVME
      nixos = {
        device = "/dev/disk/by-id/nvme-CT1000P3PSSD8_2227E6457CFF";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
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

            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes =
                  (mkSubvolume "@root" "/")
                  // (mkSubvolume "@var" "/var")
                  // (mkSubvolume "@nix" "/nix")
                  // (mkSubvolume "@home" "/home")
                  // (mkSubvolume "@local-pool" "/pools/local");
              };
            };
          };
        };
      };

      # Ultra NVME
      ultra = {
        device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X165765M";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes =
                  (mkSubvolume "@snapshots" "/pools/snapshots") // (mkSubvolume "@ultra-pool" "/pools/ultra");
              };
            };
          };
        };
      };

      # 3To Archives
      transfer = {
        device = "/dev/disk/by-uuid/94fb43dc-bfff-428f-aaef-233749754f6f";
        type = "disk";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/mnt/archives";
        };
      };

      # 8To Backups
      medias = {
        device = "/dev/disk/by-uuid/255fc8ca-e257-4c57-a973-acc65ec81e6e";
        type = "disk";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/mnt/backups";
        };
      };

      # 8To RAID0 First PV
      raid0_first = {
        device = "/dev/disk/by-uuid/y7YAfw-Bwt6-VTBI-FOt0-u4sH-1yrQ-pefA7x";
        type = "disk";
        content = {
          #type = "filesystem";
          #format = "ext4";
          #mountpoint = "/mnt/backup";
          type = "lvm_pv";
          vg = "vg_storage";
        };
      };

      # 8To RAID0 Second PV
      raid0_second = {
        device = "/dev/disk/by-uuid/5c4475ec-d9a2-477a-ba42-f9338a550118";
        type = "disk";
        content = {
          #type = "filesystem";
          #format = "ext4";
          #mountpoint = "/mnt/archives";
          type = "lvm_pv";
          vg = "vg_storage";
        };
      };
    };

    lvm_vg = {
      vg_storage = {
        type = "lvm_vg";
        lvs = {
          lv_raid0 = {
            size = "12T";
            lvm_type = "raid0";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/raid";
            };
          };
        };
      };
    };
  };
}
