{
  config,
  hosts,
  ...
}:
{
  imports = [
    ../../modules/k3s
  ];

  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-token.path;
    serverAddr = "https://${hosts.k3s-control-plane.ipv4}:6443";
  };

}
