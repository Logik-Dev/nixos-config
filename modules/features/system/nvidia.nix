{
  flake.modules.nixos.nvidia =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {

      # opengl
      hardware.graphics.enable = true;
      services.xserver.enable = lib.mkForce false;
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };

      boot.initrd.kernelModules = [ "nvidia" ];
      boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

      # nixpkgs.config.cudaSupport = true;

      environment = {
        systemPackages = with pkgs; [
          cudatoolkit
          libGLU
          libGL
          ncurses5
          nvtopPackages.nvidia
          linuxPackages.nvidia_x11
        ];

        sessionVariables = {
          LD_LIBRARY_PATH = [ "${config.hardware.nvidia.package}/lib" ];
          CUDA_PATH = "${pkgs.cudatoolkit}";
        };
      };

    };
}
