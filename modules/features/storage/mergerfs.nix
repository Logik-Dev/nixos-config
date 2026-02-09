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

      systemd.services.sync-storage-to-medias = {
        description = "Sync /mnt/storage to /mnt/medias";

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.rsync}/bin/rsync -avh --progress /mnt/storage/ /mnt/medias/";
        };

      };

      # Optionnel : timer pour exécution automatique (par exemple chaque nuit à 2h)
      systemd.timers.sync-storage-to-medias = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 12:05:00"; # 2h du matin
          Persistent = true; # Rattrape si le système était éteint
        };
      };
    };

}
