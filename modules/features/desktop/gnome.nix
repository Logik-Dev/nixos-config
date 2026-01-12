{

  flake.modules.nixos.gnome =
    { pkgs, ... }:
    {
      services.xserver.enable = true;
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      environment.systemPackages = [
        pkgs.adwaita-icon-theme
        pkgs.gnomeExtensions.user-themes
      ];
    };

}
