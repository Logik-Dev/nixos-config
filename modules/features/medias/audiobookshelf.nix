_: {
  flake.modules.nixos.audiobookshelf =
    { ... }:
    {
      # Reuse the shared media hygiene (group = "media", UMask 0002) so the
      # libraries under /mnt/storage stay group-writable with Bindery.
      imports = [ (import ./lib/_media-service.nix { app = "audiobookshelf"; }) ];

      # dataDir is relative to /var/lib (module constraint); config/DB/metadata
      # live there, the actual libraries are configured in the web UI.
      services.audiobookshelf = {
        enable = true;
        port = 13378;
      };

      systemd.services.audiobookshelf.unitConfig.RequiresMountsFor = [ "/mnt/storage" ];

      traefik.services.audiobookshelf = {
        port = 13378;
        # No Authelia on purpose: native clients (iOS/Android/CarPlay) cannot
        # complete a forward-auth redirect; Audiobookshelf has its own auth.
        enableAuthelia = false;
        category = "Médias";
        icon = "di:audiobookshelf";
      };

      notify.services = [ "audiobookshelf" ];

      backups.sources.audiobookshelf = {
        paths = [ "/var/lib/audiobookshelf" ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
