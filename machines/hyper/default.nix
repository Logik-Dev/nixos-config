{
  inputs,
  username,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.default
    inputs.nixos-facter-modules.nixosModules.facter
    { config.facter.reportPath = ./facter.json; }
    ./adguard.nix
    ./avahi.nix
    ./builder.nix
    ./ddns.nix
    ./disko.nix
    ./docker
    ./firewall.nix
    ./incus.nix
    ./medias.nix
    #    ./mergerfs.nix
    ./nfs.nix
    ../../modules/traefik
    ./nix-serve.nix
    #./snapraid.nix
    ./vaultwarden.nix
    ./wireguard.nix
  ];

  # Firewall configuration in firewall.nix
  # traefik
  services.traefik-proxy.enable = true;

  # backups
  services.backups.enable = true;

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
