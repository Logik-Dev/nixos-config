{ config, pkgs, ... }:
{

  home.username = "logikdev";
  home.stateVersion = "24.05";
  home.homeDirectory = "/home/logikdev";

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    sshKeys = [ (builtins.readFile ./gpg.pub) ];
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
      publicKeys = [ { source = ./gpg.pub; } ];
    };
  };

}
