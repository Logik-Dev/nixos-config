{
  flake.modules.nixos.resticExporter =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Build a restic-exporter systemd instance for a given repository.
      mkExporter =
        {
          name,
          port,
          repository,
          # Local filesystem repos (e.g. the USB/local ones) are owned by root
          # with 0700 perms, so a DynamicUser cannot read them. Run as root for
          # those; only remote (s3:) repos can use a DynamicUser.
          dynamicUser ? true,
          ...
        }:
        {
          description = "Prometheus restic exporter for ${name}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            DynamicUser = dynamicUser;
            Restart = "always";
            CacheDirectory = "restic-exporter-${name}";
            CacheDirectoryMode = "0700";
            RuntimeDirectory = "restic-exporter-${name}";
            RuntimeDirectoryMode = "0700";
            # restic-exporter.py requires RESTIC_PASSWORD_FILE (a path), while
            # restic.env only ships RESTIC_PASSWORD. Materialize the password
            # into a runtime file before launching the exporter.
            ExecStart = pkgs.writeShellScript "restic-exporter-${name}-start" ''
              umask 0077
              printf '%s' "$RESTIC_PASSWORD" > "$RUNTIME_DIRECTORY/password"
              export RESTIC_PASSWORD_FILE="$RUNTIME_DIRECTORY/password"
              unset RESTIC_PASSWORD
              exec ${pkgs.prometheus-restic-exporter}/bin/restic-exporter.py
            '';
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

      # Derive one exporter per (source × repository), mirroring the layout in
      # storage/restic.nix where each source is backed up to
      # <targetPath>/restic/<sourceName>. Ports are assigned deterministically
      # from a base; attribute iteration order is stable (sorted keys).
      basePort = 9760;
      instances = lib.imap0 (index: inst: inst // { port = basePort + index; }) (
        lib.flatten (
          lib.mapAttrsToList (
            sourceName: sourceValue:
            lib.mapAttrsToList (_targetName: targetPath: {
              name = "${sourceName}-${_targetName}";
              repository = "${targetPath}/restic/${sourceName}";
              dynamicUser = lib.hasPrefix "s3:" targetPath;
            }) (sourceValue.defaultRepositories // sourceValue.extraRepositories)
          ) config.backups.sources
        )
      );
    in
    {
      options.resticExporters = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        internal = true;
        default = [ ];
        description = "Generated restic exporter instances (name, port, repository), consumed by prometheus scrape configs.";
      };

      config = {
        resticExporters = instances;

        systemd.services = lib.listToAttrs (
          map (
            inst: lib.nameValuePair "prometheus-restic-exporter-${inst.name}" (mkExporter inst)
          ) instances
        );

        notify.services = map (inst: "prometheus-restic-exporter-${inst.name}") instances;
      };
    };
}
