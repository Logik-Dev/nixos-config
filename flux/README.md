# FluxCD GitOps Configuration

This directory contains the GitOps configuration for the K3s cluster using FluxCD.

## Architecture

```
flux/
├── clusters/k3s/           # K3s cluster specific configuration
│   ├── flux-system/        # FluxCD base components
│   ├── infrastructure.yaml # Infrastructure kustomization
│   └── apps.yaml          # Applications kustomization
├── infrastructure/         # Infrastructure as Code
│   ├── cert-manager/       # TLS certificate management
│   └── networking/         # Network configuration (Cilium + Gateways)
└── apps/                   # Business applications
```

## Certificate Management

The cluster uses cert-manager with Let's Encrypt for automatic TLS certificate provisioning:
- **DNS Challenge**: Cloudflare DNS-01 challenge for wildcard certificates
- **Domains**: `*.ingress.logikdev.fr` and `*.iot.logikdev.fr`
- **Issuer**: ClusterIssuer configured for Let's Encrypt production

## Network Configuration

### Cilium CNI
Cilium is configured to replace MetalLB with the following features:
- **L2 Announcement**: LoadBalancer IP announcement at Layer 2
- **Kube-proxy replacement**: Cilium replaces kube-proxy
- **Hubble**: Network observability

### Gateway API
Two HTTPS gateways provide ingress for different VLANs:
- **VLAN12 Gateway** (`192.168.12.100`): `*.ingress.logikdev.fr`
- **VLAN21 Gateway** (`192.168.21.240`): `*.iot.logikdev.fr`

## Installation

1. Install FluxCD on the cluster:
```bash
flux bootstrap github \
  --owner=Logik-Dev \
  --repository=Nixos \
  --branch=main \
  --path=./flux/clusters/k3s \
  --personal
```

2. FluxCD will automatically deploy:
   - Cilium with L2 Announcement
   - cert-manager with Let's Encrypt integration
   - HTTPS Gateway configurations
   - Infrastructure components
   - Defined applications

## TLS Certificate Workflow

1. **Gateway Creation**: Gateways are annotated with `cert-manager.io/cluster-issuer: letsencrypt`
2. **DNS Challenge**: cert-manager uses Cloudflare API token for DNS-01 challenge
3. **Certificate Issuance**: Let's Encrypt issues wildcard certificates for both domains
4. **Automatic Renewal**: cert-manager handles certificate renewal automatically

## Monitoring

Hubble UI will be accessible to observe network traffic and diagnose connectivity issues.