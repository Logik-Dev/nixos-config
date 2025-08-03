{
  pkgs,
  username,
  pkgsUnstable,
  ...
}:
{

  home.packages = with pkgs; [
    age
    nodejs
    discord-ptb
    hubble
    ns-usbloader
    wireguard-tools
    dnsutils
    opentofu
    talosctl
    pkgsUnstable.claude-code
  ];

  home.sessionVariables.CLAUDE_CODE_MAX_OUTPUT_TOKENS = "32000";

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

}
