{ ... }:
let

  flake.modules.nixos.hyper.imports = [
    backup
    minio
    {
      services.minio.dataDir = [
        "/mnt/ultra/minio"
      ];
    }
  ];

  flake.modules.nixos.common =
    { pkgs, ... }:
    let
      createBucket = pkgs.writeShellScriptBin "create-bucket" ''

        set -euo pipefail

        if [ $# -ne 1 ]; then
            echo "Usage: $0 BUCKET_NAME"
            exit 1
        fi

        BUCKET_NAME="$1"
        MINIO_ALIAS="hyper"
        PASS_PATH="minio/$BUCKET_NAME"

        # Create bucket
        mc mb "$MINIO_ALIAS/$BUCKET_NAME" 2>/dev/null || true

        # Enable versioning
        mc version enable "$MINIO_ALIAS/$BUCKET_NAME"

        # Generate password with pass
        pass generate -n "$PASS_PATH" 40 > /dev/null

        # Create user (password read from stdin, not stored in variable)
        pass show "$PASS_PATH" | mc admin user add "$MINIO_ALIAS" "$BUCKET_NAME" --password-stdin > /dev/null 2>&1 || \
            mc admin user add "$MINIO_ALIAS" "$BUCKET_NAME" "$(pass show "$PASS_PATH")" > /dev/null 2>&1

        # Apply readwrite policy
        mc admin policy attach $MINIO_ALIAS readwrite --user="$BUCKET_NAME"

        # Add metadata to pass entry
        {
            pass show "$PASS_PATH"
            echo "access_key: $BUCKET_NAME"
            echo "bucket: $BUCKET_NAME"
        } | pass insert -m -f "$PASS_PATH" > /dev/null

        echo "✅ Bucket '$BUCKET_NAME' created"
        echo "📦 Password stored in: $PASS_PATH"

      '';
    in
    {
      environment.systemPackages = [
        createBucket
        pkgs.minio-client
      ];
    };

  minio =
    {
      config,
      pkgs,
      commonSecret,
      ...
    }:
    {
      services.reverse-proxy.vhosts.s3 = {
        port = 9000;
        extraConfig = ''
          client_max_body_size 1024m;
          proxy_request_buffering off;
          proxy_set_header Connection "";
          proxy_connect_timeout 300s;
          proxy_send_timeout 300s;
          proxy_read_timeout 300s;
        '';
      };
      services.reverse-proxy.vhosts.minio = {
        port = 9001;
        enableWebsockets = true;
      };

      age.secrets.minio.rekeyFile = commonSecret "minio";

      services.minio = {
        enable = true;
        rootCredentialsFile = config.age.secrets.minio.path;
      };

      environment.systemPackages = [ pkgs.minio-client ];
    };

  backup =
    { pkgs, config, ... }:
    {
      # Backup script
      systemd.services.minio-backup = {
        description = "Minio backup service";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
        };
        script = ''
          set -euo pipefail

          # Source minio credentials
          source ${config.age.secrets.minio.path}

          # Backup directory
          BACKUP_DIR="/mnt/usb/backups/minio"

          # Create backup directory
          ${pkgs.coreutils}/bin/mkdir -p "$BACKUP_DIR"

          # Configure mc client
          ${pkgs.minio-client}/bin/mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

          # Mirror all buckets to backup location
          for bucket in $(${pkgs.minio-client}/bin/mc ls local --json | ${pkgs.jq}/bin/jq -r 'select(.type=="folder") | .key'); do
            echo "Backing up bucket: $bucket"
            ${pkgs.minio-client}/bin/mc mirror "local/$bucket" "$BACKUP_DIR/$bucket"
          done

          echo "Backup completed successfully to $BACKUP_DIR"
        '';
        path = with pkgs; [
          coreutils
          findutils
          minio-client
          jq
        ];
      };

      # Timer for daily backups
      systemd.timers.minio-backup = {
        description = "Minio backup timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1min";
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };
    };
in
{
  inherit flake;
}
