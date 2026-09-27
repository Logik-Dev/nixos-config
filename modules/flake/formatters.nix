{ inputs, ... }:
{

  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.nixfmt.package = pkgs.nixfmt;
        programs.deadnix.enable = true;
        programs.statix.enable = true;
        # statix rewrites structure and nixfmt reindents; run nixfmt last so the
        # two formatters converge (otherwise the treefmt check oscillates).
        settings.formatter.nixfmt.priority = 10;
      };
    };

}
