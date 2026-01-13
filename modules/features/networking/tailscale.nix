{
  flake.modules.homeManager.desktop = {
    services.tailscale-systray.enable = true;
  };

  flake.modules.nixos.common =
    { config, hostSecret, ... }:
    {
      age.secrets.tailscale.rekeyFile = hostSecret "tailscale";
      services.tailscale = {
        enable = true;
        authKeyFile = config.age.secrets.tailscale.path;
      };
    };

  flake.modules.nixos.hyper = {
    networking.firewall.allowedTCPPorts = [ 5432 ];
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
