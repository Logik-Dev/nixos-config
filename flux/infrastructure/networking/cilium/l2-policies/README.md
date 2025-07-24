# L2 Announcement Policies

This directory will contain the L2 announcement policies for Cilium.

## Future Configuration

When ready to configure L2 announcement for VLAN12 ingress, create:

1. **CiliumLoadBalancerIPPool** - Define IP ranges for LoadBalancer services
2. **CiliumL2AnnouncementPolicy** - Configure L2 announcement rules for VLAN12

## Example Structure

```yaml
# cilium-lb-pool-vlan12.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: vlan12-ingress-pool
spec:
  cidrs:
  - cidr: "192.168.12.100/28"  # Example IP range for VLAN12

---
# cilium-l2-policy-vlan12.yaml  
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: vlan12-ingress-policy
spec:
  loadBalancerIPs: true
  interfaces:
  - "vlan12-ingress"
  nodeSelector:
    matchLabels: {}
```

This will be configured later according to your VLAN12 requirements.