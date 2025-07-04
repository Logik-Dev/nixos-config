{
  pkgs,
  domain,
  hostname,
  lib,
  username,
  config,
  hosts,
  inputs,
  hetzner_user,
  ...
}:
let
  currentHost = if hostname == "nixos" then null else hosts.${hostname};

  remote-builder = if currentHost == "hyper" then [ ] else [ ./remote-builder.nix ];

  # Virtualisation module for LXD
  virtModule =
    if isNull currentHost then
      [ ]
    else if currentHost.platform == "container" then
      [ "${inputs.nixpkgs}/nixos/modules/virtualisation/lxc-container.nix" ]
    else if currentHost.platform == "virtual-machine" then
      [ "${inputs.nixpkgs}/nixos/modules/virtualisation/lxd-virtual-machine.nix" ]
    else
      [ ];
in
{
  imports =
    [
      ./locals.nix
      ./packages.nix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ virtModule
    ++ remote-builder;

  # Update hostname after rebuild
  system.activationScripts.hostname.text = ''
    hostname ${hostname}
  '';

  networking.hostName = hostname;
  networking.extraHosts = lib.pipe hosts [
    (lib.filterAttrs (k: v: k != hostname))
    (lib.mapAttrsToList (k: v: "${v.ipv4} ${k}"))
    (lib.concatStringsSep "\n")
  ];

  # OpenSSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = false;
  security.pam.sshAgentAuth.enable = true;
  programs.ssh.knownHosts =
    {
      "${hetzner_user}.your-storagebox.de".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
    }
    // lib.mapAttrs' (k: v: {
      name = "${k},${v.ipv4}";
      value = {
        publicKeyFile = ../../machines/${k}/keys/ssh_host_ed25519_key.pub;
      };
    }) hosts;

  programs.ssh.extraConfig = ''
    Host hetzner
      Port 23
      User ${hetzner_user}
      HostName ${hetzner_user}.your-storagebox.de
  '';

  # Common secrets
  sops.defaultSopsFile = ../../secrets/common.yaml;
  sops.secrets.borg = { };
  sops.secrets."borg-pushover-token" = { };
  sops.secrets."pushover-user" = { };
  sops.secrets.password.neededForUsers = true;
  sops.secrets.nix-builder-key = {
    sopsFile = ../../secrets/common.yaml;
    owner = "root";
    path = "/root/.ssh/nix-builder-key";
    mode = "0600";
  };

  # Common users
  users.groups.media.gid = lib.mkForce 991;
  security.sudo.wheelNeedsPassword = false;
  users.users.${username} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.password.path;
    openssh.authorizedKeys.keyFiles = [
      ../sonicmaster/keys/id_ed25519.pub
    ];
  };

  # Nix config
  nixpkgs.config.allowUnfree = true;
  nix = {
    gc.dates = "monthly";
    settings = {
      auto-optimise-store = true;
      substituters = [ "http://${hosts.hyper.ipv4}:5000" ];
      trusted-public-keys = [ "builer-cache-1:3sC3Wme/HyYHJptBwGX4nDxXLdLvBx4Q+BdTBTZmQZA=" ];
      trusted-users = [
        "@wheel"
        "root"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
    };
  };

  /*
    services.vmagent = {
      enable = true;

      remoteWrite = {
        url = "http://logs.${domain}/loki/api/v1/push";
      };

      prometheusConfig = {
        url = "https://logs.${domain}";
        labels = {
          job = "systemd-journal";
          host = hostname;
        };
        journalScrapeConfig = {
          directory = "/var/log/journal";
          use_notify = true;
          max_age = "24h";
          label_map = {
            "_SYSTEMD_UNIT" = "unit";
            "_HOSTNAME" = "host";
          };
        };
      };
    };
  */

  system.stateVersion = "25.05";
}
