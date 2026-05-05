{ inputs, ... }:
let

  flake.modules.darwin.common = {
    services.openssh.enable = true;
  };

  flake.modules.homeManager.common =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          matchBlocks.h.hostname = "192.168.10.100";
        };
      }
      (lib.mkIf (pkgs.stdenv.isDarwin) {
        programs.ssh = {
          matchBlocks."*".identityAgent =
            "/Users/logikdev/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
          matchBlocks.h.extraOptions = {
            RequestTTY = "yes";
            RemoteCommand = "zellij attach ssh || zellij -s ssh";
          };
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

  flake.modules.nixos.hyper =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 22 ];
      users.users."${config.constants.users.logikdev.username}" = {
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
