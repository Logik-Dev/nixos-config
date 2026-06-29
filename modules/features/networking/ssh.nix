{ inputs, ... }:
let

  flake.modules.darwin.common = {
    services.openssh.enable = true;
  };

  flake.modules.homeManager.common =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings = {
            h.HostName = "192.168.10.100";
            ogms.HostName = "46.62.144.160";
          };
        };
      }
      (lib.mkIf (pkgs.stdenv.isDarwin) {
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
    { ... }:
    {
      security.pam.sshAgentAuth.enable = true;
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "no";
        settings.PasswordAuthentication = false;
      };
    };

in
{
  inherit flake;
}
