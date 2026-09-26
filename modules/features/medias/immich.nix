{ ... }:
{
  flake.modules.nixos.immich =
    { config, pkgs, ... }:
    {
      traefik.services.immich = {
        port = 2283;
        category = "Médias";
        icon = "di:immich";
        # No Authelia on purpose: the mobile/desktop apps talk to the API
        # directly and cannot complete a forward-auth redirect. Immich has its
        # own auth (and the container binds loopback otherwise).
      };

      services.immich = {
        enable = true;
        group = "media";
        mediaLocation = "/mnt/ultra/immich";
        machine-learning.enable = false;
        accelerationDevices = [
          "/dev/nvidia0"
          "/dev/nvidiactl"
          "/dev/nvidia-uvm"
        ];
      };

      backups.sources.immich = {
        paths = [ config.services.immich.mediaLocation ];
        # cache = ML model store; thumbs/encoded-video are large (~59G) and
        # regenerated on demand. upload/ (475G) stays in the backup.
        exclude = [
          "${config.services.immich.mediaLocation}/cache"
          "${config.services.immich.mediaLocation}/thumbs"
          "${config.services.immich.mediaLocation}/encoded-video"
        ];
        manageService = false;
      };

      users.users.immich = {
        home = "/mnt/ultra/immich/home";
        createHome = true;
        extraGroups = [
          "video"
          "render"
        ];
      };

      hardware.nvidia-container-toolkit.enable = true;

      virtualisation.oci-containers.containers = {
        immich-ml = {
          # Tag derived from the server version so a nixpkgs bump keeps
          # server and ML in lock-step (version mismatch breaks ML inference).
          image = "ghcr.io/immich-app/immich-machine-learning:v${pkgs.immich.version}-cuda";
          autoStart = true;
          extraOptions = [ "--gpus=all" ];
          # Loopback only: podman's DNAT bypasses the NixOS firewall, and the
          # ML API has no auth. The immich-server reaches it via localhost.
          ports = [ "127.0.0.1:3003:3003" ];
          volumes = [ "/mnt/ultra/immich/cache:/cache" ];
        };
      };

      notify.services = [
        "podman-immich-ml"
        "immich-server"
      ];

    };
}
