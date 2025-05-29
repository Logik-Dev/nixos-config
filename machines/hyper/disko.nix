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
            # Local pool PV
            local = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_local";
              };
            };
          };
        };
      };

      # Ultra M2 SSD (2Tb) misc + pool owned by incus for container storage
      ultra = {
        device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0X165765M";
        type = "disk";
        content = {
          type = "btrfs";
          extraArgs = [ "-f" ];
          subvolumes = {
            "/mnt/ultra" = {
              mountOptions = btrfsMountOptions ++ [ "ssd" ];
              mountpoint = "/mnt/ultra";
            };
            "/mnt/ultra/pool" = { };
            "/mnt/ultra/misc" = { };
          };
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
          mountOptions = [
            "nofail"
            "defaults"
          ];
        };
      };

      # Data1 (8Tb) will be merged to /mnt/storage with mergerfs
      data1 = {
        device = "/dev/disk/by-uuid/ef34a318-43d4-4afa-b309-b62dc3ef1a56";
        type = "disk";
        content = {
          type = "btrfs";
          mountpoint = "/mnt/data1";
          extraArgs = [ "-f" ];
          mountOptions = btrfsMountOptions;
        };
      };

      # Data2 (8Tb) will be merged to /mnt/storage with mergerfs
      data2 = {
        device = "/dev/disk/by-uuid/c4b2173a-ee14-402e-9596-a6a47093680d";
        type = "disk";
        content = {
          type = "btrfs";
          mountpoint = "/mnt/data2";
          extraArgs = [ "-f" ];
          mountOptions = btrfsMountOptions;
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

      /*
        # Archives (3Tb)
        transfer = {
          device = "/dev/disk/by-uuid/94fb43dc-bfff-428f-aaef-233749754f6f";
          type = "disk";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/archives";
          };
        };
      */

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

      # Local VG is OWNED by incus for VMs ONLY
      vg_local = {
        type = "lvm_vg";
        lvs = {
          pool = {
            size = "100%";
            lvm_type = "thin-pool";
          };
        };
      };
    };
  };
}
