{ pkgs, ... }:
{
  home.sessionVariables.FLAKE = "/home/logikdev/Nixos";

  home.packages = with pkgs; [
    bat
    fd
    nh
    nixd
    ripgrep
    sops
    ssh-to-age
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
    go-task
    wl-clipboard
  ];

  programs.zsh.enable = true;

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;

  };

  programs.git = {
    enable = true;
    userName = "Logik-Dev";
    userEmail = "logikdevfr@gmail.com";

    signing = {
      key = "F5A34D392D22853E7EB1FA85AC259B4007CB7CE9";
      signByDefault = true;
    };
    aliases = {
      gcam = "git commit -m";
    };
  };

  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "/home/logikdev/.password-store";
    };
  };

}
