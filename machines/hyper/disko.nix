{
  ...
}:
let
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
  disko.devices = {
    disk = {
      # Nixos M2 SSD (1Tb) AND local pool for VMs
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
              size = "150G";
              content = {
                type = "lvm_pv";
                vg = "vg_root";
              };
            };
            # Local BTRFS pool + misc
            local = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                mountpoint = "/mnt/local";
                mountOptions = btrfsMountOptions ++ [ "ssd" ];
                subvolumes = {
                  "/mnt/local/pool" = { };
                  "/mnt/local/misc" = { };
                };
              };
            };
          };
        };
      };

      # Ultra M2 SSD (2Tb) LVM pool owned by incus for VMs storage
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
          mountpoint = "/mnt/storage";
          mountOptions = [
            "nofail"
            "defaults"
          ];
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
    };

    # Volume groups
    lvm_vg = {

      # Root VG for Nixos
      vg_root = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };

      # Ultra VG is OWNED by incus for VMs ONLY
      vg_ultra = {
        type = "lvm_vg";
        lvs = {
          pool = {
            size = "1.8T";
            lvm_type = "thin-pool";
          };
          # Shared storage for Kubernetes
          ultra-shared = {
            size = "1T";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/ultra";
              mountOptions = [
                "nofail"
                "defaults"
                "noatime"
              ];
            };
          };
        };
      };

      # Storage VG
      vg_storage = {
        type = "lvm_vg";
        lvs = {

          # Nfs for k8s
          storage = {
            size = "12T";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/future";
              mountOptions = [
                "nofail"
                "defaults"
                "noatime"
              ];
            };
          };

          # Snapshots
          backups = {
            size = "1T";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/storage-snapshots";
              mountOptions = [
                "nofail"
                "defaults"
                "noatime"
              ];
            };
          };
        };
      };
    };
  };
}
