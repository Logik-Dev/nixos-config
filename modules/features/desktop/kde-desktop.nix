{
  flake.modules.nixos.kde-desktop =
    {
      pkgs,
      ...
    }:
    {
      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        autoNumlock = true;
      };

      services.desktopManager.plasma6.enable = true;

      environment.systemPackages = with pkgs; [
        kdePackages.bluedevil
      ];
    };

}
