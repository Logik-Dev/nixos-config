{
  flake.modules.nixos.common =
    { pkgs, ... }:
    {
      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.nerd-fonts.fira-code
      ];
    };
}
