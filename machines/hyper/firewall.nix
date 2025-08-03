{
  pkgs,
  config,
  ...
}:
{
  # Disable standard NixOS iptables firewall to avoid conflicts with nftables
  networking.firewall.enable = false;

  networking.nftables.enable = true;
  networking.nftables.ruleset = ''
    table inet filter {
      chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow loopback
        iifname "lo" accept
        
        # Allow established and related traffic
        ct state established,related accept
        
        # Allow SSH
        tcp dport 22 accept
        
        # Allow HTTP/HTTPS for Traefik
        tcp dport { 80, 443 } accept
        udp dport 443 accept
        
        # Allow Incus management
        tcp dport { 8443, 8444 } accept
        
        # Allow DHCP
        udp dport { 67, 68 } accept
        
        # Allow WireGuard
        udp dport 51820 accept
        iifname "wg0" accept
        
        # Allow AdGuard Home DNS on enp5s0
        iifname "enp5s0" udp dport 53 accept
        iifname "enp5s0" tcp dport 53 accept
        
        # Allow NFS server on enp5s0 (NFSv4 only)
        iifname "enp5s0" tcp dport { 111, 2049 } accept
        iifname "enp5s0" udp dport { 111, 2049 } accept
        
        # Allow NixOS cache (nix-serve) from local network
        ip saddr 192.168.0.0/16 tcp dport 5000 accept
        
        # Allow PostgreSQL
        iifname "enp5s0" tcp dport 5432 accept
        
        # Allow traffic on Incus bridges
        iifname { "vlan11-k8s", "vlan12-ingress", "vlan21-iot" } accept
        
        # Allow ping
        icmp type echo-request accept
        icmpv6 type echo-request accept
      }
      
      chain forward {
        type filter hook forward priority 0; policy accept;
        
        # Allow forwarding for Incus bridges
        iifname { "vlan11-k8s", "vlan12-ingress", "vlan21-iot" } accept
        oifname { "vlan11-k8s", "vlan12-ingress", "vlan21-iot" } accept
        
        # Allow WireGuard forwarding
        iifname "wg0" accept
        oifname "wg0" accept
      }
      
      chain output {
        type filter hook output priority 0; policy accept;
      }
    }

    table inet nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        
        # Masquerading for WireGuard to enp5s0
        ip saddr 10.11.11.0/24 oifname "enp5s0" masquerade
      }
    }
  '';
}
