{
  hostname,
  lib,
  username,
  config,
  hosts,
  inputs,
  ...
}:
let
  currentHost = if hostname == "nixos" then null else hosts.${hostname};

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
  imports = [
    ./locals.nix
    ./packages.nix
    inputs.sops-nix.nixosModules.sops
  ] ++ virtModule;

  # Update hostname after rebuild
  system.activationScripts.hostname.text = ''
    hostname ${hostname}
  '';

  networking.hostName = hostname;
  networking.extraHosts = lib.pipe hosts [
    (lib.filterAttrs (k: v: k != hostname))
    (lib.mapAttrsToList (k: v: "${k} ${v.ipv4}"))
    (lib.concatStringsSep "\n")
  ];

  # OpenSSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = false;
  security.pam.sshAgentAuth.enable = true;

  #services.openssh.settings.AllowUsers = [ username ];

  # Common secrets
  sops.defaultSopsFile = ../../secrets/common.yaml;
  sops.secrets.borg = { };
  sops.secrets."borg-pushover-token" = { };
  sops.secrets."pushover-user" = { };
  sops.secrets.password.neededForUsers = true;

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

  system.stateVersion = "25.05";
}
