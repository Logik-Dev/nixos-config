{ inputs, ... }:
{
  flake.modules.nixos.rustfs =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.rustfs.nixosModules.rustfs
      ];

      traefik.services.rustfs.port = 9001;
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

      backups.sources.rustfs = {
        paths = [ "/mnt/snap-ultra/rustfs" ];
        manageService = false;
        defaultRepositories = {
          usb = "/mnt/usb";
        };
        runBefore =
          let
            snap = pkgs.writeShellScriptBin "snap" ''
              mkdir -p /mnt/snap-ultra
              ${pkgs.util-linux}/bin/umount /mnt/snap-ultra || true
              ${pkgs.lvm2.bin}/bin/lvremove -f /dev/vg_ultra/snap-ultra || true
              ${pkgs.lvm2.bin}/bin/lvcreate -L 100G -n snap-ultra -s /dev/vg_ultra/ultra
              ${pkgs.util-linux}/bin/mount /dev/vg_ultra/snap-ultra /mnt/snap-ultra
            '';
          in
          "${snap}/bin/snap";
      };

    };
}
