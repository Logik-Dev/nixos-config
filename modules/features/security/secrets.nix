{ inputs, ... }:
let
  module =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.secrets;
      hostName = config.networking.hostName;
    in
    {
      options.secrets = {
        hostsSecretsDir = lib.mkOption {
          description = "Directory where hosts secrets are stored";
          type = lib.types.path;
          default = inputs.self.outPath + "/secrets/hosts";
        };
      };

      config =
        let
          hostDir = "${cfg.hostsSecretsDir}/${hostName}";

          hostSecrets = lib.optionalAttrs (builtins.pathExists hostDir) (
            lib.filterAttrs (_n: v: v == "regular") (builtins.readDir hostDir)
          );

          mkSecret =
            k: _v: lib.nameValuePair (lib.strings.removeSuffix ".age" k) { rekeyFile = "${hostDir}/${k}"; };

        in
        {
          age.secrets = lib.mapAttrs' mkSecret hostSecrets;
        };
    };
in

{
  flake.modules = {
    nixos.common.imports = [ module ];
    darwin.common.imports = [ module ];
  };
}
