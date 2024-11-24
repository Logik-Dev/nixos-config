{ flake, inputs, ... }:
{ pkgs, ... }:
{

  config = {
    home.packages = with pkgs; [
      bat
      fd
      nh
      nixd
      nixvimPkg
      ripgrep
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
    ];

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
    home.sessionVariables.FLAKE = "/home/logikdev/Parts";

    programs.starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;

    };

    nix.registry = {
      "my".flake = flake;
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
  };
}
