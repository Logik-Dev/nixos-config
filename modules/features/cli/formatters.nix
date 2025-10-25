{ inputs, ... }:
{

  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.nixfmt.package = pkgs.nixfmt-rfc-style;
        programs.rustfmt.enable = true;
      };
    };

}
