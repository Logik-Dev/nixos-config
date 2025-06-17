{ ... }:
{

  services.victorialogs.enable = true;
  networking.firewall.allowedTCPPorts = [ 9428 ];

}
