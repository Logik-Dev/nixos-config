{

  flake.modules.nixos.sonicmaster =
    { pkgs, ... }:
    {
      services.usbmuxd.enable = true;
      services.usbmuxd.package = pkgs.usbmuxd2;

      environment.systemPackages = [
        pkgs.libimobiledevice
        pkgs.fuse # optional, to mount using 'ifuse'
      ];
    };

}
