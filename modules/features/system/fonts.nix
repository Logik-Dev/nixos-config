{ ... }:
let
  nerdFonts =
    { pkgs, ... }:
    {
      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.nerd-fonts.fira-code
      ];
    };

  flake.modules.nixos.common.imports = [ nerdFonts ];
  flake.modules.darwin.common.imports = [ nerdFonts ];
in
{
  inherit flake;
}
