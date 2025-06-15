{
  pkgs,
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

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

}
