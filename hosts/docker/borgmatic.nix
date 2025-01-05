{ homelab, pkgs, ... }:
let
  notify =
    {
      msg,
      priority ? "normal",
    }:
    "${pkgs.pushr}/bin/pushr -p '${priority}' -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

  user = homelab.username;

in
{
  services.borgmatic.enable = true;
  services.borgmatic.configurations = {
    containers = {
      source_directories = [
        "/var/lib/containers"
      ];
      repositories =
        map
          (repo: {
            path = "ssh://${user}@borg/home/${user}/${repo}/containers";
            label = repo;
          })
          [
            "backups"
            "raid"
            "archives"
          ];
      encryption_passcommand = "${pkgs.coreutils}/bin/cat /run/secrets/borg";
      ssh_command = "ssh -i /etc/ssh/ssh_host_rsa_key";
      extra_borg_options.create = "--stats";
      keep_weekly = 4;
      keep_monthly = 6;
      before_backup = [
        (notify { msg = "Containers backup starting on {repository} ..."; })
        "borgmatic init --encryption repokey"
        "systemctl stop podman-qbittorrent.service"
      ];
      after_backup = [
        "systemctl start podman-qbittorrent.service"
        (notify { msg = "Containers backup complete on {repository}."; })
      ];

      on_error = [
        (notify {
          msg = "An error occured, can't complete containers backup on {repository}.";
          priority = "emergency";
        })
      ];
    };
  };
}
