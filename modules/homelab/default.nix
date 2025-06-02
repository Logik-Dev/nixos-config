{ lib, ... }:
with builtins;
with lib;
let
  json = fromJSON (readFile ../../deployments/machines.json);
  hostType = types.submodule {
    options = {
      ipv4 = mkOption {
        type = types.nullOr types.str;
      };
      system = mkOption {
        type = types.str;
        default = "x86_64-linux";
      };
      hostname = mkOption {
        type = types.str;
      };
      sshPublicKey = mkOption {
        type = types.str;
      };
      platform = mkOption {
        type = types.enum [
          "bare-metal"
          "container"
          "virtual-machine"
        ];
      };
    };
  };
in
{
  options.hosts = mkOption {
    type = types.attrsOf hostType;
  };

  config.hosts = mapAttrs (
    hostname:
    {
      platform,
      ipv4 ? null,
      ...
    }:
    {
      inherit
        hostname
        ipv4
        platform
        ;
      sshPublicKey = readFile ../../machines/${hostname}/keys/ssh_host_ed25519_key.pub;
    }
  ) json;
}
