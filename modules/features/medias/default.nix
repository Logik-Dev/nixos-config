{
  flake.modules.nixos.hyper = {
    systemd.tmpfiles.rules = [
      "d /mnt/storage 2755 logikdev media - -"
      "d /mnt/storage/medias 2755 logikdev media - -"
      "d /mnt/ultra 2755 logikdev media - -"
    ];
  };
}
