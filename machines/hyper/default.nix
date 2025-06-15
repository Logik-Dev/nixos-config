{
  inputs,
  username,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.default
    inputs.nixos-facter-modules.nixosModules.facter
    { config.facter.reportPath = ./facter.json; }
    ./builder.nix
    ./disko.nix
    ./incus.nix
    ./mergerfs.nix
    ./nix-serve.nix
    ./snapraid.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };

  # Needed folders
  systemd.tmpfiles.settings = {
    "10-shared-folders" = {
      "/mnt/storage/borg" = {
        d = {
          group = "media";
          mode = "775";
          user = username;
        };
      };
    };
  };

  # GPU passtrough
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];

  boot.kernelParams = [
    "intel_iommu=on"
    "vfio-pci.ids=8086:3e98"
  ];

}
