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
    };
  };
}
