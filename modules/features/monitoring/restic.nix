{
  flake.modules.nixos.resticExporter =
    {
      config,
      lib,
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
          # sftp repos (Hetzner Storage Box) need the ssh client on PATH: the
          # exporter shells out to restic which shells out to ssh.
          path = lib.optionals (lib.hasPrefix "sftp:" repository) [ pkgs.openssh ];
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
              ${lib.optionalString (lib.hasPrefix "sftp:" repository) ''
                # Stagger sftp exporters: on a deploy they all restart at once,
                # and a dozen near-simultaneous sftp sessions arms the Storage
                # Box's per-IP rate-limiter, which then refuses ports 22/23
                # for the whole egress IP until ~25 min of complete silence.
                # 0-900s spreads 13 exporters to <1 connection/min. The sleep
                # runs inside the main process (Type=simple) so it never
                # delays the nixos switch.
                sleep "$((RANDOM % 900))"
              ''}
              umask 0077
              printf '%s' "$RESTIC_PASSWORD" > "$RUNTIME_DIRECTORY/password"
              export RESTIC_PASSWORD_FILE="$RUNTIME_DIRECTORY/password"
              unset RESTIC_PASSWORD
              exec ${pkgs.prometheus-restic-exporter}/bin/restic-exporter.py
            '';
            EnvironmentFile = config.age.secrets."restic.env".path;
            # Slow the restart loop for remote repos: hammering a refused
            # connection is exactly what keeps the Storage Box rate-limiter
            # armed. 15 min: 13 exporters retrying at 5 min (≈2.6 conn/min
            # sustained) proved enough to re-trigger the block on 2026-07-04;
            # at 15 min it's <1/min. An exporter staying down longer is
            # covered by the ResticExporterDown alert.
            RestartSec = lib.mkIf (lib.hasPrefix "sftp:" repository) 900;
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
          map (inst: lib.nameValuePair "prometheus-restic-exporter-${inst.name}" (mkExporter inst)) instances
        );

        # Deliberately NOT in notify.services: exporters restart in a loop
        # while their repo is unreachable, and a per-failure push turns any
        # Storage Box outage into an ntfy flood. Exporter health is alerted
        # once, calmly, by the ResticExporterDown Prometheus rule
        # (up{job="restic"} == 0 for 30m) in prometheus.nix.
      };
    };
}
