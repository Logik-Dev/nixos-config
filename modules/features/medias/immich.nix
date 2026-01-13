{ ... }:
{
  flake.modules.nixos.hyper = {
    services.mytraefik.services.immich.port = 2283;

    services.immich = {
      enable = true;
      group = "media";
      redis.enable = true;
      mediaLocation = "/mnt/ultra/immich";
      machine-learning.enable = false;
      accelerationDevices = [
        "/dev/nvidia0"
        "/dev/nvidiactl"
        "/dev/nvidia-uvm"
      ];
      database = {
        enable = true;
        enableVectorChord = true;
        createDB = true;
      };
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
        image = "ghcr.io/immich-app/immich-machine-learning:v2.4.1-cuda";
        autoStart = true;
        extraOptions = [ "--gpus=all" ];
        ports = [ "3003:3003" ];
        volumes = [ "/mnt/ultra/immich/cache:/cache" ];
      };
    };
  };
}
