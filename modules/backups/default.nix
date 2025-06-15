{
  lib,
  pkgs,
  config,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
  inherit (import ./scripts.nix { inherit pkgs; })
    startServices
    stopServices
    restoreDirectories
    restorePostgresql
    ;

  cfg = config.services.backups;

  cfgType =
    with lib.types;
    submodule {
      options = {
        source_directories = lib.mkOption {
          description = "List of directories to backup";
          type = listOf str;
          default = [ ];
        };
        keep_weekly = lib.mkOption {
          description = "How many weekly backup to keep";
          type = number;
          default = 4;
        };
        keep_monthly = lib.mkOption {
          description = "How many monthly backup to keep";
          type = number;
          default = 6;
        };
        services = lib.mkOption {
          description = "List of services to stop before backup and restart after";
          type = listOf str;
          default = [ ];
        };
        postgresql_databases = lib.mkOption {
          description = "List of Postgresql databases to dump";
          type = listOf attrs;
          default = [ ];
        };
        repositories = lib.mkOption {
          description = "List of targeted repositories. Possible values: storage, usb, hetzner. All by defaults";
          type = listOf str;
          default = [
            "storage"
            "usb"
            "hetzner"
          ];
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

    # generate restore scripts
    environment.systemPackages = builtins.attrValues (
      builtins.mapAttrs (
        config: value:
        pkgs.writeShellScriptBin "${config}-restore" ''
          ${stopServices value.services}/bin/stop-services
          ${restorePostgresql config value.postgresql_databases}/bin/restore-databases
          ${restoreDirectories config value.source_directories}/bin/restore-directories
          ${startServices value.services}/bin/start-services
        ''
      ) cfg.configurations
    );

    services.borgmatic.enable = true;
    services.borgmatic.configurations = lib.mapAttrs (name: value: {
      archive_name_format = "${name}-{now}";
      source_directories = value.source_directories;
      postgresql_databases = value.postgresql_databases;
      encryption_passcommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.borg.path}";
      ssh_command = "ssh -i /etc/ssh/ssh_host_rsa_key";
      extra_borg_options.create = "--list --stats";
      keep_weekly = value.keep_weekly;
      keep_monthly = value.keep_monthly;
      relocated_repo_access_is_ok = true;
      read_special = value.postgresql_databases != [ ]; # read special is needed for databases hooks

      # repositories
      repositories = builtins.filter (e: lib.elem e.label value.repositories) [
        {
          path = "ssh://${username}@borg/./borg/storage/${name}";
          label = "storage";
        }
        {
          path = "ssh://${username}@borg/./borg/usb/${name}";
          label = "usb";
        }
        {
          path = "ssh://hetzner/./borg/${name}";
          label = "hetzner";
        }
      ];

      # actions
      commands = [
        {
          # init repository and stop services before backup
          before = "configuration";
          when = [ "create" ];
          run = [
            "echo 'starting backup for ${name}...'"
            "echo 'init repository if needed...'"
            "borgmatic init --encryption repokey"
            "echo 'stopping services...'"
          ] ++ builtins.map (service: "systemctl stop ${service}.service") value.services;
        }
        {
          # restart services after backup (even on fail)
          after = "configuration";
          when = [ "create" ];
          run = [
            "echo 'restarting services...'"
          ] ++ builtins.map (service: "systemctl start ${service}.service") value.services;
        }
        {
          # log success when finished
          after = "configuration";
          when = [ "create" ];
          states = [ "finish" ];
          run = [
            "echo '${name} backup successful!'"
          ];
        }
      ];

      # checks
      checks = [
        {
          name = "data"; # check data integrity
          frequency = "1 week";
          only_run_on = [ "Monday" ];
        }
      ];

      # notifications
      pushover = {
        token = "{credential file ${config.sops.secrets.borg-pushover-token.path}}";
        user = "{credential file ${config.sops.secrets.pushover-user.path}}";
        start = {
          title = "Backup Started";
          message = "<b>${name}</b> backup started";
          priority = -2;
          html = true;
        };
        finish = {
          title = "Backup Finished";
          message = "<b>${name}</b> backup finished";
          priority = 0;
          html = true;
        };
        fail = {
          title = "Backup Failed";
          message = "<b>${name}</b> backup <font color='#ff6961'>failed</font>";
          priority = 2;
          html = true;
          sound = "siren";
        };
        states = [
          "start"
          "finish"
          "fail"
        ];
      };

    }) cfg.configurations;
  };
}
