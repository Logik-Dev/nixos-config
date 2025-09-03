{ config, pkgs, ... }:
{

  services.traefik-proxy.services.s3.port = 9000;
  services.traefik-proxy.services.minio.port = 9001;

  sops.secrets.minio = {
    sopsFile = ../../secrets/minio.hyper.env;
    format = "dotenv";
    key = "";
  };

  services.minio = {
    enable = true;
    rootCredentialsFile = config.sops.secrets.minio.path;
    dataDir = [ "/mnt/storage/archives/minio" ];
  };

  # Minio CLI for backup operations
  environment.systemPackages = [ pkgs.minio-client ];

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
      source ${config.sops.secrets.minio.path}
      
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
}
