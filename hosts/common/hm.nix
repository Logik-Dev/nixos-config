{
  lib,
  homelab,
  ...
}:
let
  inherit (lib) mapAttrsToList;
  inherit (builtins) concatStringsSep;

  mapHostLine = k: v: k + "," + v.ipv4 + " " + v.sshPublicKey;

  knownHosts = concatStringsSep "\n" (mapAttrsToList mapHostLine homelab.hosts);
in

{
  home.username = homelab.username;
  home.homeDirectory = "/home/${homelab.username}";
  home.stateVersion = "24.05";
  programs.ssh = {
    enable = true;
    userKnownHostsFile = "~/.ssh/known_hosts.d/known_hosts";
  };

  programs.zsh.enable = true;

  home.file = {
    ".ssh/known_hosts.d/known_hosts".text = knownHosts;
  };
}
