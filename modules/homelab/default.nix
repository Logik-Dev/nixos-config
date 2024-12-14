{ lib, ... }:
with builtins;
with lib;
let
  json = fromJSON (readFile ./homelab.json);
  hostType = types.submodule {
    options = {
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
    };
  };
in
{
  options.homelab = {
    username = mkOption {
      type = types.str;
    };
    hosts = mkOption {
      type = types.attrsOf hostType;
    };
  };

  config.homelab = {
    username = json.username;
    hosts = lib.mapAttrs (
      hostname:
      {
        modules,
        os,
        ipv4 ? null,
      }:
      {
        inherit hostname;
        inherit ipv4 modules os;
        sshPublicKey = builtins.readFile ../../hosts/${hostname}/ssh_host_ed25519_key.pub;
      }
    ) json.hosts;
  };
}