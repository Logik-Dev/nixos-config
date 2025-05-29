{
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../common/bare-metal.nix
    ./wireguard.nix
  ];

  programs.steam.enable = true;

  # Automount USB storage
  services.devmon.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  networking.extraHosts = "192.168.11.31 docker torrent.logikdev.fr";

}
