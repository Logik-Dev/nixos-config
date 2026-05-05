{ inputs, ... }:
{
  flake.modules = {
    generic.constants =
      {
        lib,
        pkgs,
        ...
      }:

      let
        homeRoot = if pkgs.stdenv.isLinux then "/home" else "/Users";
      in
      {
        options.constants = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };

        config.constants = {
          domain = "logikdev.fr";
          users.logikdev = {
            fullname = "Cédric Maunier";
            username = "logikdev";
            homeDir = "${homeRoot}/logikdev";
            flakeDir = "${homeRoot}/logikdev/Homelab/Nixos";
            email = "logikdevfr@gmail.com";
            gpg = "F5A34D392D22853E7EB1FA85AC259B4007CB7CE9";
            sshKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKu/AimR2iGXlkfsUyzMuSg/ytgeNqTAeJZNcABv6kKwDngRojJDotsXbfRUZPOnsEyi0ZlwAaAtuVv3Caj7ePY=";
          };
        };
      };

    nixos.common.imports = [ inputs.self.modules.generic.constants ];
    darwin.common.imports = [ inputs.self.modules.generic.constants ];
    homeManager.common.imports = [ inputs.self.modules.generic.constants ];
  };

}
