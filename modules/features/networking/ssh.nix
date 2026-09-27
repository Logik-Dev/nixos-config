_:
let

  flake.modules.darwin.common = {
    # m4 is never accessed over SSH: keep Remote Login off (it listened on all
    # interfaces with password auth as the only working method — no keys were
    # ever provisioned). Outgoing SSH client config lives in homeManager below.
    services.openssh.enable = false;
  };

  flake.modules.homeManager.common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings = {
            h.HostName = config.constants.hosts.hyper.lanIp;
            ogms.HostName = "46.62.144.160";
          };
        };
      }
      (lib.mkIf pkgs.stdenv.isDarwin {
        home.file.".ssh/controlmasters/.keep".text = "";
        programs.ssh.settings = {
          "*" = {
            #identityAgent = "/Users/logikdev/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
            AddKeysToAgent = "yes";
            UseKeychain = "yes";
            ControlMaster = "auto";
            ControlPersist = "60m";
            ControlPath = "${config.home.homeDirectory}/.ssh/controlmasters/%r@%h:%p";

          };
          h = {
            RequestTTY = "yes";
            RemoteCommand = "zellij attach ssh || zellij -s ssh";
          };
        };
      })
    ];

  flake.modules.nixos.common =
    { lib, ... }:
    {
      security.pam.sshAgentAuth.enable = true;
      services.openssh = {
        enable = lib.mkDefault true;
        settings.PermitRootLogin = "no";
        settings.PasswordAuthentication = false;
        # With UsePAM yes, keyboard-interactive still accepted the account
        # password even though PasswordAuthentication was off. Key-only.
        settings.KbdInteractiveAuthentication = false;
      };

      # Accounts follow the repo exactly: no passwd/useradd/usermod drift.
      # Passwords are declarative (hashedPasswordFile from agenix); to change
      # one, update the secret and rekey.
      users.mutableUsers = false;
    };

in
{
  inherit flake;
}
