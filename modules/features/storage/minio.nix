{ inputs, ... }:
let

  flake.modules.nixos.hyper.imports = [
    minio
    {
      services.minio.dataDir = [
        "/mnt/ultra/minio"
      ];
    }
  ];

  flake.modules.darwin.common =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.minio-client ];
    };

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
      ...
    }:
    {
      # TODO migration to garage
      nixpkgs.config.permittedInsecurePackages = [ "minio-2025-10-15T17-29-55Z" ];
      traefik.services.minio.port = 9001;
      traefik.services.s3.port = 9000;

      services.minio = {
        enable = false;
        rootCredentialsFile = config.age.secrets.minio.path;
      };

      #notify.services = [ "minio" ];

      environment.systemPackages = [ pkgs.minio-client ];

    };

in
{
  inherit flake;
}
