{
  config,
  pkgs,
  homelab,
  host,
  lib,
  inputs,
  ...
}:
let
  inherit (lib) mapAttrs' mapAttrsToList nameValuePair;
  inherit (builtins) concatStringsSep;
in
{

  imports = [
    ./locals.nix
  ];

  nixpkgs.overlays = [
    (final: prev: {
      pushr = inputs.pushr.defaultPackage.${pkgs.system};
    })
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    fira-code-symbols
  ];

  sops.defaultSopsFile = ./secrets.yaml;

  sops.secrets.borg = { };
  sops.secrets."borg-pushover-token" = { };
  sops.secrets."pushover-user" = { };

  networking = {
    nameservers = [
      "192.168.11.53"
      "9.9.9.9"
    ];
    hostName = host.hostname;
    networkmanager.enable = true;
    extraHosts = concatStringsSep "\n" (mapAttrsToList (k: v: v.ipv4 + " " + k) homelab.hosts);
  };

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ stdenv.cc.cc ];
  };

  services.openssh.enable = true;
  services.openssh.knownHosts = mapAttrs' (
    hostname: val:
    nameValuePair hostname {
      hostNames = [
        hostname
        val.ipv4
      ];
      publicKeyFile = ../${hostname}/keys/ssh_host_rsa_key.pub;
    }
  ) homelab.hosts;

  security.pam.sshAgentAuth.enable = true;
  security.sudo.wheelNeedsPassword = false;

  sops.secrets.password = {
    sopsFile = ./secrets.yaml;
    neededForUsers = true;
  };

  users.users.${homelab.username} = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.password.path;
    openssh.authorizedKeys.keyFiles = [ ../sonicmaster/keys/id_ed25519.pub ];
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    borgbackup
    curl
    git
    htop
    pushr
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

  system.stateVersion = "24.05";
}
