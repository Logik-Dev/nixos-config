{ username, pkgs, ... }:
let
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
    photos = {

      source_directories = [
        "/mnt/photos/immich"
      ];
      repositories = [
        {
          path = "ssh://${username}@borg/home/${username}/borg/photos";
          label = "photos";
        }
      ];

      encryption_passcommand = "${pkgs.coreutils}/bin/cat /run/secrets/borg";
      ssh_command = "ssh -i /etc/ssh/ssh_host_rsa_key";
      extra_borg_options.create = "--stats";
      keep_weekly = 4;
      keep_monthly = 6;
      before_backup = [
        (notify { msg = "Photos backup starting on {repository} ..."; })
        "borgmatic init --encryption repokey"
        "systemctl stop immich-server.service"
        "systemctl stop immich-machine-learning.service"
      ];
      after_backup = [
        "systemctl start immich-server.service"
        "systemctl start immich-machine-learning.service"
        (notify { msg = "Photos backup complete on {repository}"; })
      ];
      on_error = [
        (notify {
          msg = "An error occured, can't complete photos backup.";
          priority = "emergency";
        })
      ];
    };
  };
}
