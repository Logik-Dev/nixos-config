_:
let
  systemDisksModule =
    { config, ... }:
    let
      m = config.disko-lib.mountOptions;
    in
    {
      ### WARNING
      ### When reinstalling keep ONLY system disk and comment other mounts here
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
                  mountOptions = m.default;
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
                  mountOptions = m.default;
                };
              };
            };
          };
        };
      };
    };
in
{
  flake.modules.nixos.hyper.imports = [ systemDisksModule ];
}
