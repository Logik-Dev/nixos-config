{
  flake.modules.nixos.hyper =
    { pkgs, ... }:
    {

      systemd.tmpfiles.rules = [
        "d /mnt/storage 0755 root root -"
      ];

      environment.systemPackages = [
        pkgs.mergerfs
        pkgs.xfsprogs
      ];

      fileSystems."/mnt/storage" = {
        device = "/mnt/medias1:/mnt/medias2";
        fsType = "fuse.mergerfs";
        options = [
          "defaults"
          "allow_other"
          "use_ino"
          "cache.files=partial"
          "dropcacheonclose=true"
          "category.create=mfs"
        ];
        depends = [
          "/mnt/medias1"
          "/mnt/medias2"
        ];
      };
    };
}
