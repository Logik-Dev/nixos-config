{

  flake.modules.nixos.gnome =
    { pkgs, ... }:
    {
      services.xserver.enable = true;
      services.xserver.displayManager.gdm.enable = true;
      services.xserver.desktopManager.gnome.enable = true;
      environment.systemPackages = [
        pkgs.adwaita-icon-theme
        pkgs.gnomeExtensions.user-themes
      ];
    };

}
