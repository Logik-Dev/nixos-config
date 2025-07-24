{
  config,
  ...
}:
{

  services.k3s = {
    enable = true;
    tokenFile = config.sops.secrets.k3s-token.path;
    clusterInit = true;
    extraFlags = [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable=traefik"
      "--disable-kube-proxy"
    ];

  };


  networking.firewall.allowedTCPPorts = [
    6443
    2049
  ];

}
