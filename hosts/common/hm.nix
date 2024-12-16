{ homelab, pkgs, ... }:
let
  knownHosts = pkgs.lib.pipe (builtins.attrNames homelab.hosts) [
    (map (host: host + "," + homelab.hosts.${host}.ipv4 + " " + homelab.hosts.${host}.sshPublicKey))
    (builtins.concatStringsSep "\n")
  ];
in
/*
   knownHosts = builtins.concatStringsSep "\n" (
    map (name: name + "," + homelab.hosts.${name}.ipv4 + " " + homelab.hosts.${name}.sshPublicKey) (
      builtins.attrNames homelab.hosts
    )
  );
*/
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
