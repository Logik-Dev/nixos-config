{ inputs, ... }:
{
  flake.modules.nixos.nixos.imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  flake.modules.darwin.darwin.imports = [
    inputs.home-manager.darwinModules.home-manager
    { home-manager.backupFileExtension = "bak"; }
  ];

  # Fonction module (pas attrset statique) : `config` doit être résolu dans le
  # contexte du système darwin — sinon `config.constants` référence le `config`
  # de flake-parts (qui n'a pas l'option) → « attribute 'constants' missing ».
  flake.modules.darwin.common =
    { config, ... }:
    {
      nix.buildMachines = [
        {
          hostName = config.constants.hosts.hyper.lanIp;
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
