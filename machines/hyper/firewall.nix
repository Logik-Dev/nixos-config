{
  networking.firewall.enable = false;
  networking.nftables.enable = true;

  networking.nftables.ruleset = ''
    table inet filter {
      chain input {
        type filter hook input priority 0; policy drop;

        # Loopback
        iifname "lo" accept

        # Connexions établies
        ct state established,related accept

        # SSH uniquement sur management
        iifname "management" tcp dport 22 accept

        # SSH for QEMU on tailscale0 
        iifname "tailscale0" tcp dport 22 accept 

        # HTTPS sur Management
        iifname "management" tcp dport 443 accept
        iifname "management" udp dport 443 accept

        # HTTPS sur VLAN Gateway
        iifname "vlan200-gateway" tcp dport 443 accept
        iifname "vlan200-gateway" udp dport 443 accept

        # HTTPS sur Tailscale
        iifname "tailscale0" tcp dport 443 accept

        # DHCP si nécessaire
        udp dport { 67, 68 } accept

        # AdGuard Home DNS sur management
        iifname "management" udp dport 53 accept
        iifname "management" tcp dport 53 accept

        # AdGuard Home DNS sur tailscale0
        iifname "tailscale0" udp dport 53 accept
        iifname "tailscale0" tcp dport 53 accept

        # Unifi sur management
        iifname "management" tcp dport { 6789, 8080 } accept
        iifname "management" udp dport { 3478, 10001 } accept

        # NFSv4 sur management
        iifname "management" tcp dport { 111, 2049 } accept
        iifname "management" udp dport { 111, 2049 } accept

        # nix-serve accessible depuis LAN privé
        ip saddr 192.168.0.0/16 tcp dport 5000 accept

        # Ping / ICMPv6
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;

        # Forward Tailscale → LAN
        iifname "tailscale0" oifname "management" accept

        # Réponses LAN → Tailscale
        iifname "management" oifname "tailscale0" ct state established,related accept
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }

    table ip nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;

        # Masquerade le trafic Tailscale vers le LAN
        oifname "management" ip saddr 100.64.0.0/10 masquerade
      }
    }
  '';
}
