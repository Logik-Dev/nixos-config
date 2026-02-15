{ lib, ... }:
{
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  options.flake.factory = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  options.flake.secret = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

}
