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
    ./disko.nix
    ./incus.nix
    ./mergerfs.nix
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

}
