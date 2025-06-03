{
  pkgs,
  config,
  username,
  ...
}:
{

  home.packages = with pkgs; [
    age
    discord-ptb
    ns-usbloader
    wireguard-tools
    dnsutils
    opentofu
  ];

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    sshKeys = [ (builtins.readFile ./keys/gpg.pub) ];
    pinentryPackage = if config.gtk.enable then pkgs.pinentry-qt else pkgs.pinentry-curses;
    enableExtraSocket = true;
  };

  programs = {
    zsh.enable = true;
    zsh.loginExtra = "gpgconf --launch gpg-agent";

    gpg = {
      enable = true;
      settings = {
        trust-model = "tofu+pgp";
      };
      publicKeys = [ { source = ./keys/gpg.pub; } ];
    };

  };
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

}
