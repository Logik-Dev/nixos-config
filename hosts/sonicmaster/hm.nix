{ pkgs, config, ... }:
{

  home.packages = with pkgs; [
    discord-ptb
    ns-usbloader
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

}
