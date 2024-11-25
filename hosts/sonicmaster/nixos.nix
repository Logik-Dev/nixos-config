{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./gpg.nix
    ./hardware-configuration.nix
    ./yubikey.nix
  ];

  networking.hostName = "sonicmaster";

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

}
