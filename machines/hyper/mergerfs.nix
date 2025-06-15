{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mergerfs
  ];

  fileSystems."/mnt/storage" = {
    fsType = "fuse.mergerfs";
    device = "/mnt/data*";
    # options are adapted to use mmap (sqlite3 and torrents apps)
    options = [
      "cache.files=auto-full"
      "category.create=pfrd"
      "dropcacheonclose=true"
      "func.getattr=newest"
    ];
  };

}
