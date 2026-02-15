{ inputs, ... }:
let

  inherit (inputs.self.meta.owner) username;

  flake.modules.darwin.common = {
    services.openssh.enable = true;
  };

  flake.modules.homeManager.common =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          matchBlocks.h.hostname = "192.168.10.100";
        };
      }
      (lib.mkIf (pkgs.stdenv.isDarwin) {
        programs.ssh = {
          enableDefaultConfig = false;
          matchBlocks."*".identityAgent =
            "/Users/logikdev/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
        };
      })
    ];

  flake.modules.nixos.common =
    { ... }:
    {
      security.pam.sshAgentAuth.enable = true;
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "no";
        settings.PasswordAuthentication = false;
      };
    };

  flake.modules.nixos.hyper = {
    networking.firewall.allowedTCPPorts = [ 22 ];
    users.users."${username}" = {
      openssh.authorizedKeys.keyFiles = [
        (inputs.self + "/secrets/yubikey.pub")
        (inputs.self + "/secrets/m4.pub")
      ];
    };
  };
in
{
  inherit flake;
}
