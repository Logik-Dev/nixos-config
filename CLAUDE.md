# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS configuration repository that manages a homelab infrastructure with multiple machines and services. The infrastructure is defined using Nix flakes and includes container/VM management, secrets management with SOPS, Terraform for cloud deployment, and GitOps with FluxCD for Kubernetes cluster management.

## Common Commands

### Building and Deploying

- `nixos-rebuild switch --flake .#<hostname>` - Build and switch to configuration for local host
- `task rebuild-root-<hostname>` - Deploy configuration to remote host as root
- `task rebuild-user-<hostname>` - Deploy configuration to remote host as user with sudo
- `nix run .#rebuild-target <hostname>` - Alternative way to rebuild remote target

### Machine Management

- `nix run .#machine-add <hostname>` - Add a new machine to the infrastructure
- `task add-host-<hostname>` - Initialize SSH keys, folders and secrets for new host
- `task create-vm-<hostname>` - Create VM, copy SSH keys and rebuild configuration
- `task create-container-<hostname>` - Create container and deploy configuration

### Image Building

- `nix run .#image-builder` - Build VM/container images
- `nix build .#packages.x86_64-linux.vm-base` - Build base VM image

### Secrets Management

- `nix run .#sops-config-gen` - Generate .sops.yaml configuration file
- `sops secrets/<file>.yaml` - Edit encrypted secrets files

### Development Tasks

- `task` or `task --list-all` - List all available tasks
- `nix flake update` - Update flake inputs
- `nix flake check` - Validate flake configuration

### GitOps and Kubernetes

- `flux bootstrap github --owner=Logik-Dev --repository=Nixos --branch=main --path=./flux/clusters/k3s --personal` - Bootstrap FluxCD on K3s cluster
- `kubectl get gateways` - Check Gateway API status
- `kubectl get certificates -A` - Check cert-manager certificate status
- `kubectl logs -n cert-manager -l app=cert-manager` - Check cert-manager logs

## Architecture

### Directory Structure

- `machines/` - Individual machine configurations, organized by hostname
- `modules/` - Reusable NixOS modules for common functionality
- `secrets/` - SOPS-encrypted secrets files per machine/service
- `deployments/` - Terraform configuration for cloud infrastructure (state files are SOPS-encrypted)
- `flux/` - GitOps configuration for K3s cluster with FluxCD
- `scripts/` - Nix scripts for automation (machine-add, rebuild-target, etc.)

### Key Concepts

- **Flake-based Configuration**: Uses Nix flakes with inputs like nixpkgs, home-manager, sops-nix, disko
- **Machine Discovery**: Hosts are defined in `deployments/machines.json` and loaded via `modules/homelab/default.nix`
- **Secrets Management**: Uses SOPS-nix with age encryption, keys stored in `machines/<hostname>/keys/`
- **Multi-platform Support**: Supports bare-metal, containers, and VMs via different deployment methods
- **GitOps**: FluxCD manages K3s cluster state from `flux/` directory
- **Gateway API**: Cloud-native ingress with automatic HTTPS/TLS via cert-manager
- **Certificate Management**: Let's Encrypt integration with Cloudflare DNS challenge for wildcard certificates

### Special Args

Global configuration is stored in `special_args.json` containing username, email, domain, and cloud provider details (including `hetzner_user`). These are passed to all NixOS configurations.

**Security Note**: This file contains sensitive information required during NixOS evaluation (before SOPS initialization). It uses a pre-commit/post-commit hook system:
- **Pre-commit**: Automatically encrypts `special_args.json` before git commit
- **Post-commit**: Automatically decrypts `special_args.json` for local development
- The file is stored encrypted in git but available decrypted locally for builds
- This ensures secrets are available early in the NixOS evaluation process while maintaining security

### Host Configuration Pattern

Each machine in `machines/<hostname>/` contains:
- `default.nix` - Main NixOS configuration
- `keys/` - SSH host keys and age public keys for SOPS
- Machine-specific service configurations

### Shared Modules

- `modules/backups/` - Backup service configuration
- `modules/homelab/` - Host discovery and networking
- `modules/traefik/` - Reverse proxy configuration
- `modules/neovim/` - Neovim configuration with Lua
- `modules/k3s/` - Kubernetes cluster configuration

### FluxCD Structure

- `flux/clusters/k3s/` - Cluster-specific FluxCD configuration
- `flux/infrastructure/cert-manager/` - TLS certificate management with Let's Encrypt
- `flux/infrastructure/networking/` - Gateway API configuration with HTTPS ingress
- `flux/apps/` - Application deployments and services

### TLS Certificate Domains

- `*.ingress.logikdev.fr` - VLAN12 gateway (192.168.12.100) for general ingress
- `*.iot.logikdev.fr` - VLAN21 gateway (192.168.21.240) for IoT services