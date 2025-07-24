{ ... }:
{
  networking.firewall.allowedUDPPorts = [ 5353 ];
  services.avahi = {
    enable = true;
    nssmdns = true;

    reflector = true;
    allowInterfaces = [
      "enp5s0"
      "enp4s0.21"
    ];

    publish = {
      enable = true;
      workstation = true;
      userServices = true;
    };
  };
}
