{
  hosts,
  config,
  ...
}:

{
  programs.ssh.extraConfig = ''
    Host builder
      Port 22
      User nix-builder
      Hostname ${hosts.hyper.ipv4}
      IdentitiesOnly yes
      IdentityFile ${config.sops.secrets.nix-builder-key.path}
  '';

  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;
  nix.buildMachines = [
    {
      hostName = "builder";
      system = "x86_64-linux";
      protocol = "ssh";
      sshUser = "nix-builder";
      sshKey = "${config.sops.secrets.nix-builder-key.path}";
      maxJobs = 8;
      speedFactor = 2;
      mandatoryFeatures = [ ];
      supportedFeatures = [
        "kvm"
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
  ];
}
