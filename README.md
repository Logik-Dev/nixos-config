# NixOS Homelab Configuration

This repository contains a comprehensive NixOS configuration for managing a homelab infrastructure with multiple machines, services, and a Kubernetes cluster.

## 🏗️ Architecture

### Infrastructure Overview
- **Hypervisor**: `hyper` - Main bare-metal server running consolidated services
- **Kubernetes**: `k3s-control-plane`, `k3s-worker1`, `k3s-worker2` - Distributed k3s cluster
- **Development**: `sonicmaster` - Development workstation

### Services
- **Reverse Proxy**: Traefik with Cloudflare integration
- **DNS**: AdGuard Home for network-wide ad blocking
- **VPN**: WireGuard for secure remote access
- **Media**: Containerized media services via Docker
- **Security**: Vaultwarden password manager
- **Backups**: Automated backup system with Borg

## 🚀 Quick Start

### Prerequisites
- NixOS with flakes enabled
- SSH access to target machines
- SOPS for secrets management

### Common Commands

```bash
# Build and deploy to local machine
nixos-rebuild switch --flake .#<hostname>

# Deploy to remote machine
nix run .#rebuild-target <hostname>

# Build container/VM images
nix run .#image-builder

# Edit secrets
sops secrets/<file>.yaml
```

## 🔐 Secrets Management

This project uses two complementary approaches for secrets:

### 1. SOPS-nix (Runtime Secrets)
- Encrypted with age keys stored in `machines/<hostname>/keys/age.pub`
- Decrypted at runtime by systemd services
- Used for service credentials, API keys, passwords

### 2. Special Args (Build-time Secrets)
- File: `special_args.json` (encrypted in git, decrypted locally)
- Contains domain names, usernames, email addresses
- Required during NixOS evaluation before SOPS initialization
- Automatically encrypted/decrypted via git hooks

## 📁 Directory Structure

```
├── deployments/          # Terraform infrastructure definitions
│   ├── machines.json     # Machine inventory and networking
│   ├── networks.tf       # Incus network configurations
│   └── profiles.tf       # Container/VM profiles
├── machines/             # Individual machine configurations
│   ├── common/           # Shared configuration across all machines
│   ├── hyper/            # Main hypervisor with consolidated services
│   ├── k3s-*/            # Kubernetes cluster nodes
│   └── sonicmaster/      # Development workstation
├── modules/              # Reusable NixOS modules
│   ├── traefik/          # Reverse proxy configuration
│   ├── backups/          # Backup system
│   └── neovim/           # Development environment
├── secrets/              # SOPS-encrypted secrets
└── scripts/              # Automation scripts
```

## 🔧 Development

This repository includes Claude Code configuration for AI-assisted development:
- `.claude/` - Claude Code settings
- `CLAUDE.md` - Detailed guidance for AI assistants

## 🛠️ Infrastructure as Code

- **NixOS**: Declarative system configuration
- **Terraform**: Infrastructure provisioning (Incus containers/VMs)
- **SOPS**: Secrets management with age encryption
- **Flakes**: Reproducible builds and dependency management

## 📖 Documentation

For detailed information, see [CLAUDE.md](./CLAUDE.md) which contains:
- Complete command reference
- Architecture deep-dive
- Development workflows
- Troubleshooting guides
