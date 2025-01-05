{ homelab, pkgs, ... }:
let
  user = homelab.username;

  notify =
    {
      msg,
      priority ? "normal",
    }:
    "${pkgs.pushr}/bin/pushr -p '${priority}' -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

in
{

  services.borgmatic.enable = true;
  services.borgmatic.configurations = {
    medias = {

      source_directories = [
        "/var/lib/jellyfin"
        "/var/lib/prowlarr"
        "/var/lib/radarr"
        "/var/lib/sonarr"
      ];
      repositories =
        map
          (repo: {
            path = "ssh://${user}@borg/home/${user}/${repo}/medias";
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
        (notify { msg = "Medias backup starting on {repository} ..."; })
        "borgmatic init --encryption repokey"
        "systemctl stop jellyfin.service"
        "systemctl stop prowlarr.service"
        "systemctl stop radarr.service"
        "systemctl stop sonarr.service"
      ];
      after_backup = [
        "systemctl start jellyfin.service"
        "systemctl start prowlarr.service"
        "systemctl start radarr.service"
        "systemctl start sonarr.service"
        (notify { msg = "Medias backup complete on {repository}"; })
      ];
      on_error = [
        (notify {
          msg = "An error occured, can't complete medias backup.";
          priority = "emergency";
        })
      ];
    };
  };
}
