{ inputs, ... }:
let
  nixCommon = {
    nixpkgs.config.allowUnfree = true;
    nix = {
      optimise.automatic = true;
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # used by nixd
      settings = {
        trusted-users = [
          "root"
          "@wheel"
          "logikdev"
        ];
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
        auto-optimise-store = true;
      };
    };
  };
in
{
  flake.modules = {
    darwin.common = {
      imports = [ nixCommon ];
      nix.gc.automatic = true;
    };

    nixos.common = {
      imports = [ nixCommon ];
      nix.gc.automatic = true;
      nix.gc.dates = "weekly";

      # A build runs up to 8 parallel jobs and used to compete with Jellyfin and
      # Postgres at strictly equal priority (nix-daemon was CPUSchedulingPolicy
      # OTHER, Nice=0). SCHED_IDLE fixes that without throttling anything: on an
      # otherwise idle machine the build still gets every core, it only ever
      # yields to a task that is actually runnable.
      nix.daemonCPUSchedPolicy = "idle";

      # IO deliberately stays in the best-effort class at its lowest priority,
      # rather than the "idle" class: nixpkgs warns that idle IO "might slow
      # down or starve crucial configuration updates during load", and a deploy
      # here is interactive — someone is waiting on `nh os switch`. The
      # asymmetry with the CPU setting costs close to nothing, because /nix
      # lives on the NVMe where the scheduler is "none" and ionice has no effect
      # at all (see system/io-scheduler.nix).
      nix.daemonIOSchedClass = "best-effort";
      nix.daemonIOSchedPriority = 7;
    };

  };
}
