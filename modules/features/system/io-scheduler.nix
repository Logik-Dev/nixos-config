_: {
  flake.modules.nixos.io-scheduler = {
    # BFQ is the only IO scheduler on this host that honours cgroup weights and
    # ionice. Without it every IO priority knob in the tree is a placebo: the
    # four SnapRAID HDDs and the restic USB target all default to mq-deadline,
    # which ignores IOWeight *and* IOSchedulingClass/Priority — including the
    # IOSchedulingPriority=7 that the nixpkgs snapraid module already sets and
    # that has therefore never done anything.
    #
    # Measured motivation (docs/resource-control-plan.md §2.4): IO pressure
    # peaks at 51% over 7 days, in bursts at 02h (restic window) and 10h
    # (snapraid-sync, 340 GB read / 352 GB written). Memory pressure over the
    # same period peaked at 1.4% — IO is the contention that actually exists.
    #
    # CONFIG_IOSCHED_BFQ=m on this kernel, so the module is loaded explicitly.
    # Writing "bfq" to queue/scheduler does make the block layer call
    # request_module("bfq-iosched"), but depending on that autoload from a udev
    # rule is a race not worth taking.
    boot.kernelModules = [ "bfq" ];

    # Rotational devices only (sd[a-z] here, all five spinning: 4 SnapRAID data
    # /parity + the USB restic target). The two NVMe drives stay on "none":
    # BFQ's per-request accounting costs more than it can win on a device with
    # that much parallelism, and there is no measured NVMe contention to fix.
    #
    # CONFIG_BFQ_GROUP_IOSCHED=y, so this is also the prerequisite that would
    # make a per-slice IOWeight meaningful if the limits plan is ever needed
    # (plan annexe A).
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
    '';
  };
}
