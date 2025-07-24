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

  # Deploy Cilium manifests via K3s static manifests directory
  environment.etc."rancher/k3s/server/manifests/cilium.yaml".source = ./cilium-native-manifest.yaml;

  networking.firewall.allowedTCPPorts = [
    6443
    2049
  ];

}
