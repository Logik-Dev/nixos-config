{
  hetzner_user,
  inputs,
  email,
  username,
  pkgs,
  domain,
  hosts,
  pkgsUnstable,
  ...
}:
let
  hmModules = [
    ./hm.nix
    ../../modules/cli/hm.nix
    ../../modules/neovim/hm.nix
    ../../modules/desktop/hm.nix
  ];
in
{
  imports = [
    ./backups.nix
    ./hardware-configuration.nix
    ../../modules/desktop/nixos.nix
    ../../modules/yubikey/nixos.nix
    ./wireguard.nix
    # home manager
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        sharedModules = [
          inputs.sops-nix.homeManagerModules.sops
        ];
        useGlobalPkgs = true;
        useUserPackages = true;
        users.${username} = {
          imports = hmModules;
        };
        extraSpecialArgs = {
          inherit
            email
            username
            domain
            hosts
            hetzner_user
            pkgsUnstable
            ;
        };
      };
    }
  ];

  virtualisation.podman.enable = true;

  # zsh
  users.users.${username}.shell = pkgs.zsh;
  programs.zsh.enable = true;
  environment.pathsToLink = [ "/share/zsh" ]; # autocompletion for system programs

  # bootloader
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };

  # Automount USB storage
  services.devmon.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

}
