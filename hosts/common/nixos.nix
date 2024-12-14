{
  config,
  pkgs,
  homelab,
  host,
  ...
}:
{

  imports = [
    ./locals.nix
  ];

  networking = {
    hostName = host.hostname;
    networkmanager.enable = true;
    extraHosts = pkgs.lib.pipe (builtins.attrNames homelab.hosts) [
      (builtins.filter (name: homelab.hosts.${name}.ipv4 != null))
      (map (name: homelab.hosts.${name}.ipv4 + " " + name))
      (builtins.concatStringsSep "\n")
    ];
  };

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };

  boot.loader.efi.canTouchEfiVariables = true;

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ stdenv.cc.cc ];
  };

  services.openssh.enable = true;
  security.pam.sshAgentAuth.enable = true;
  security.sudo.wheelNeedsPassword = false;

  sops.secrets.password = {
    sopsFile = ./secrets.yaml;
    neededForUsers = true;
  };

  users.users.${homelab.username} = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.password.path;
    openssh.authorizedKeys.keyFiles = [ ../sonicmaster/id_ed25519.pub ];
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
  ];

  nix = {
    nixPath = [ "nixpkgs=${pkgs.path}" ];
    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "@wheel"
        "root"
        homelab.username
      ];
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
    };
    gc.dates = "weekly";
  };

  services.printing.enable = true;

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 3;
    };
  };

  system.stateVersion = "24.05";
}
