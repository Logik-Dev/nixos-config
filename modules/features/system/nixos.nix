{ inputs, ... }:
{
  flake.modules.nixos.nixos.imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  flake.modules.nixos.sonicmaster = {

    nix.buildMachines = [
      {
        hostName = "192.168.10.100";
        sshUser = "logikdev";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        # if the builder supports building for multiple architectures,
        # replace the previous line by, e.g.
        # systems = ["x86_64-linux" "aarch64-linux"];
        maxJobs = 1;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        mandatoryFeatures = [ ];
      }
    ];
    nix.distributedBuilds = true;
    # optional, useful when the builder has a faster internet connection than yours
    nix.extraOptions = ''
      	  builders-use-substitutes = true
      	'';
  };
}
