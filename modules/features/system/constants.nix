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
            sshKeyMac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvOpCZkkrtpmyjeYoHG9YacwW1uy4tvQ3PXjjy05CU7 logikdev@m4";
          };
          hosts.hyper = {
            lanIp = "192.168.10.100";
            gateway = "192.168.10.1";
            prefixLength = 24;
            mac = {
              management = "fc:34:97:10:ca:04";
              vms = "98:b7:85:00:8f:f2";
            };
            storageBox = {
              user = "u625917";
              host = "u625917.your-storagebox.de";
            };
          };
          media.gid = 991;
        };
      };

    nixos.common.imports = [ inputs.self.modules.generic.constants ];
    darwin.common.imports = [ inputs.self.modules.generic.constants ];
    homeManager.common.imports = [ inputs.self.modules.generic.constants ];
  };
}
