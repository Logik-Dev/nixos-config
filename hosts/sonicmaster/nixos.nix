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

}
