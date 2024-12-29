{ homelab, pkgs, ... }:
let
  user = homelab.username;
in
/*
  borg-restore = pkgs.writeShellApplication {
    name = "borg-restore";

    runtimeInputs = [ pkgs.borgmatic ];

    text = ''
      sudo systemctl stop vaultwarden
      sudo borgmatic extract --archive latest --repository raid # Restore latest backup from RAID repo
      sudo rm -rf /var/lib/bitwarden_rs
      sudo mv ./var/lib/bitwarden_rs /var/lib
      sudo systemctl start vaultwarden
    '';
  };
*/
{

  # environment.systemPackages = [ borg-restore ];

  services.borgmatic.enable = true;
  services.borgmatic.settings = {

    source_directories = [
      "/var/lib/jellyfin"
      "/var/lib/prowlarr"
      "/var/lib/radarr"
      "/var/lib/sonarr"
    ];
    repositories =
      map
        (repo: {
          path = "${user}@borg:/home/${user}/${repo}/medias"; # init not working with 'ssh://' prefix
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
    ];

  };

}
