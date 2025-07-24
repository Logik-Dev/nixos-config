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
│   └── networking/
│       └── cilium/         # Cilium configuration with L2 Announcement
└── apps/                   # Business applications
```

## Cilium Configuration

Cilium is configured to replace MetalLB with the following features:
- **L2 Announcement**: LoadBalancer IP announcement at Layer 2
- **Kube-proxy replacement**: Cilium replaces kube-proxy
- **Hubble**: Network observability
- **Future VLAN12**: Support for ingress on VLAN12

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
   - Infrastructure components
   - Defined applications

## L2 Announcement (To be configured later)

L2 rules for VLAN12 ingress will be added via:
- `CiliumLoadBalancerIPPool` to define IP ranges
- `CiliumL2AnnouncementPolicy` for announcement rules on VLAN12

## Monitoring

Hubble UI will be accessible to observe network traffic and diagnose connectivity issues.