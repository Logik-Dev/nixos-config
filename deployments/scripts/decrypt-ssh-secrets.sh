#!/usr/bin/env bash

mkdir -p etc/ssh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for keyname in ssh_host_rsa_key ssh_host_rsa_key.pub ssh_host_ed25519_key ssh_host_ed25519_key.pub; do
  if [[ $keyname == *.pub ]]; then
    umask 0133
    cp "$SCRIPT_DIR/$keyname" "./etc/ssh/$keyname" 
  else
    umask 0177
    sops --extract '["'$keyname'"]' --decrypt "$SCRIPT_DIR/secrets.yaml" >"./etc/ssh/$keyname"
  fi
done
