_: {
  flake.modules.nixos.beets =
    { pkgs, ... }:
    let
      beet = import ./lib/_beet-classique.nix { inherit pkgs; };
    in
    {
      environment.systemPackages = [
        pkgs.unflac
        beet.package
      ];
      systemd.tmpfiles.rules = [
        "d /mnt/ultra/beets-classique 2775 logikdev media - -"
        "d /var/log/beets-classique 2775 logikdev media - -"
      ];
      backups.sources.beets = {
        paths = [ "/mnt/ultra/beets-classique" ];
        manageService = false; # pas d'unité beets.service
      };
    };
}
