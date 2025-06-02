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
      data1 = "/mnt/data1";
      data2 = "/mnt/data2";
    };
    parityFiles = [
      "/mnt/parity2/snapraid.parity"
    ];
    contentFiles = [
      "/mnt/local/misc/.snapraid.content"
      "/mnt/data1/.snapraid.content"
      "/mnt/data2/.snapraid.content"
    ];
    exclude = [
      "/lost+found/"
    ];
  };
}
