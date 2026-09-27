_:
let

  flake.modules.nixos.hyper = {

    systemd.tmpfiles.rules = [
      "d /mnt/parity1 0755 root root -"
      "d /mnt/parity2 0755 root root -"
    ];

    # The nixpkgs snapraid module creates snapraid-sync.service and
    # snapraid-scrub.service (each with its own timer) — there is no plain
    # "snapraid.service". Naming "snapraid" here only spawned a phantom
    # snapraid.service that never runs, leaving sync/scrub failures silent
    # (diverging parity with no alert). Wire OnFailure to the real units.
    notify.services = [
      "snapraid-sync"
      "snapraid-scrub"
    ];

    services.snapraid = {
      enable = true;
      sync.interval = "10:30";
      dataDisks = {
        data1 = "/mnt/medias1";
        data2 = "/mnt/medias2";
      };
      parityFiles = [
        "/mnt/parity1/snapraid.parity"
        "/mnt/parity2/snapraid.parity"
      ];
      contentFiles = [
        "/mnt/local/.snapraid.content"
        "/mnt/ultra/.snapraid.content"
        "/mnt/medias1/.snapraid.content"
        "/mnt/medias2/.snapraid.content"
      ];
      exclude = [
        "/lost+found/"
      ];
    };
  };
in
{
  inherit flake;
}
