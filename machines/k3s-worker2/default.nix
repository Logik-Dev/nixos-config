{
  config,
  hostname,
  hosts,
  ...
}:
{

  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-token.path;
    serverAddr = "https://${hosts.k3s-control-plane.ipv4}:6443";
  };

  networking.firewall.allowedTCPPorts = [
    10250 # kubelet API
    2049 # NFS (if needed for storage)
  ];

  networking.firewall.allowedUDPPorts = [
    8472 # flannel vxlan (if used)
  ];

}
