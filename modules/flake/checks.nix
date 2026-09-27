{ inputs, lib, ... }:
{
  # `nix flake check` only evaluated the treefmt check, never the host
  # configurations — a broken module only surfaced at deploy time. These
  # checks force the module system to evaluate each host (via its toplevel
  # drvPath) without *building* the full system, so eval errors are caught
  # locally and on any future CI while staying cheap.
  perSystem =
    { pkgs, system, ... }:
    let
      nixosHosts = lib.optionals (system == "x86_64-linux") [
        "hyper"
        "sonicmaster"
      ];
      darwinHosts = lib.optionals (system == "aarch64-darwin") [ "m4" ];

      mkEvalCheck =
        name: config:
        pkgs.runCommand "${name}-eval" { } ''
          # unsafeDiscardStringContext keeps the store path out of the
          # derivation's inputs: the config is *evaluated* (catches errors)
          # without dragging the whole system into the build.
          echo ${builtins.unsafeDiscardStringContext config.system.build.toplevel.drvPath} > $out
        '';

      mkChecks =
        hosts: configs:
        lib.listToAttrs (map (h: lib.nameValuePair "${h}-eval" (mkEvalCheck h configs.${h}.config)) hosts);
    in
    {
      checks =
        mkChecks nixosHosts inputs.self.nixosConfigurations
        // mkChecks darwinHosts inputs.self.darwinConfigurations;
    };
}
