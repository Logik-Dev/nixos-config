{ username, ... }:
{
  # parity disks permisions
  systemd.tmpfiles.settings = {
    "20-snapraid-folders" = {
      "/mnt/parity2" = {
        d = {
          group = "users";
          mode = "750";
          user = username;
        };
      };
    };
  };

  services.snapraid = {
    enable = true;
    dataDisks = {
      storage = "/mnt/storage";
    };
    parityFiles = [
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
}
