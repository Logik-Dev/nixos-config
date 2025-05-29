{ ... }:
{
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
      "/mnt/ultra/misc/snapraid.content"
      "/var/snapraid.content"
      "/mnt/data1/snapraid.content"
      "/mnt/data2/snapraid.content"
    ];
    exclude = [
      "/lost+found/"
    ];
  };
}
