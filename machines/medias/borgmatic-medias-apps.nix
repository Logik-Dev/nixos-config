{ username, pkgs, ... }:
let
  notify =
    {
      msg,
      priority ? "normal",
    }:
    "${pkgs.pushr}/bin/pushr -p '${priority}' -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

  borg-restore-medias-apps = pkgs.writeShellApplication {
    name = "borg-restore-medias-apps";

    runtimeInputs = [ pkgs.borgmatic ];

    text = ''
      sudo systemctl stop jellyfin.service
      sudo systemctl stop prowlarr.service
      sudo systemctl stop jellyseerr.service
      sudo systemctl stop radarr.service
      sudo systemctl stop sonarr.service
      sudo borgmatic extract --archive latest --repository medias-apps # Restore latest backup
      sudo rm -rf /var/lib/jellyfin
      sudo rm -rf /var/lib/private/prowlarr
      sudo rm -rf /var/lib/private/jellyseerr
      sudo rm -rf /var/lib/radarr
      sudo rm -rf /var/lib/sonarr
      sudo mv ./var/lib/* /var/lib
      sudo systemctl start jellyfin.service
      sudo systemctl start prowlarr.service
      sudo systemctl start jellyseerr.service
      sudo systemctl start radarr.service
      sudo systemctl start sonarr.service

    '';
  };
in
{

  environment.systemPackages = [ borg-restore-medias-apps ];
  services.borgmatic.enable = true;
  services.borgmatic.configurations = {
    medias-apps = {

      # directories
      source_directories = [
        "/var/lib/jellyfin"
        "/var/lib/private/prowlarr"
        "/var/lib/private/jellyseerr"
        "/var/lib/radarr"
        "/var/lib/sonarr"
      ];

      # repository
      repositories = [
        {
          path = "ssh://${username}@borg/home/${username}/borg/medias-apps";
          label = "medias-apps";
        }
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
        "systemctl stop jellyseerr.service"
        "systemctl stop radarr.service"
        "systemctl stop sonarr.service"
      ];
      after_backup = [
        "systemctl start jellyfin.service"
        "systemctl start prowlarr.service"
        "systemctl start jellyseerr.service"
        "systemctl start radarr.service"
        "systemctl start sonarr.service"
        (notify { msg = "Medias-apps backup complete on {repository}"; })
      ];
      on_error = [
        (notify {
          msg = "An error occured, can't complete medias-apps backup.";
          priority = "emergency";
        })
      ];
    };
  };
}
