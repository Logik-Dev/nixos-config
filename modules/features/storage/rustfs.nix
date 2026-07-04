{ inputs, ... }:
{
  flake.modules.nixos.rustfs =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.rustfs.nixosModules.rustfs
      ];

      traefik.services.rustfs.port = 9001;
      traefik.services.rustfs.enableAuthelia = true;
      traefik.services.s3.port = 9000;

      notify.services = [ "rustfs" ];

      services.rustfs = {
        enable = true;
        package = inputs.rustfs.packages.${pkgs.stdenv.hostPlatform.system}.default;
        accessKeyFile = config.age.secrets.rustfs-access-key.path;
        secretKeyFile = config.age.secrets.rustfs-secret-key.path;
        volumes = "/mnt/ultra/rustfs";
        address = ":9000";
        consoleEnable = true;
        consoleAddress = "127.0.0.1:9001";
      };

      # The rustfs blob store is deliberately NOT backed up wholesale: it holds
      # every *-s3 restic repo (dominated by immich-s3 ~440 GB), all of which
      # already have their own -usb/-hetzner copies, so a rustfs-usb backup was
      # ~860 GB of duplicated immich on one disk. Immich is protected directly
      # via backups.sources.immich (usb + hetzner). The one thing living only in
      # rustfs — barman's pg-backups store — is backed up on its own, small,
      # see backups.sources.pg-barman in postgresql.nix.
    };
}
