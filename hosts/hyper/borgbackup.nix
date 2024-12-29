{ config, pkgs, ... }:
{

  users.users.logikdev.extraGroups = [ "borg " ];

  sops.secrets.borg = {
    sopsFile = ../common/secrets.yaml;
  };

  services.borgbackup.repos.machines = {
    path = "/mnt/raid/backups/machines/security";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHDUL/6nZq80/VwN/oVU6GDctoGHOhvP/F7axuiQeZXQ"
    ];
    allowSubRepos = true;
  };

  services.borgbackup.repos.services = {
    path = "/mnt/backups/services";
    allowSubRepos = true;
    authorizedKeys =
      let
        securityKey = builtins.readFile ../security/ssh_host_rsa_key.pub;
      in
      [ securityKey ];
  };

  services.borgbackup.jobs = {
    security = {

      repo = "/mnt/raid/backups/machines/security";
      preHook = ''
        ${pkgs.incus}/bin/incus snapshot create security borg
      '';
      postHook = "${pkgs.incus}/bin/incus snapshot delete security borg";
      paths = "/var/lib/incus/virtual-machines-snapshots/security/borg";
      encryption.passCommand = "${pkgs.coreutils}/bin/cat /run/secrets/borg";
      encryption.mode = "repokey";
      doInit = true;
    };
  };
}
