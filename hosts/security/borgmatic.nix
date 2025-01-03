{ homelab, pkgs, ... }:
let
  notify =
    msg:
    "${pkgs.pushr}/bin/pushr -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

  user = homelab.username;

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
in
{

  environment.systemPackages = [ borg-restore ];

  services.borgmatic.enable = true;
  services.borgmatic.configurations = {
    vaultwarden = {
      source_directories = [
        "/var/lib/bitwarden_rs"
      ];
      repositories =
        map
          (repo: {
            path = "${user}@borg:/home/${user}/${repo}/security"; # init not working with 'ssh://' prefix
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
        (notify "Vaultwarden backup starting...")
        "borgmatic init --encryption repokey"
        "systemctl stop vaultwarden.service"
      ];
      after_backup = [
        "systemctl start vaultwarden.service"
        (notify "Vaultwarden backup complete.")
      ];

      on_error =
        let
          cmd = notify "An error occured, can't complete vaultwarden backup.";
        in
        [
          (cmd + " -p emergency")
        ];
    };
  };
}
