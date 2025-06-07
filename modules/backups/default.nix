{
  lib,
  pkgs,
  config,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
  notify =
    {
      msg,
      priority ? "normal",
    }:
    "${pkgs.pushr}/bin/pushr -p '${priority}' -t Borgmatic -K /run/secrets/borg-pushover-token -U /run/secrets/pushover-user -c '${msg}'";

  cfg = config.services.backups;
  cfgType =
    with lib.types;
    submodule {
      options = {
        source_directories = lib.mkOption {
          type = listOf str;
          default = [ ];
        };
        keep_weekly = lib.mkOption {
          type = number;
          default = 4;
        };
        keep_monthly = lib.mkOption {
          type = number;
          default = 6;
        };
        services = lib.mkOption {
          type = listOf str;
          default = [ ];
        };
      };
    };
in
{
  options.services.backups = {
    enable = lib.mkEnableOption "backups";
    configurations = lib.mkOption {
      type = lib.types.attrsOf cfgType;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.borgmatic.enable = true;
    services.borgmatic.configurations = lib.mapAttrs (name: value: {
      source_directories = value.source_directories;
      repositories = [
        {
          path = "ssh://${username}@borg/home/${username}/borg/storage/${name}";
          label = "storage";
        }
        {
          path = "ssh://${username}@borg/home/${username}/borg/usb/${name}";
          label = "usb";
        }
      ];
      encryption_passcommand = "${pkgs.coreutils}/bin/cat /run/secrets/borg";
      ssh_command = "ssh -i /etc/ssh/ssh_host_rsa_key";
      extra_borg_options.create = "--list --stats";
      keep_weekly = value.keep_weekly;
      keep_monthly = value.keep_monthly;
      relocated_repo_access_is_ok = true;
      before_backup = [
        (notify { msg = "${name} backup starting on {repository} ..."; })
        "borgmatic init --encryption repokey"
      ] ++ builtins.map (service: "systemctl stop ${service}.service") value.services;

      after_backup = builtins.map (service: "systemctl start ${service}.service") value.services ++ [
        (notify { msg = "${name} backup complete on {repository}"; })
      ];

      on_error = [
        (notify {
          msg = "An error occured, can't complete ${name} backup.";
          priority = "emergency";
        })
      ];

    }) cfg.configurations;
  };
}
