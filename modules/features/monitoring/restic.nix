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
                # Stagger sftp exporters ONLY on mass-start events (boot or
                # nixos switch): dozens of near-simultaneous sftp sessions arm
                # the Storage Box's per-IP rate-limiter, which then refuses
                # ports 22/23 for the whole egress IP until ~25 min of silence.
                # 48 exporters × RANDOM % 3000 spreads them to <1 conn/min.
                # An isolated restart (crash, repo not yet created) must not
                # sleep again — that left exporters down ~50 min and fired
                # false ResticExporterDown alerts on 2026-09-24.
                if [ "$(( $(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y /run/current-system) ))" -lt 900 ]; then
                  sleep "$((RANDOM % 3000))"
                fi
              ''}
              umask 0077
              printf '%s' "$RESTIC_PASSWORD" > "$RUNTIME_DIRECTORY/password"
              export RESTIC_PASSWORD_FILE="$RUNTIME_DIRECTORY/password"
              unset RESTIC_PASSWORD
              # $CACHE_DIRECTORY must be expanded here, at runtime: systemd does
              # NOT expand variables inside Environment= (it would be passed to
              # restic literally, which then tries to `mkdir $CACHE_DIRECTORY` on
              # the read-only fs and fails under the stricter modern restic).
              export RESTIC_CACHE_DIR="$CACHE_DIRECTORY"
              exec ${pkgs.prometheus-restic-exporter}/bin/restic-exporter.py
            '';
            EnvironmentFile = config.age.secrets."restic.env".path;
            # Slow the restart loop for remote repos: hammering a refused
            # connection is exactly what keeps the Storage Box rate-limiter
            # armed. The 2026-07-04 storm was ~13 exporters retrying every
            # 5 min (≈2.6 conn/min) — with 48 exporters, 60 min keeps the
            # sustained rate under 1 conn/min. An exporter staying down longer
            # is covered by the ResticExporterDown alert. Local repos get
            # 5 min: a freshly added source has no repo until its first backup,
            # and the default RestartSec tripped systemd's start limit on
            # 2026-09-24 (start-limit-hit) instead of retrying.
            RestartSec = if lib.hasPrefix "sftp:" repository then 3600 else 300;
            Environment = [
              "LISTEN_ADDRESS=127.0.0.1"
              "LISTEN_PORT=${toString port}"
              "REFRESH_INTERVAL=3600"
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
        # (up{job="restic"} == 0 for 75m) in prometheus.nix.
      };
    };
}
