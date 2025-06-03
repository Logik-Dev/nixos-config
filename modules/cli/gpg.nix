{ config, pkgs, ... }:
{

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    sshKeys = [ (builtins.readFile ../../machines/sonicmaster/keys/gpg.pub) ];
    pinentryPackage = if config.gtk.enable then pkgs.pinentry-qt else pkgs.pinentry-curses;
    enableExtraSocket = true;
  };

  programs.gpg = {
    enable = true;
    settings = {
      trust-model = "tofu+pgp";
    };
    publicKeys = [ { source = ../../machines/sonicmaster/keys/gpg.pub; } ];
  };

}
