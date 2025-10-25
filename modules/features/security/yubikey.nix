{
  flake.modules.nixos.yubikey =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.rage
        pkgs.age-plugin-yubikey
      ];

      services.udev.packages = [ pkgs.yubikey-personalization ];
      services.pcscd.enable = true;

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      security.pam.services = {
        login.u2fAuth = true;
        sudo.u2fAuth = true;
      };
    };

  # avoid conflict with pcscd on boot
  flake.modules.homeManager.common = {
    programs.gpg.scdaemonSettings.disable-ccid = true;
  };
}
