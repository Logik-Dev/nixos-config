# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS configuration repository that manages a homelab infrastructure with multiple machines and services. The infrastructure is defined using Nix flakes and includes container/VM management, secrets management with SOPS, and Terraform for cloud deployment.

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

## Architecture

### Directory Structure

- `machines/` - Individual machine configurations, organized by hostname
- `modules/` - Reusable NixOS modules for common functionality
- `secrets/` - SOPS-encrypted secrets files per machine/service
- `deployments/` - Terraform configuration for cloud infrastructure
- `scripts/` - Nix scripts for automation (machine-add, rebuild-target, etc.)

### Key Concepts

- **Flake-based Configuration**: Uses Nix flakes with inputs like nixpkgs, home-manager, sops-nix, disko
- **Machine Discovery**: Hosts are defined in `deployments/machines.json` and loaded via `modules/homelab/default.nix`
- **Secrets Management**: Uses SOPS-nix with age encryption, keys stored in `machines/<hostname>/keys/`
- **Multi-platform Support**: Supports bare-metal, containers, and VMs via different deployment methods

### Special Args

Global configuration is stored in `special_args.json` containing username, email, domain, and cloud provider details. These are passed to all NixOS configurations.

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