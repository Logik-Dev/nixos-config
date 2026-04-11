{

  flake.modules.darwin.common = {
    # Must be set to configure DNS
    networking.knownNetworkServices = [
      "Thunderbolt Bridge"
      "Wi-Fi"
    ];
    services.tailscale = {
      enable = true;
      overrideLocalDns = true;
    };
  };

  flake.modules.nixos.common =
    { config, ... }:
    {
      services.tailscale = {
        enable = true;
        authKeyFile = config.age.secrets.tailscale.path;
      };
    };

  flake.modules.nixos.hyper = {
    networking.firewall.allowedTCPPorts = [ 5432 ];

    notify.services = [ "tailscale" ];

    services.tailscale = {
      useRoutingFeatures = "both";
      extraUpFlags = [ "--ssh" ];
      extraSetFlags = [ "--advertise-routes=192.168.10.0/24,192.168.21.0/24" ];
    };
  };

  flake.modules.nixos.sonicmaster = {
    services.tailscale = {
      useRoutingFeatures = "client";
      extraUpFlags = [ "--accept-routes" ];
    };
  };
}
