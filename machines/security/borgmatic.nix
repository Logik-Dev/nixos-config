{ username, pkgs, ... }:
let
  notify =
    {
      msg,
      priority ? "normal",
    }:
    "${pkgs.pushr}/bin/pushr -p '${priority}' -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

  borg-restore = pkgs.writeShellApplication {
    name = "borg-restore";

    runtimeInputs = [ pkgs.borgmatic ];

    text = ''
      sudo systemctl stop vaultwarden
      sudo borgmatic extract --archive latest --repository borg # Restore latest backup
      sudo rm -rf /var/lib/vaultwarden
      sudo mv ./var/lib/vaultwarden /var/lib
      sudo systemctl start vaultwarden
    '';
  };
in
{

  environment.systemPackages = [ borg-restore ];

  services.borgmatic.enable = true;
  services.borgmatic.configurations = {
    vaultwarden = {
      source_directories = [ "/var/lib/vaultwarden" ];
      repositories = [ "ssh://${username}@borg/home/${username}/borg/security" ];
      encryption_passcommand = "${pkgs.coreutils}/bin/cat /run/secrets/borg";
      ssh_command = "ssh -i /etc/ssh/ssh_host_rsa_key";
      extra_borg_options.create = "--stats";
      keep_weekly = 4;
      keep_monthly = 6;
      before_backup = [
        (notify { msg = "Vaultwarden backup starting on {repository} ..."; })
        "borgmatic init --encryption repokey"
        "systemctl stop vaultwarden.service"
      ];
      after_backup = [
        "systemctl start vaultwarden.service"
        (notify { msg = "Vaultwarden backup complete on {repository}."; })
      ];

      on_error = [
        (notify {
          msg = "An error occured, can't complete vaultwarden backup on {repository}.";
          priority = "emergency";
        })
      ];
    };
  };

}
