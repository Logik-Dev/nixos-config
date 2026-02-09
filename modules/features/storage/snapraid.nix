{ ... }:
let

  flake.modules.nixos.hyper = {

    systemd.tmpfiles.rules = [
      "d /mnt/parity1 0755 root root -"
      "d /mnt/parity2 0755 root root -"
    ];

    services.snapraid = {
      enable = true;
      dataDisks = {
        storage = "/mnt/storage";
      };
      parityFiles = [
        "/mnt/parity1/snapraid.parity"
        "/mnt/parity2/snapraid.parity"
      ];
      contentFiles = [
        "/mnt/ultra/.snapraid.content"
        "/mnt/local/.snapraid.content"
        "/mnt/storage/.snapraid.content"
      ];
      exclude = [
        "/lost+found/"
      ];
    };
  };
in
{
  inherit flake;
}
