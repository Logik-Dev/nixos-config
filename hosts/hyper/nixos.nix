{
  inputs,
  homelab,
  lib,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.default
    inputs.nixos-facter-modules.nixosModules.facter
    { config.facter.reportPath = ./facter.json; }
    ./disko.nix
    ../common/bare-metal.nix
    ./incus.nix
    ./homepage
  ];

  users.groups.media.gid = lib.mkForce 991;

  systemd.tmpfiles.settings =
    let
      d = {
        group = "users";
        mode = "0755";
        user = homelab.username;
      };
    in
    {
      # Borg backup folders
      "10-backups-folders" = {
        "/mnt/backups/borg" = {
          inherit d;
        };
        "/mnt/raid/borg" = {
          inherit d;
        };
        "/mnt/archives/borg" = {
          inherit d;
        };
      };

      # Media folders
      "20-media-folder" = {
        "/mnt/raid/medias" = {
          d = {
            group = "media";
            mode = "775";
            user = homelab.username;
          };
        };
      };
    };

  services.openssh.enable = true;
}
