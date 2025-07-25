{
  pkgs,
  ...
}:

{
  # Kernel modules required for Cilium and K3s
  boot.kernelModules = [
    "iptable_mangle"
    "iptable_raw"
    "xt_socket"
    "ip_tables"
    "iptable_filter"
    "iptable_nat"
    "nf_nat"
    "x_tables"
  ];

  # Ensure modules are loaded at boot
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  # Required packages for K3s
  environment.systemPackages = with pkgs; [
    iptables
    conntrack-tools
  ];

  # Firewall configuration for K3s
  networking.firewall = {
    enable = false; # Disabled to avoid conflicts with K3s
  };
}

