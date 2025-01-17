{ lib, ... }:
with builtins;
with lib;
let
  json = fromJSON (readFile ./homelab.json);
  hostType = types.submodule {
    options = {
      aliases = mkOption {
        type = types.listOf types.str;
      };
      ipv4 = mkOption {
        type = types.nullOr types.str;
      };
      modules = mkOption {
        type = types.listOf types.str;
      };
      os = mkOption {
        type = types.str;
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
          "vm"
          "lxc"
        ];
      };
    };
  };
in
{
  options.homelab = {
    username = mkOption {
      type = types.str;
    };

    domain = mkOption {
      type = types.str;
    };

    hosts = mkOption {
      type = types.attrsOf hostType;
    };
  };

  config.homelab = {
    username = json.username;
    domain = json.domain;
    hosts = mapAttrs (
      hostname:
      {
        aliases ? [ ],
        modules,
        platform,
        os,
        ipv4 ? null,
      }:
      {
        inherit
          aliases
          hostname
          ipv4
          modules
          os
          platform
          ;
        sshPublicKey = readFile ../../hosts/${hostname}/keys/ssh_host_ed25519_key.pub;
      }
    ) json.hosts;
  };
}
