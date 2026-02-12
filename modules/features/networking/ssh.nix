{ inputs, ... }:
let

  inherit (inputs.self.meta.owner) username;

  flake.modules.nixos = {
    inherit common hyper;
  };

  common = {
    security.pam.sshAgentAuth.enable = true;
    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "no";
      settings.PasswordAuthentication = false;
    };
  };

  hyper = {
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
