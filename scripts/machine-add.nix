{ pkgs, ... }:
let
  machine-add = pkgs.writeShellScriptBin "machine-add" ''
    set -e
    TMP=$(mktemp -d)
    HOSTNAME=$1
    MACHINE_DIR="$FLAKE/machines/$HOSTNAME"
    TMP_KEYS_DIR="$TMP/$HOSTNAME/keys"
    HOST_RSA="ssh_host_rsa_key"
    HOST_ED25519="ssh_host_ed25519_key"
    SOPS_SECRET_FILE="$FLAKE/secrets/$HOSTNAME.yaml"

    cleanup(){
      echo "Clean temp directory..."
      rm -rf "$TMP"
    }
    trap cleanup EXIT

    if [ -z $HOSTNAME ]; then
      echo "No hostname supplied"
      echo "Usage: $0 <hostname>"
      exit 1
    fi

    if [ -d $MACHINE_DIR ]; then
      echo "Machine directory exists, skipping"
      exit 1
    fi

    echo "Generate ssh host keys..."
    mkdir -p "$TMP/$HOSTNAME/keys"
    ssh-keygen -q -N "" -t rsa -b 4096 -f "$TMP_KEYS_DIR/$HOST_RSA"
    ssh-keygen -q -N "" -t ed25519 -f "$TMP_KEYS_DIR/$HOST_ED25519"

    echo "Generate age public key..."
    ssh-to-age -i "$TMP/$HOSTNAME/keys/$HOST_ED25519.pub" -o "$TMP_KEYS_DIR/age.pub"

    echo "Insert ssh private keys in password store..."
    pass insert -f -m homelab/hosts/$HOSTNAME/$HOST_RSA < $TMP_KEYS_DIR/$HOST_RSA
    pass insert -f -m homelab/hosts/$HOSTNAME/$HOST_ED25519 <  $TMP_KEYS_DIR/$HOST_ED25519

    echo "Create hostname directory and copy public keys..."
    mkdir -p "$MACHINE_DIR"/keys
    cp "$TMP_KEYS_DIR"/*.pub "$MACHINE_DIR"/keys

    echo "Generate default.nix..."
    echo "{...}: {}" > "$MACHINE_DIR"/default.nix

    echo "Add new files to git"
    git add "$MACHINE_DIR"

    echo "Regenerate .sops.yaml..."
    nix run .#sops-config-gen

    echo "Update keys for common secrets..."
    sops updatekeys "$FLAKE"/secrets/common.yaml


    echo "💾 Writing secrets to $SOPS_SECRET_FILE (unencrypted for now)..."

    cat > "$SOPS_SECRET_FILE" <<EOF
    ssh_host_rsa_key: |
    $(sed 's/^/  /' "$TMP_KEYS_DIR/$HOST_RSA")

    ssh_host_ed25519_key: |
    $(sed 's/^/  /' "$TMP_KEYS_DIR/$HOST_ED25519")
    EOF

    echo "🔐 Encrypting with sops..."
    sops --encrypt --in-place "$SOPS_SECRET_FILE"

    echo "✅ SSH keys stored and encrypted in: $SOPS_SECRET_FILE"

  '';
in
machine-add
