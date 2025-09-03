# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a simplified NixOS configuration repository that manages a single homelab server (`hyper`). The infrastructure is defined using Nix flakes and includes secrets management with SOPS.

## Common Commands

### Building and Deploying

- `nixos-rebuild switch --flake .#hyper` - Build and switch to configuration for the hyper server
- `nix flake update` - Update flake inputs
- `nix flake check` - Validate flake configuration

### Secrets Management

- `sops secrets/<file>.yaml` - Edit encrypted secrets files

## Architecture

### Directory Structure

- `machines/hyper/` - Complete server configuration (all-in-one)
- `modules/traefik/` - Reverse proxy configuration module
- `secrets/` - SOPS-encrypted secrets files

### Key Concepts

- **Flake-based Configuration**: Uses Nix flakes with inputs like nixpkgs, sops-nix, disko, cf-ddns, pushr
- **Single Server Setup**: Configuration focused on the `hyper` server only
- **Secrets Management**: Uses SOPS-nix with age encryption, keys stored in `machines/hyper/keys/`

### Special Args

Global configuration is stored in `special_args.json` containing username, email, domain, and hetzner_user for storage box access.

**Security Note**: This file contains sensitive information required during NixOS evaluation (before SOPS initialization). It uses a pre-commit/post-commit hook system:
- **Pre-commit**: Automatically encrypts `special_args.json` before git commit  
- **Post-commit**: Automatically decrypts `special_args.json` for local development
- The file is stored encrypted in git but available decrypted locally for builds

### Hyper Server Configuration

The hyper server (`machines/hyper/`) contains:
- `default.nix` - Complete server configuration (all common + specific config)
- `keys/` - SSH host keys and age public keys for SOPS
- Service-specific configurations:
  - `adguard.nix` - DNS filtering
  - `ddns.nix` - Dynamic DNS with Cloudflare
  - `disko.nix` - Disk partitioning
  - `firewall.nix` - Network security rules
  - `libvrit.nix` - Virtualization
  - `minio.nix` - Object storage
  - `nfs.nix` - Network file sharing
  - `snapraid.nix` - Storage protection

### Services

The hyper server runs:
- **Traefik** - Reverse proxy for web services
- **AdGuard Home** - Network-wide DNS filtering  
- **MinIO** - S3-compatible object storage
- **NFS** - Network file sharing
- **Unifi Controller** - Network management
- **Tailscale** - VPN networking
- **SnapRAID** - Storage parity protection