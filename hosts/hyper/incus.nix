{
  lib,
  pkgs,
  homelab,
  ...
}:
let
  mkProfile = name: description: devices: { inherit name devices description; };

  mkVlanProfile =
    vlan: description:
    mkProfile "vlan${toString vlan}" description {
      eth0 = {
        inherit vlan;
        name = "eth0";
        type = "nic";
        nictype = "macvlan";
        parent = "enp4s0";
      };
    };
  sizes = [
    "30GiB"
    "60GiB"
    "100GiB"
    "500GiB"
  ];

  mkStorageProfile =
    pool: size:
    mkProfile "${pool}-${size}" "" {
      root = {
        inherit pool size;
        path = "/";
        type = "disk";
      };
    };

  mkStorageProfiles = pool: map (size: mkStorageProfile pool size) sizes;

  intelGpuProfile = {
    name = "intel-gpu";
    description = "Intel UHD Graphics";
    devices = {
      intel-gpu = {
        type = "gpu";
        gid = 44;
        pci = "0000:00:02.0";
      };
    };
  };

  mediasProfileContainer = {
    name = "medias-shares";
    description = "Medias Shares";
    devices = {
      medias = {
        type = "disk";
        shift = true;
        source = "/mnt/raid/medias";
        path = "/medias";
      };
    };
  };
  mediasProfileVM = {
    name = "medias-shares-vm";
    description = "Medias Shares with IO Cache";
    devices = {
      medias = {
        type = "disk";
        shift = true;
        source = "/mnt/raid/medias";
        path = "/medias";
        "io.cache" = "metadata";
      };
    };
  };
  backupProfile = {
    name = "backups-folders";
    description = "Backups folders";
    devices =
      let
        type = "disk";
        shift = true;
      in
      {
        backups = {
          inherit type shift;
          path = "/home/logikdev/backups";
          source = "/mnt/backups/borg";
        };

        raid = {
          inherit type shift;
          path = "/home/logikdev/raid";
          source = "/mnt/raid/borg";
        };

        archive = {
          inherit type shift;
          path = "/home/logikdev/archives";
          source = "/mnt/archives/borg";
        };

      };
  };

  mountOptions = builtins.concatStringsSep "," [
    "noatime"
    "compress=zstd"
    "ssd"
    "space_cache=v2"
    "commit=15"
  ];

  mkBtrfsPool = name: source: {
    inherit name;
    driver = "btrfs";
    config = {
      inherit source;
      "btrfs.mount_options" = mountOptions;
    };
  };
in
{
  virtualisation.libvirtd.enable = true;
  networking.nftables.enable = true;
  networking.useNetworkd = true;
  networking.networkmanager.enable = lib.mkForce false;
  environment.systemPackages = with pkgs; [ btrfs-progs ];
  virtualisation.incus = {
    enable = true;
    #ui.enable = true;
    preseed = {
      config = {
        "core.https_address" = ":8443";
        "core.metrics_address" = ":8444";
        "core.metrics_authentication" = false;
      };

      profiles = [
        (mkVlanProfile 11 "Containers network")
        (mkVlanProfile 21 "IoT network")
        backupProfile
        intelGpuProfile
        mediasProfileContainer
        mediasProfileVM
      ] ++ mkStorageProfiles "local" ++ mkStorageProfiles "ultra";

      storage_pools = [
        (mkBtrfsPool "local" "/pools/local")
        (mkBtrfsPool "ultra" "/pools/ultra")
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 8443 ];

  networking.firewall.interfaces.incusbr0.allowedTCPPorts = [
    53
    67
  ];
  networking.firewall.interfaces.incusbr0.allowedUDPPorts = [
    53
    67
  ];

  #  programs.virt-manager.enable = true;
  users.users.logikdev.extraGroups = [
    "libvirtd"
    "incus-admin"
  ];

  services.vmagent = {
    enable = true;
    remoteWriteUrl = "https://victoriametrics.${homelab.domain}/api/v1/write";
    prometheusConfig = {
      scrape_configs = [
        {
          job_name = "incus";
          metrics_path = "/1.0/metrics";
          scheme = "https";
          tls_config.insecure_skip_verify = true;
          static_configs = [
            {
              targets = [ "hyper:8444" ];
            }
          ];
        }
      ];
    };
  };

}
