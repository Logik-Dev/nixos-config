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

    darwin.common.imports = [ secretsOwner ];

    nixos.syncthing =
      { config, ... }:
      {
        imports = [ secretsOwner ];
        traefik.services.syncthing = {
          port = 8384;
          enableAuthelia = true;
          category = "Réseau & Stockage";
          icon = "di:syncthing";
        };
        networking.firewall.allowedTCPPorts = [ 22000 ];
        networking.firewall.allowedUDPPorts = [ 22000 ];
        notify.services = [ "syncthing" ];
        services.syncthing = {
          enable = true;
          user = "logikdev";
          dataDir = "/home/logikdev";
          cert = "/run/agenix/syncthing-cert.pem";
          key = "/run/agenix/syncthing-key.pem";
          guiPasswordFile = config.age.secrets.syncthing-pw.path;
          # nix = source de vérité pour les folders : ceux qui ne sont pas
          # déclarés ci-dessous sont retirés de Syncthing (les fichiers sur
          # disque, eux, ne sont pas touchés). Va de pair avec le retrait des
          # autoAcceptFolders plus bas (sinon les deux se battent).
          overrideFolders = true;
          settings = {
            gui = {
              user = config.constants.users.logikdev.username;
              insecureSkipHostcheck = true; # désactive le host check
            };
            devices = {
              # autoAcceptFolders retiré : les folders sont désormais
              # déclaratifs (overrideFolders = true). Un folder auto-accepté
              # non déclaré serait de toute façon supprimé au prochain init.
              m4.id = "LYVNDWO-CMXIN33-MHV2ZMY-CNTTTZI-FKYYYR6-LM5FJ2X-LFZILSS-N3J7TQD";
              hyper = {
                addresses = [ "tcp://${config.constants.hosts.hyper.lanIp}:22000" ];
                id = "FZPCP6F-EYN4ZIT-XD34XBB-S5QQLJD-Z36F6JG-THSP3ZA-XEA6IWJ-TOMNTAF";
              };
            };
            folders = {
              # Repo Mac <-> hyper. ID figé (oouz4-6lgje) : le modifier ferait
              # supprimer l'ancien folder (overrideFolders) et casserait la
              # synchro existante des deux côtés. paperless-consume est déclaré
              # dans home/paperless.nix et fusionne ici.
              nixos = {
                id = "oouz4-6lgje";
                label = "Nixos";
                path = "/home/logikdev/Homelab/Nixos";
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
