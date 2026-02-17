let
  secretsOwner =
    { config, ... }:
    let
      owner = config.constants.users.logikdev.username;
    in
    {
      age.secrets."syncthing-cert.pem".owner = owner;
      age.secrets."syncthing-key.pem".owner = owner;
      age.secrets."syncthing-pw".owner = owner;
    };
in
{
  flake.modules = {

    nixos.hyper = {
      traefik.services.syncthing.port = 8384;
      networking.firewall.allowedTCPPorts = [ 22000 ];
      networking.firewall.allowedUDPPorts = [ 22000 ];
    };

    nixos.common.imports = [ secretsOwner ];

    darwin.common.imports = [ secretsOwner ];

    homeManager.common =
      { config, ... }:
      {
        services.syncthing = {
          enable = true;
          cert = "/run/agenix/syncthing-cert.pem";
          key = "/run/agenix/syncthing-key.pem";
          passwordFile = "/run/agenix/syncthing-pw";
          settings = {
            gui = {
              user = config.constants.users.logikdev.username;
              insecureSkipHostcheck = true; # désactive le host check
            };
            devices = {
              m4 = {
                id = "LYVNDWO-CMXIN33-MHV2ZMY-CNTTTZI-FKYYYR6-LM5FJ2X-LFZILSS-N3J7TQD";
                autoAcceptFolders = true;
              };
              hyper = {
                addresses = [ "tcp://192.168.10.100:22000" ];
                id = "FZPCP6F-EYN4ZIT-XD34XBB-S5QQLJD-Z36F6JG-THSP3ZA-XEA6IWJ-TOMNTAF";
                autoAcceptFolders = true;
              };
            };
            folders = {
              "${config.constants.users.logikdev.flakeDir}" = {
                id = "flake";
                devices = [
                  "hyper"
                  "m4"
                ];
              };
            };
          };
        };
      };
  };
}
