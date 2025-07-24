{
  pkgs,
  username,
  email,
  ...
}:
{
  imports = [
    ./gpg.nix
    ./zsh.nix
  ];

  home.sessionVariables.FLAKE = "/home/${username}/Nixos";

  home.packages = with pkgs; [
    bat
    cilium-cli
    compose2nix
    fd
    fluxcd
    k9s
    kubectl
    nh
    nixd
    ripgrep
    sops
    ssh-to-age
    go-task
    wl-clipboard
  ];

  programs.zsh.enable = true;

  programs.lf.enable = true;

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
    userEmail = email;

    signing = {
      key = "F5A34D392D22853E7EB1FA85AC259B4007CB7CE9";
      signByDefault = true;
    };
  };

  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "/home/${username}/.password-store";
    };
  };

}
