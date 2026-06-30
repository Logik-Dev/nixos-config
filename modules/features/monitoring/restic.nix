{
  flake.modules.nixos.resticExporter =
    {
      config,
      pkgs,
      ...
    }:
    let
      # Build a restic-exporter systemd instance for a given repository.
      mkExporter =
        {
          name,
          port,
          repository,
        }:
        {
          description = "Prometheus restic exporter for ${name}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            DynamicUser = true;
            Restart = "always";
            CacheDirectory = "restic-exporter-${name}";
            CacheDirectoryMode = "0700";
            ExecStart = "${pkgs.prometheus-restic-exporter}/bin/restic-exporter.py";
            EnvironmentFile = config.age.secrets."restic.env".path;
            Environment = [
              "LISTEN_ADDRESS=127.0.0.1"
              "LISTEN_PORT=${toString port}"
              "REFRESH_INTERVAL=3600"
              "RESTIC_CACHE_DIR=$CACHE_DIRECTORY"
              "RESTIC_REPOSITORY=${repository}"
            ];
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
            CapabilityBoundingSet = [ "" ];
            DevicePolicy = "closed";
            LockPersonality = true;
            PrivateDevices = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            UMask = "0077";
          };
        };
    in
    {
      systemd.services = {
        "prometheus-restic-exporter-s3" = mkExporter {
          name = "s3";
          port = 9753;
          repository = "s3:https://s3.hyper.logikdev.fr/restic";
        };
        "prometheus-restic-exporter-usb" = mkExporter {
          name = "usb";
          port = 9754;
          repository = "/mnt/usb/restic";
        };
      };

      notify.services = [
        "prometheus-restic-exporter-s3"
        "prometheus-restic-exporter-usb"
      ];
    };
}
