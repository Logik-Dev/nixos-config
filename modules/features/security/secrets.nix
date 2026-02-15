{ inputs, ... }:
let
  module =
    {
      lib,
      config,
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

        commonSecretsDir = lib.mkOption {
          description = "Directory where common secrets are stored";
          type = lib.types.path;
          default = inputs.self.outPath + "/secrets/common";
        };
      };

      config =
        let
          hostDir = "${cfg.hostsSecretsDir}/${hostName}";

          hostSecrets = lib.optionalAttrs (builtins.pathExists hostDir) (
            lib.filterAttrs (n: v: v == "regular") (builtins.readDir hostDir)
          );

          commonSecrets = lib.filterAttrs (k: v: v == "regular") (builtins.readDir cfg.commonSecretsDir);

          mkSecret =
            k: v: dir:
            lib.nameValuePair (lib.strings.removeSuffix ".age" k) { rekeyFile = "${dir}/${k}"; };

          mkHostSecret = k: v: mkSecret k v hostDir;
          mkCommonSecret = k: v: mkSecret k v cfg.commonSecretsDir;

        in
        {
          age.secrets = lib.mkMerge [
            (lib.mapAttrs' mkHostSecret hostSecrets)
            (lib.mapAttrs' mkCommonSecret commonSecrets)
          ];
        };
    };
in

{
  flake.modules = {
    nixos.common.imports = [ module ];
    darwin.common.imports = [ module ];
  };
}
