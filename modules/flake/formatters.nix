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
        programs.ruff.enable = true;
        # ruff 0.16 active 413 règles par défaut, dont DTZ/PLW/S qui échouent
        # sur des scripts préexistants ; on cible le jeu classique E4/E7/E9/F.
        settings.formatter.ruff-check.options = [ "--select=E4,E7,E9,F" ];
        # statix rewrites structure and nixfmt reindents; run nixfmt last so the
        # two formatters converge (otherwise the treefmt check oscillates).
        settings.formatter.nixfmt.priority = 10;
      };
    };

}
